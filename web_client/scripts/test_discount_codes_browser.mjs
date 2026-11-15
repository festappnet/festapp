#!/usr/bin/env node
import assert from 'node:assert/strict';
import path from 'node:path';
import {readFile} from 'node:fs/promises';
import {createServer} from 'vite';
import {createNativeBrowser} from './native_browser.mjs';

const root = path.resolve(import.meta.dirname, '..');
const owner = await createNativeBrowser();
let server;
try {
    server = await createServer({root, configFile:false, logLevel:'error', server:{host:'127.0.0.1',port:0}, plugins:[{name:'discount-fixture',configureServer(s) {
        s.middlewares.use(async (req,res,next) => {
            if (req.url?.startsWith('/form/test')) {
                res.setHeader('content-type','text/html; charset=utf-8');
                return res.end('<!doctype html><html><head><meta name="color-scheme" content="light"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><main></main><script type="module" src="/tests/fixtures/discount_codes/host.js"></script></body></html>');
            }
            const match = req.url?.match(/^\/assets\/translations\/(cs|en)\.json$/);
            if (!match) return next();
            res.setHeader('content-type','application/json'); res.end(await readFile(path.resolve(root, '../assets/translations', `${match[1]}.json`)));
        });
    }}]});
    await server.listen();
    const origin = `http://127.0.0.1:${server.httpServer.address().port}`;
    owner.allow(origin);
    const context = await owner.context(); const page = await context.newPage();
    await owner.setTopLevelColorScheme(page,'light');
    const quote = {data:{code:200,quote:{code:'SAVE',base:1000,discount:250,net:750,currency:'CZK',fingerprint:'fixture-fingerprint'}},error:null};
    for (const [lang,labels] of Object.entries({cs:{prompt:'Máte slevový kód?',apply:'Uplatnit',busy:'Ověřování kódu…',invalid:'Kód nelze pro tento výběr použít. Zkontrolujte jej nebo odeberte.',retry:'Zkusit znovu',remove:'Odebrat',net:'Cena po slevě',changed:'Cena nebo platnost slevy se změnila. Zkontrolujte objednávku znovu.'},en:{prompt:'Have a discount code?',apply:'Apply',busy:'Checking code…',invalid:'This code cannot be used for this selection. Check or remove it.',retry:'Try again',remove:'Remove',net:'Discounted price',changed:'The price or discount eligibility changed. Review your order again.'}})) {
        await page.goto(`${origin}/form/test?lang=${lang}`); await page.waitForFunction('window.fixtureReady');
        const details=page.locator('details'); const status=details.locator('[role=status]');
        assert.equal(await details.locator('summary').innerText(),labels.prompt); assert.equal(await details.getAttribute('open'),null);
        await details.locator('summary').click();
        const input=details.locator('input'); const apply=details.getByRole('button',{name:labels.apply});
        await input.fill('SAVE'); await apply.click();
        assert.equal(await status.innerText(),labels.busy); assert.equal(await apply.isDisabled(),true);
        assert.equal(await page.evaluate('window.calls[0].discount.code'),'SAVE');
        await page.evaluate(value=>window.resolveQuote(value),quote);
        await page.waitForFunction(() => window.fixture.discount.valid && !document.querySelector('details button').disabled);
        assert.match(await status.innerText(),new RegExp(labels.net));
        if (lang === 'en') {
            const expected = await page.evaluate(() => new Intl.NumberFormat('en', {style:'currency',currency:'CZK',minimumFractionDigits:0,maximumFractionDigits:2}).format(750));
            assert.ok((await status.innerText()).includes(expected), 'English status uses the English currency format');
        }
        assert.match(await page.locator('#floating-price-widget').innerText(),/750/);
        assert.equal(await page.evaluate('window.fixture.session.payload.discount.fingerprint'),'fixture-fingerprint');
        await page.screenshot({path:`/tmp/festapp-discount-${lang}.png`});
        await page.evaluate('window.showReview()');
        const review=page.locator('#order-preview-overlay');
        assert.match(await review.locator('.preview-total-price').innerText(),/750/);
        assert.match(await review.locator('.preview-total-price').innerText(),/SAVE/);
        await review.locator('.btn-submit-order').click();
        assert.equal(await page.evaluate('window.paymentQuote.quote.amountMinor'),75000);
        assert.equal(await page.evaluate('window.paymentQuote.quote.currency'),'CZK');
        await page.screenshot({path:`/tmp/festapp-discount-review-${lang}.png`});
        await page.evaluate(() => { document.querySelector('#order-preview-overlay').remove(); document.body.style.overflow=''; });
        await page.evaluate('window.changeSelection()');
        assert.equal(await page.evaluate('Boolean(window.fixture.discount.valid)'),false);
        assert.equal(await status.innerText(),labels.changed);
        assert.equal(await page.evaluate('window.fixture.session.payload.discount.fingerprint'),'fixture-fingerprint');
        assert.match(await page.locator('#floating-price-widget').innerText(),/1\s?000|1000/);
        await details.getByRole('button',{name:labels.remove}).click();
        assert.equal(await input.inputValue(),''); assert.equal(await status.innerText(),'');
        assert.equal(await page.evaluate('window.fixture.session.payload.discount === undefined'),true);
        await input.fill('BAD'); await apply.click();
        await page.evaluate(() => window.resolveQuote({data:{code:400,reason:'invalid'},error:null}));
        await page.waitForFunction(expected => document.querySelector('details [role=status]').textContent === expected,labels.invalid);
        assert.equal(await apply.isDisabled(),false);
        // Fresh navigation isolates history and pending storage for the transport replay.
        await page.goto(`${origin}/form/test?lang=${lang}`); await page.waitForFunction('window.fixtureReady');
        await page.evaluate('window.startRetryFixture()');
        const result=page.locator('.fullscreen-result-overlay');
        const retry=result.getByRole('button',{name:labels.retry});
        await retry.waitFor();
        assert.equal(await page.evaluate('location.hash'),'#order-result');
        assert.equal(await page.evaluate('window.retryFixture.sent.length'),1);
        await page.evaluate(() => { window.retryFixture.session.payload.ticket = [{id:99}]; });
        await retry.click();
        await page.waitForFunction(() => window.retryFixture.sent.length === 2 && window.retryFixture.counts.completed === 1);
        const replay = await page.evaluate('window.retryFixture');
        assert.deepEqual(replay.sent[1],replay.sent[0]);
        assert.equal(replay.counts.preflight,1);
        assert.equal(replay.counts.retryStartedAfterClose,true);
        assert.equal(replay.sent.length,2);
        assert.equal(await page.evaluate('window.calls.length'),0);
        assert.equal(await page.locator('.fullscreen-result-overlay').count(),1);
        assert.equal(await page.evaluate('location.hash'),'#order-result');
    }
    // The responsive contract runs against the real application styles and local fixture.
    const visualErrors = [];
    page.on('pageerror', error => visualErrors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') visualErrors.push(message.text()); });
    for (const [viewport, size] of Object.entries({desktop:{width:1280,height:900},mobile:{width:390,height:844}})) {
        await page.setViewportSize(size);
        for (const [lang, labels] of Object.entries({cs:{apply:'Uplatnit',remove:'Odebrat'},en:{apply:'Apply',remove:'Remove'}})) {
            await page.goto(`${origin}/form/test?lang=${lang}`); await page.waitForFunction('window.fixtureReady');
            const details = page.locator('details');
            await details.locator('summary').click();
            await details.locator('input').fill('SAVE');
            const apply = details.getByRole('button',{name:labels.apply});
            const remove = details.getByRole('button',{name:labels.remove});
            await apply.click(); await page.evaluate(value => window.resolveQuote(value), quote);
            await page.waitForFunction(() => window.fixture.discount.valid && !document.querySelector('details button').disabled);
            const a = await apply.boundingBox(), b = await remove.boundingBox();
            assert.ok(a && b, `${viewport}/${lang}: both actions are visible`);
            const horizontal = Math.max(b.x - a.x - a.width, a.x - b.x - b.width);
            const vertical = Math.max(b.y - a.y - a.height, a.y - b.y - b.height);
            assert.ok(horizontal >= 8 || vertical >= 8, `${viewport}/${lang}: action gap must be at least 8px, got horizontal ${horizontal}, vertical ${vertical}`);
            assert.ok(a.x >= 0 && b.x >= 0 && a.x+a.width <= size.width && b.x+b.width <= size.width, `${viewport}/${lang}: actions fit viewport`);
            await page.screenshot({animations:'disabled',path:`/tmp/festapp-discount-polish-${viewport}-${lang}.png`});
            await page.evaluate('window.showReview()');
            const review = page.locator('#order-preview-overlay');
            await review.locator('.preview-total-price').waitFor();
            const layout = await review.locator('.preview-discount-summary').evaluate(summary => {
                const rows = [...summary.querySelectorAll('.preview-discount-row')].map(row => {
                    const [label, amount] = row.querySelectorAll('span');
                    const l = label.getBoundingClientRect(), a = amount.getBoundingClientRect();
                    return {left:l.left, right:a.right, gap:a.left-l.right, weight:Number(getComputedStyle(row).fontWeight)};
                });
                return {rows, align:getComputedStyle(summary).textAlign, codeWeight:Number(getComputedStyle(summary.querySelector('.preview-discount-code')).fontWeight)};
            });
            assert.equal(layout.rows.length,3,`${viewport}/${lang}: three review rows`);
            assert.ok(layout.rows.every(row => row.gap >= 8),`${viewport}/${lang}: review labels and amounts do not overlap`);
            assert.ok(layout.rows.every(row => Math.abs(row.left-layout.rows[0].left) < 1 && Math.abs(row.right-layout.rows[0].right) < 1),`${viewport}/${lang}: review columns align`);
            assert.notEqual(layout.align,'center',`${viewport}/${lang}: review is not centered text`);
            assert.ok(layout.rows[2].weight >= 600 && layout.rows[2].weight > layout.rows[0].weight && layout.rows[2].weight > layout.codeWeight,`${viewport}/${lang}: total is emphasized`);
            await page.screenshot({animations:'disabled',path:`/tmp/festapp-discount-polish-review-${viewport}-${lang}.png`});
        }
    }
    assert.deepEqual(visualErrors, [], 'responsive browser console/page errors');
    console.log('PASS: CZ/EN discount UI, quote busy/error/removal, selection invalidation, floating/review net price and payment quote and retry history/replay (stub transports)');
} finally { try { await owner.close(); } finally { await server?.close(); } }
