#!/usr/bin/env node
import {timed} from './test_timings.mjs';
// Real browser + real SQL; local transport adapter replaces the Edge/REST gateway.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import pg from 'pg';
import { createServer } from 'vite';
import {createNativeBrowser} from './native_browser.mjs';

assert.ok(process.env.SEAT_CHECKOUT_DATABASE_URL, 'Set SEAT_CHECKOUT_DATABASE_URL to the bootstrapped local test database');
const url = new URL(process.env.SEAT_CHECKOUT_DATABASE_URL);
assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(url.hostname), 'Browser fixtures require a loopback database');
const root = path.resolve(import.meta.dirname, '..');
const owner=await createNativeBrowser();let context,page;
const db = new pg.Client({ connectionString: url.href });
let server,fixture,checkout;
const calls=[];const offlineRecovery=process.argv.includes('--offline-recovery');
try {
    await db.connect();
    const identity = await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
    assert.equal(identity.rowCount, 1, 'Require the bootstrap marker of a disposable test database');
    await db.query('BEGIN');
    await db.query("SELECT set_config('festapp.email_wake','scheduled',true), set_config('request.jwt.claim.sub','',true), set_config('request.jwt.claim.role','anon',true)");
    const setup = await db.query(await readFile(path.join(root, 'tests/fixtures/seat_checkout/setup.sql'), 'utf8'));
    fixture = setup.at(-1).rows[0].fixture;
    const rpc = {
        get_form_by_link: ['SELECT public.get_form_by_link($1::jsonb) AS result', a => [a.input_data]],
        get_form_measurement_policy: ['SELECT public.get_form_measurement_policy($1) AS result', a => [a.p_form_link]],
        get_blueprint: ['SELECT public.get_blueprint($1,$2,$3) AS result', a => [a.my_secret, a.form_key, a.blueprint_id]],
        select_spot: ['SELECT public.select_spot($1,$2,$3,$4) AS result', a => [a.form_key, a.secret_id, a.spot_id, a.selecting]],
        'send-ticket-order': ['SELECT public.create_ticket_order_client_sync_v1($1,$2,$3) AS result', a => [a.orderDetails, a.commandId, a.clientId]],
    };
    let rpcQueue = Promise.resolve();
    const handleRpc = async (req, res, next) => {
        if (req.url === '/assets/translations/cs.json') {
            res.setHeader('Content-Type', 'application/json');
            res.end(await readFile(path.join(root, '../assets/translations/cs.json')));
            return;
        }
        if (req.url !== '/__seat_checkout_rpc') return next();
        res.setHeader('Content-Type', 'application/json');
        let body = '';
        for await (const chunk of req) body += chunk;
        const operation = rpcQueue.then(async () => {
            let savepoint = false;
            try {
                const { name, args } = JSON.parse(body);
                assert.ok(Object.hasOwn(rpc, name), `Unexpected RPC ${name}`);
                const [sql, parameters] = rpc[name];
                calls.push(name);
                if (name === 'select_spot') await new Promise(resolve => setTimeout(resolve, 250));
                await db.query('SAVEPOINT browser_rpc'); savepoint = true;
                await db.query('SET LOCAL ROLE anon');
                const result = (await db.query(sql, parameters(args))).rows[0].result;
                await db.query('RESET ROLE');
                await db.query('RELEASE SAVEPOINT browser_rpc'); savepoint = false;
                let data = result;
                if (name === 'send-ticket-order') {
                    checkout = { payload: args.orderDetails, result: result.data };
                    data = result.data.code === 200 ? { code: 200, ticketOrder: result.data } : result.data;
                }
                res.end(JSON.stringify({ data, error: null }));
            } catch (error) {
                if (savepoint) await db.query('ROLLBACK TO SAVEPOINT browser_rpc');
                res.end(JSON.stringify({ data: null, error: { message: error.message } }));
            }
        });
        rpcQueue = operation.catch(() => {});
        await operation;
    };
    server = await createServer({ root, server: { host: '127.0.0.1', port: 0, strictPort: true }, logLevel: 'error',
        plugins: [{ name: 'seat-checkout-fixture', configureServer(server) { server.middlewares.use(handleRpc); } }] });
    await timed('browser.server-start', () => server.listen(), {suite: 'seat_checkout_browser'});
    const port = server.httpServer.address().port;
    const origin=`http://127.0.0.1:${port}`;owner.allow(origin);context=await owner.context();page=await context.newPage();await owner.setTopLevelColorScheme(page,'light');page.setDefaultTimeout(8000);
    await page.goto(`${origin}/tests/fixtures/seat_checkout/index.html`);
    assert.equal(context.pages().length,1,'Use an isolated local browser');
    await page.locator(`input[name="${fixture.email}"]`).first().waitFor();
    await page.locator(`input[name="${fixture.email}"]`).first().fill('regression@example.invalid');
    await page.locator(`input[name="${fixture.name}"]`).first().fill('Test');
    await page.locator(`input[name="${fixture.surname}"]`).first().fill('Checkout');
    // The reserved .invalid fixture deliberately needs the real email-suffix
    // confirmation. Preserve that confirmation through seat-widget rerenders
    // and the offline recovery below instead of bypassing email validation.
    const suffixWarning = '[data-email-suffix-warning]:not([hidden])';
    await page.locator(suffixWarning).first().waitFor();
    await page.locator(`${suffixWarning} button`).first().click();
    await page.waitForFunction('!document.querySelector("[data-email-suffix-warning]:not([hidden])")');
    await page.locator('.btn-blueprint-select').first().click();
    const seatSelector = `.venue-layout-viewer svg g:nth-child(1 of [data-node-id="${fixture.node}"])`;
    await page.locator(seatSelector).first().waitFor();
    const controls = (await page.evaluate(`(() => {
        const modal=document.querySelector('.blueprint-modal-container');
        const list=modal.querySelector('.venue-layout-viewer > [role="list"]');
        const bounds=list.getBoundingClientRect();
        const button=modal.querySelector('.blueprint-btn-confirm');
        const b=button.getBoundingClientRect();
        return {listWidth:bounds.width,listHeight:bounds.height,
            buttons:modal.querySelectorAll(':scope > button').length,
            oldClass:button.className,buttonType:button.type,
            centered:Math.abs(b.x+b.width/2-innerWidth/2)<2,
            extraControls:!!modal.querySelector('.blueprint-modal-actions,.blueprint-state-legend')};
    })()`));
    assert.ok(controls.listWidth<=1 && controls.listHeight<=1, 'Assistive seat list must not be visible');
    assert.equal(controls.buttons,1,'Keep the original single Continue button');
    assert.equal(controls.oldClass,'btn btn-primary btn-submit blueprint-btn-confirm');
    assert.equal(controls.buttonType,'button');
    assert.equal(controls.centered,true,'Continue keeps its original centered placement');
    assert.equal(controls.extraControls,false,'No new footer actions or legend');

    await page.waitForFunction("document.querySelector('.blueprint-modal-container').getAnimations().every(a=>a.playState!=='running')");
    const fit=(await page.evaluate("document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')"));
    await page.locator('.blueprint-zoom-button:first-child').first().click();
    assert.notEqual((await page.evaluate("document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')")),fit);
    await page.locator('.blueprint-zoom-reset').first().click();
    const reset = (await page.evaluate("document.querySelector('.venue-layout-viewer svg').getAttribute('viewBox')"));
    const fitBounds = fit.trim().split(/\s+/).map(Number);
    const resetBounds = reset.trim().split(/\s+/).map(Number);
    assert.equal(fitBounds.length, 4);
    assert.equal(resetBounds.length, 4);
    // Equivalent fitted bounds can differ by floating-point rounding after zoom.
    resetBounds.forEach((value, index) => assert.ok(
        Number.isFinite(value) && Number.isFinite(fitBounds[index]) && Math.abs(value - fitBounds[index]) < 1e-6,
        `Reset restores fitted viewBox component ${index}: ${value} vs ${fitBounds[index]}`,
    ));
    const viewport="(() => {const s=document.querySelector('.venue-layout-viewer svg'),r=s.getBoundingClientRect();return JSON.stringify({x:r.x,y:r.y,width:r.width,height:r.height,camera:s.getAttribute('viewBox')})})()";
    const beforeClick=(await page.evaluate(viewport));
    await page.locator(seatSelector).first().click();
    await page.waitForFunction("document.querySelector('.blueprint-btn-confirm').disabled");
    assert.equal((await page.evaluate(viewport)),beforeClick,'Pending selection must not move or resize the map');
    await page.waitForFunction(`document.querySelector('.ticket-item[data-seat-id="${fixture.seat}"]') !== null`);
    // The seat appears optimistically. Wait for the real reservation response
    // before inspecting SQL on the fixture connection used by the RPC adapter.
    await page.waitForFunction("window.__seatCheckoutRpcResults?.has('select_spot') === true");
    assert.equal((await db.query('SELECT secret IS NOT NULL AS reserved FROM eshop.spots WHERE id=$1', [fixture.seat])).rows[0].reserved,
        true, 'The map click must reserve the actual SQL seat');
    assert.equal((await page.evaluate(viewport)),beforeClick,'Confirmed selection must retain camera and viewport');
    if (offlineRecovery) {
        await context.setOffline(true);
        // The selection marker covers the seat group after selection. Dispatch
        // a real pointer gesture at its center, as a buyer would tap it.
        const point = (await page.evaluate(`(() => {const r=document.querySelector(${JSON.stringify(seatSelector)}).getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`));
        await page.mouse.move(Math.round(point.x), Math.round(point.y));
        await page.mouse.down();
        await page.mouse.up();
        await page.waitForFunction("!document.querySelector('.blueprint-btn-confirm').disabled");
        // Connectivity returns before checkout. The lost release must not be
        // replayed: a fresh read should confirm the original SQL hold instead.
        await context.setOffline(false);
    }
    await page.locator('.blueprint-btn-confirm').first().click();
    await page.waitForFunction('!document.querySelector(".blueprint-modal-container")');
    await page.locator('#dynamic-form .btn-submit').first().scrollIntoViewIfNeeded();
    await page.locator('#dynamic-form .btn-submit').first().click();
    await page.locator('.btn-submit-order').first().waitFor();
    await page.locator('.btn-submit-order').first().scrollIntoViewIfNeeded();
    await page.waitForFunction(`(() => { const b=document.querySelector('.btn-submit-order'); const r=b.getBoundingClientRect(); return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('.btn-submit-order')===b && document.getAnimations().every(a=>a.playState!=='running'); })()`);
    await page.locator('.btn-submit-order').first().click();
    await page.locator('.result-title').first().waitFor();
    assert.equal(checkout?.result.code, 200, `Actual UI payload rejected: ${JSON.stringify(checkout?.result)}`);
    await page.locator('.result-title.success-color').first().waitFor();
    assert.equal(Number(checkout.payload.ticket[0].spot), fixture.seat);
    assert.ok(calls.includes('select_spot'), 'Seat selection must invoke SQL');
    assert.equal(calls.filter(name => name === 'send-ticket-order').length, 1);
    if (offlineRecovery) {
        assert.equal(calls.filter(name => name === 'select_spot').length, 1, 'Never replay an uncertain release');
        assert.equal(calls.filter(name => name === 'get_blueprint').length, 2, 'Checkout must reread the authoritative hold');
        assert.ok(checkout.payload.fields.some(field => Object.values(field).includes('regression@example.invalid')), 'Keep the entered email');
    }
    const bound = (await db.query(`SELECT x."order" AS order_id, t.state, t.ticket_symbol
        FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
        JOIN eshop.tickets t ON t.id=x.ticket WHERE s.id=$1`, [fixture.seat])).rows[0];
    assert.equal(String(bound.order_id), String(checkout.result.order.id));
    assert.equal(bound.state, 'ordered');
    assert.ok(bound.ticket_symbol);
    console.log('PASS: real map click -> SQL reservation -> preview -> order -> selected seat bound to ticket');
    if (offlineRecovery) console.log('PASS: offline seat release -> reconnect -> authoritative recovery -> one successful order, original seat and answers retained');
} catch (error) {
    console.error('SQL calls:', calls, 'checkout:', checkout?.result?.code);
    console.error('Browser state:', await page?.locator('body').innerText().catch(() => null));
    throw error;
} finally {
    try { await owner.close(); } finally {
        try { await server?.close(); } finally {
            try { await db.query('ROLLBACK'); } finally { await db.end(); }
        }
    }
}
