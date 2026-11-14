#!/usr/bin/env node
// Browser E2E: live consent transfer from the installed Joomla module to a form
// opened in a new tab. Requires the Joomla 6 fixture from verify.sh (seeded) and
// web_client dependencies (pnpm install --frozen-lockfile).
//
// Boundary: no production service is contacted. vstupenky.online is answered
// only inside this isolated browser context: /embed.js with the repository's
// generated helper and /form/* with the repository's consent-link test form
// (real Klaro + consent runtime, in-memory transport, no orders or leads). The
// Joomla page is served under an HTTPS test name. Every other request is
// aborted, except the real Cookiebot SDK hosts when --cookiebot is given; then
// the module-rendered page is answered under the Cookiebot test domain without
// contacting that website.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';

const web = new URL('../../../web_client/', import.meta.url);
const root = fileURLToPath(web);
const require = createRequire(new URL('package.json', web));
const playwright = require('playwright');
const {createServer} = await import(pathToFileURL(require.resolve('vite')).href);
const args = process.argv.slice(2);
const browsers = (args.find(arg => arg.startsWith('--browsers='))?.slice(11) || 'chromium,firefox,webkit').split(',');
const cookiebotLive = args.includes('--cookiebot');
const major = 6, container = `festapp-joomla-20261026-${major}`, joomla = `http://127.0.0.1:5991${major}`;
const seed = JSON.parse(readFileSync(new URL(`../.private/seed-${major}.json`, import.meta.url)));
const button = seed.modules.mod_vstupenky_online, embedded = seed.article_module;
const SITE = 'https://joomla-consent.test';
const CMP_SITE = 'https://cmp-test.frantisekbujnovsky.com', CMP_PATH = '/festapp-joomla-e2e/';
const CBID = '09e4e631-f8c7-434e-8387-315da47220fe';
const FORM = 'https://vstupenky.online', FORM_URL = FORM + '/form/embedded-synthetic';
// Values of the repository test form (consent_link_child.js): organization 1, Unit 2.
const scope = {consent_organization:'1', consent_unit:'2', consent_revision:'a'.repeat(32)};
const cookieconsent = {...scope, consent_link:'1', consent_provider:'cookieconsent', consent_cc_revision:'3'};
const cookiebot = {...scope, consent_link:'1', consent_provider:'cookiebot', consent_cbid:CBID, consent_origin:CMP_SITE,
    consent_valid_from:'2026-11-01T00:00:00.000Z', consent_max_age:'15552000'};
const off = {consent_link:'0', output:'embed', link_text:'', link_class:'btn btn-primary'};
const cookieBundle = readFileSync(new URL('node_modules/vanilla-cookieconsent/dist/cookieconsent.umd.js', web), 'utf8');
const helper = readFileSync(new URL('public/embed.js', web));
const userJs = '/var/www/html/media/templates/site/cassiopeia/js/user.js';
const results = [];

// Joomla's System - HTTP Headers plugin sends COOP same-origin by default, which
// severs the new tab from the website; the documented setting allows popups.
function coop(value) {
    const sql = value === null ? "UPDATE #__extensions SET params='{}' WHERE element='httpheaders' AND folder='system'"
        : "UPDATE #__extensions SET params=" + "'" + JSON.stringify({coop:value}) + "'" + " WHERE element='httpheaders' AND folder='system'";
    // Plugin parameters are cached in the com_plugins group.
    execFileSync('docker', ['exec', container, 'php', '-r', `require '/tests/bootstrap.php';$db->setQuery(${JSON.stringify(sql)})->execute();
$container->get(\\Joomla\\CMS\\Cache\\CacheControllerFactoryInterface::class)->createCacheController('callback', ['defaultgroup'=>'com_plugins'])->clean();`]);
    execFileSync('docker', ['exec', container, 'php', '/tests/clear-cache.php']);
}
function configure(changes) {
    execFileSync('docker', ['exec', container, 'php', '/tests/consent-fixture.php', JSON.stringify(changes)]);
}
// The organizer's own banner, added like any template script (Cassiopeia user.js).
function installCookieConsent() {
    const run = `;CookieConsent.run({mode:'opt-in',revision:3,hideFromBots:false,categories:{necessary:{enabled:true,readOnly:true},analytics:{},marketing:{}},
language:{default:'cs',translations:{cs:{consentModal:{title:'Cookies',description:'Měření a marketing',acceptAllBtn:'Přijmout vše',acceptNecessaryBtn:'Odmítnout'},
preferencesModal:{title:'Nastavení',acceptAllBtn:'Přijmout vše',acceptNecessaryBtn:'Odmítnout',savePreferencesBtn:'Uložit',sections:[]}}}}});`;
    execFileSync('docker', ['exec', '-i', container, 'sh', '-c', `mkdir -p "$(dirname ${userJs})" && cat > ${userJs}`], {input:cookieBundle + run});
    execFileSync('docker', ['exec', container, 'sh', '-c', `mkdir -p /var/www/html/media/templates/site/cassiopeia/css && printf '%s' '@import url("/festapp-test/cookieconsent.css");' > /var/www/html/media/templates/site/cassiopeia/css/user.css`]);
}
function removeCookieConsent() {
    execFileSync('docker', ['exec', container, 'sh', '-c', `rm -f ${userJs} /var/www/html/media/templates/site/cassiopeia/css/user.css`]);
}

const child = await createServer({root, configFile:false, logLevel:'error', server:{host:'127.0.0.1', port:0, hmr:false}});
await child.listen();
const vite = `http://127.0.0.1:${child.httpServer.address().port}`;
const formPage = '<!doctype html><html lang="en"><body><main></main><script type="module" src="/tests/fixtures/form_measurement/consent_link_child.js"></script></body></html>';

// Re-serve a proxied response; the body is already decoded, so drop transfer framing.
async function relay(route, url) {
    // Local servers reject the test names in Host/Origin; they address loopback directly.
    const headers = Object.fromEntries(Object.entries(route.request().headers()).filter(([name]) => !['origin', 'host'].includes(name)));
    const response = await route.fetch({url, headers, maxRedirects:0});
    const out = Object.fromEntries(Object.entries(response.headers())
        .filter(([name]) => !['content-encoding', 'content-length', 'transfer-encoding', 'connection'].includes(name)));
    return route.fulfill({status:response.status(), headers:out, body:await response.body()});
}

async function context(browser, {cmpPage = null} = {}) {
    const ctx = await browser.newContext({locale:'cs-CZ', colorScheme:'light', serviceWorkers:'block'});
    const blocked = [];
    await ctx.route('**/*', async route => {
        const url = new URL(route.request().url());
        try {
            if (url.origin === FORM) {
                if (url.pathname === '/embed.js') return await route.fulfill({body:helper, contentType:'text/javascript'});
                if (/^\/form\/[^/]+$/.test(url.pathname)) {
                    if (url.searchParams.has('embed')) return await route.fulfill({body:'<!doctype html><title>Embedded test form</title>', contentType:'text/html'});
                    return await route.fulfill({body:formPage, contentType:'text/html'});
                }
                return await relay(route, vite + url.pathname + url.search);
            }
            if (url.origin === SITE || (cmpPage && url.origin === CMP_SITE)) {
                if (url.pathname === '/festapp-test/cookieconsent.css') {
                    return await route.fulfill({body:readFileSync(new URL('node_modules/vanilla-cookieconsent/dist/cookieconsent.css', web)), contentType:'text/css'});
                }
                if (cmpPage && url.origin === CMP_SITE && url.pathname === CMP_PATH) return await route.fulfill({body:cmpPage, contentType:'text/html; charset=utf-8'});
                if (url.origin === CMP_SITE && !url.pathname.startsWith('/media/')) return await route.abort();
                return await relay(route, joomla + url.pathname + url.search);
            }
            if (cookiebotLive && /(^|\.)cookiebot\.(com|eu)$/.test(url.hostname)) return await route.continue();
            blocked.push(url.origin);
            return await route.abort();
        } catch (error) {
            // Requests still in flight when a tab or context closes are irrelevant.
            if (!/closed|disposed/i.test(String(error))) throw error;
        }
    });
    ctx.blocked = blocked;
    return ctx;
}
const choices = popup => popup.evaluate(() => window.linkChoices.map(c => c && {analytics:c.analytics, marketing:c.marketing}));
async function openForm(page, selector) {
    const popupReady = page.waitForEvent('popup');
    await page.locator(selector).first().click();
    const popup = await popupReady;
    const errors = [];
    popup.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    popup.on('pageerror', error => errors.push(String(error)));
    popup.on('requestfailed', request => errors.push('failed ' + request.url() + ' ' + request.failure()?.errorText));
    const pending = new Set();
    popup.on('request', request => pending.add(request.url()));
    popup.on('requestfinished', request => pending.delete(request.url()));
    await popup.waitForFunction(() => Array.isArray(window.linkChoices), null, {timeout:15000}).catch(async error => {
        throw new Error(error.message.split('\n')[0] + ' errors=' + JSON.stringify(errors).slice(0, 600) + ' pending=' + JSON.stringify([...pending]).slice(0, 600) + ' popup=' + JSON.stringify(await popup.evaluate(() => ({url:location.href, referrer:document.referrer, name:window.name})).catch(e => String(e))));
    });
    return popup;
}
async function expectTransferred(popup, choice) {
    await popup.locator('.festapp-consent-fab').waitFor({state:'visible', timeout:15000}).catch(async error => {
        const opener = popup.context().pages().find(page => page !== popup && !page.isClosed());
        const state = opener && await opener.evaluate(() => ({cookie:document.cookie, valid:typeof window.CookieConsent?.validConsent === 'function' ? window.CookieConsent.validConsent() : null,
            cookiebot:window.Cookiebot && {consent:window.Cookiebot.consent, id:window.Cookiebot.consentID, utc:window.Cookiebot.consentUTC, hasResponse:window.Cookiebot.hasResponse,
                consented:window.Cookiebot.consented, declined:window.Cookiebot.declined, regulations:window.Cookiebot.regulations, responseMode:window.Cookiebot.responseMode,
                loaders:[...document.querySelectorAll('script[src]')].map(s => s.src).filter(s => s.includes('cookiebot'))},
            config:document.querySelector('script[src$="/embed.js"]')?.getAttribute('data-festapp-consent')})).catch(e => String(e));
        throw new Error(error.message.split('\n')[0] + ' choices=' + JSON.stringify(await choices(popup)) + ' host=' + JSON.stringify(state));
    });
    await popup.waitForFunction(expected => {
        const last = window.linkChoices.at(-1);
        return last && last.analytics === expected.analytics && last.marketing === expected.marketing;
    }, choice, {timeout:15000});
    assert.equal(await popup.locator('.cookie-modal-notice').count(), 0, 'Transferred choice shows no form notice');
    assert.equal(await popup.evaluate(() => document.cookie), '', 'Imported choice is not stored in a form cookie');
    assert.equal(await popup.evaluate(() => window.opener), null, 'Form clears its opener');
}
async function expectLocalNotice(popup) {
    await popup.locator('.cookie-modal-notice').waitFor({state:'visible', timeout:15000}).catch(async error => {
        throw new Error(error.message.split('\n')[0] + ' state=' + JSON.stringify(await popup.evaluate(() => ({choices:window.linkChoices, referrer:document.referrer, name:window.name,
            opener:window.opener === null, html:document.body.innerHTML.slice(0, 400)})).catch(e => String(e))));
    });
    assert.equal((await choices(popup)).some(c => c?.analytics || c?.marketing), false, 'Nothing granted without a transfer');
}

async function cookieConsentScenarios(browser, name) {
    const ctx = await context(browser);
    const cases = [];
    try {
        const page = await ctx.newPage();
        const site = async () => {
            await page.goto(SITE + '/');
            await page.waitForFunction(() => !!window.FestappEmbed && !!window.CookieConsent?.getConfig);
        };
        await site();
        const tag = await page.locator('script[src="https://vstupenky.online/embed.js"]').evaluate(el => el.getAttribute('data-festapp-consent'));
        assert.equal(tag, '{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"' + 'a'.repeat(32) + '","revision":3}');
        assert.equal(await page.locator('a[data-festapp-consent-link]').count(), 2, 'Button and fallback link are marked');

        // No choice: the form asks itself.
        let popup = await openForm(page, `a.btn[data-festapp-consent-link]`);
        await expectLocalNotice(popup);
        await popup.close();
        cases.push('no choice -> form notice');

        // Accept in the real banner.
        await page.locator('#cc-main [data-role="all"]').first().click();
        popup = await openForm(page, `a.btn[data-festapp-consent-link]`);
        await expectTransferred(popup, {analytics:true, marketing:true});
        cases.push('accept -> transferred, no form notice');

        // Change on the website while the form is open: necessary only.
        await page.evaluate(() => window.CookieConsent.showPreferences());
        await page.locator('#cc-main .pm [data-role="necessary"]').first().click();
        await popup.waitForFunction(() => window.linkChoices.at(-1)?.analytics === false && window.linkChoices.at(-1)?.marketing === false, null, {timeout:15000});
        assert.equal(await popup.locator('.cookie-modal-notice').count(), 0);
        cases.push('change to decline while form open -> propagated');
        // Partial choice through the API of the same banner.
        await page.evaluate(() => window.CookieConsent.acceptCategory(['analytics']));
        await popup.waitForFunction(() => window.linkChoices.at(-1)?.analytics === true && window.linkChoices.at(-1)?.marketing === false, null, {timeout:15000});
        cases.push('analytics only while form open -> propagated');

        // Closing the website tab ends the transfer: the form asks itself.
        await page.close();
        await expectLocalNotice(popup).catch(async () => {
            // The notice can only reappear after revocation; check the revoked state explicitly.
            await popup.locator('.cookie-modal-notice').waitFor({state:'visible', timeout:15000});
        });
        await popup.close();
        cases.push('close website tab -> form notice');

        // Saved refusal transfers without asking; fallback link under the iframe also works.
        const again = await ctx.newPage();
        await again.goto(SITE + '/');
        await again.waitForFunction(() => !!window.FestappEmbed && !!window.CookieConsent?.getConfig);
        await again.evaluate(() => window.CookieConsent.acceptCategory([]));
        popup = await openForm(again, `[data-festapp-embed-host] a[data-festapp-consent-link]`);
        await expectTransferred(popup, {analytics:false, marketing:false});
        await popup.close();
        cases.push('decline -> declined transfers (embedded fallback link)');

        // Reloading the website ends linked visits; a fresh click is required.
        popup = await openForm(again, `a.btn[data-festapp-consent-link]`);
        await expectTransferred(popup, {analytics:false, marketing:false});
        await again.reload();
        await popup.locator('.cookie-modal-notice').waitFor({state:'visible', timeout:15000});
        await popup.close();
        cases.push('website reload -> open form falls back to its notice');
        assert.ok(!ctx.blocked.some(origin => /vstupenky\.online/.test(origin)), 'No production service request');
    } finally {
        await ctx.close();
    }
    results.push({browser:name, cmp:'cookieconsent-3.3.0', site:SITE, cases, blocked_origins:[...new Set(ctx.blocked)]});
}

async function defaultCoopScenario(browser, name) {
    const ctx = await context(browser);
    try {
        const page = await ctx.newPage();
        const response = await page.goto(SITE + '/');
        assert.equal(response.headers()['cross-origin-opener-policy'], 'same-origin');
        await page.waitForFunction(() => !!window.FestappEmbed && !!window.CookieConsent?.getConfig);
        await page.locator('#cc-main [data-role="all"]').first().click();
        const popupReady = page.waitForEvent('popup');
        await page.locator('a.btn[data-festapp-consent-link]').click();
        const popup = await popupReady;
        await popup.waitForLoadState('domcontentloaded');
        const state = await popup.evaluate(() => ({referrer:document.referrer, opener:window.opener === null}));
        // Browsers differ: a severed tab may lose its referrer and name, or keep
        // them without a usable opener. Either way only two outcomes are safe:
        // the form's own notice, or a genuine transfer of the saved choice.
        let outcome = 'new tab severed (no referrer), form cannot request the choice';
        if (state.referrer) {
            await popup.waitForFunction(() => Array.isArray(window.linkChoices), null, {timeout:15000});
            await popup.waitForFunction(() => document.querySelector('.cookie-modal-notice') ||
                (window.linkChoices.at(-1)?.analytics === true && window.linkChoices.at(-1)?.marketing === true), null, {timeout:15000});
            outcome = await popup.locator('.cookie-modal-notice').count() ? 'form notice (opener severed)' : 'transferred (browser kept the opener)';
            if (outcome.startsWith('form')) await expectLocalNotice(popup);
            else await expectTransferred(popup, {analytics:true, marketing:true});
        } else {
            assert.equal(state.opener, true, 'Severed new tab has no opener');
        }
        await popup.close();
        results.push({browser:name, cmp:'cookieconsent-3.3.0', cases:['Joomla default COOP same-origin after accept: ' + outcome]});
    } finally {
        await ctx.close();
    }
}

async function legacyScenario(browser, name) {
    const ctx = await context(browser);
    try {
        const page = await ctx.newPage();
        await page.goto(SITE + '/');
        await page.waitForFunction(() => !!window.FestappEmbed && !!window.CookieConsent?.getConfig);
        assert.equal(await page.locator('[data-festapp-consent-link]').count(), 0);
        assert.equal(await page.locator('script[data-festapp-consent]').count(), 0);
        await page.locator('#cc-main [data-role="all"]').first().click();
        const popupReady = page.waitForEvent('popup');
        await page.locator('[data-festapp-embed-host] a').first().click();
        const popup = await popupReady;
        await popup.waitForLoadState('domcontentloaded');
        // Legacy noopener/noreferrer link: no opener, no referrer, no helper window name.
        assert.deepEqual(await popup.evaluate(() => ({opener:window.opener, referrer:document.referrer, name:window.name})), {opener:null, referrer:'', name:''});
        await popup.close();
    } finally {
        await ctx.close();
    }
    results.push({browser:name, cmp:'cookieconsent-3.3.0', cases:['transfer off (default): unmarked noopener/noreferrer link, form opens without opener or referrer, nothing transferred']});
}

// Cookiebot writes method, timestamp and its cookie in separate steps; a visitor
// clicks later than this script, so wait for the complete saved record.
const settledCookiebot = page => page.waitForFunction(() => {
    const cmp = window.Cookiebot;
    return cmp?.consent?.method === 'explicit' && cmp.consentUTC instanceof Date && document.cookie.includes('CookieConsent=') &&
        decodeURIComponent(document.cookie).includes(`stamp:'${cmp.consentID}'`);
}, null, {timeout:30000});

async function cookiebotScenarios(browser, name, blocking) {
    // Exact HTML rendered by the installed module, with the website's Cookiebot loader.
    const rendered = execFileSync('curl', ['-s', joomla + '/']).toString();
    const loader = `<script id="Cookiebot" src="https://consent.cookiebot.com/uc.js" data-cbid="${CBID}"${blocking === 'auto' ? ' data-blockingmode="auto"' : ''} type="text/javascript"></script>`;
    const cmpPage = rendered.replace(/<head>/i, '<head>' + loader);
    assert.ok(cmpPage.includes(loader) && /data-festapp-consent="\{&quot;provider&quot;:&quot;cookiebot&quot;/.test(cmpPage));
    const ctx = await context(browser, {cmpPage});
    const cases = [];
    try {
        const page = await ctx.newPage();
        const load = async () => {
            await page.goto(CMP_SITE + CMP_PATH);
            await page.waitForFunction(() => !!window.FestappEmbed && !!window.Cookiebot, null, {timeout:30000});
        };
        await load();
        const dialog = page.locator('#CybotCookiebotDialog');
        await dialog.waitFor({state:'visible', timeout:30000});
        let popup = await openForm(page, 'a.btn[data-festapp-consent-link]');
        await expectLocalNotice(popup);
        await popup.close();
        cases.push('no choice -> form notice');

        await page.locator('#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll').click();
        await settledCookiebot(page);
        popup = await openForm(page, 'a.btn[data-festapp-consent-link]');
        await expectTransferred(popup, {analytics:true, marketing:true});
        cases.push('allow all -> transferred, no form notice');

        await page.evaluate(() => window.Cookiebot.renew());
        await page.locator('#CybotCookiebotDialogBodyButtonDecline').click({timeout:30000});
        await popup.waitForFunction(() => window.linkChoices.at(-1)?.analytics === false && window.linkChoices.at(-1)?.marketing === false, null, {timeout:15000});
        assert.equal(await popup.locator('.cookie-modal-notice').count(), 0);
        cases.push('deny while form open -> propagated');

        await page.close();
        await popup.locator('.cookie-modal-notice').waitFor({state:'visible', timeout:15000});
        await popup.close();
        cases.push('close website tab -> form notice');

        const again = await ctx.newPage();
        await again.goto(CMP_SITE + CMP_PATH);
        await again.waitForFunction(() => !!window.FestappEmbed, null, {timeout:30000});
        await settledCookiebot(again);
        popup = await openForm(again, '[data-festapp-embed-host] a[data-festapp-consent-link]');
        await expectTransferred(popup, {analytics:false, marketing:false});
        await popup.close();
        cases.push('saved deny -> declined transfers (embedded fallback link)');
        assert.ok(!ctx.blocked.some(origin => origin === CMP_SITE || /vstupenky\.online/.test(origin)));
    } finally {
        await ctx.close();
    }
    results.push({browser:name, cmp:'Cookiebot live SDK', blocking, site:CMP_SITE + CMP_PATH, cases, blocked_origins:[...new Set(ctx.blocked)]});
}

try {
    installCookieConsent();
    configure({[button]:{...off}, [embedded]:{...off}});
    for (const name of browsers) {
        const browser = await playwright[name].launch();
        try { await legacyScenario(browser, name); } finally { await browser.close(); }
    }
    configure({[button]:{...off, ...cookieconsent, output:'link', link_text:'Koupit vstupenky'}, [embedded]:{...off, ...cookieconsent}});
    for (const name of browsers) {
        const browser = await playwright[name].launch();
        try { await defaultCoopScenario(browser, name); } finally { await browser.close(); }
    }
    coop('same-origin-allow-popups');
    for (const name of browsers) {
        const browser = await playwright[name].launch();
        try { await cookieConsentScenarios(browser, name); } finally { await browser.close(); }
    }
    if (cookiebotLive) {
        removeCookieConsent();
        configure({[button]:{...off, ...cookiebot, output:'link', link_text:'Koupit vstupenky'}, [embedded]:{...off, ...cookiebot}});
        for (const name of browsers) {
            for (const blocking of ['auto', 'manual']) {
                const browser = await playwright[name].launch();
                try { await cookiebotScenarios(browser, name, blocking); }
                catch (error) { results.push({browser:name, cmp:'Cookiebot live SDK', blocking, failed:String(error).split('\n')[0]}); }
                finally { await browser.close(); }
            }
        }
    }
} finally {
    coop(null);
    removeCookieConsent();
    configure({[button]:{...off}, [embedded]:{...off}});
    await child.close();
}
writeFileSync(new URL('../.private/consent-browser.json', import.meta.url), JSON.stringify(results, null, 2) + '\n');
console.log(JSON.stringify(results.map(r => ({browser:r.browser, cmp:r.cmp, blocking:r.blocking, cases:r.cases?.length, failed:r.failed})), null, 1));
if (results.some(r => r.failed)) process.exitCode = 1;
