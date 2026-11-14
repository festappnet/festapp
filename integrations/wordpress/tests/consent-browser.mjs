#!/usr/bin/env node
// Browser E2E for the cookie choice transfer from a WordPress website to a form
// opened in a new tab, with real Complianz, CookieConsent v3 and (optionally)
// the live Cookiebot SDK. The form side is the repository's linked-consent
// fixture (real Klaro notice and link protocol) served from the local web
// client; no storefront, order, lead or measurement request is made. Every
// request outside the local fixture origins is aborted, except Cookiebot's
// own SDK hosts in the opt-in live Cookiebot scenario.
//
// Environment:
//   VO_WP_URL         WordPress URL (default http://localhost:59811)
//   VO_WP_CLI         command prefix running WP-CLI in that WordPress
//                     (default "node scripts/environment.mjs run cli wp")
//   VO_FORM_ORIGIN    deployment-owned local form origin (default http://127.0.0.1:59801)
//   VO_BROWSERS       comma-separated: chromium,firefox,webkit
//   VO_PROVIDERS      comma-separated: complianz,cookieconsent,cookiebot
//   VO_WP_ADMIN_PASSWORD  enables the settings page scenario (admin user "admin")
//   VO_COOKIEBOT_HOST HTTPS origin of a website whose CBID domain group is
//                     configured; enables the live Cookiebot scenario. Its test
//                     path is answered locally by route interception, so
//                     nothing on that host changes.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const here = import.meta.dirname;
const webClient = path.resolve(here, '../../../web_client');
const require = createRequire(path.join(webClient, 'package.json'));
const playwright = require('playwright');
const {createServer} = await import(pathToFileURL(require.resolve('vite')).href);

const wpUrl = process.env.VO_WP_URL || 'http://localhost:59811';
const wpCli = (process.env.VO_WP_CLI || 'node scripts/environment.mjs run cli wp').split(' ');
const formOrigin = process.env.VO_FORM_ORIGIN || 'http://127.0.0.1:59801';
const browsers = (process.env.VO_BROWSERS || 'chromium,firefox,webkit').split(',');
const providers = (process.env.VO_PROVIDERS ?? 'complianz,cookieconsent').split(',').filter(Boolean);
const cookiebotHost = process.env.VO_COOKIEBOT_HOST || '';
const liveForm = 'https://vstupenky.online';
const cookiebotPath = '/wp-consent-transfer-test/';
const cookiebotOrigins = new Set(['https://consent.cookiebot.com', 'https://consentcdn.cookiebot.com', 'https://imgsct.cookiebot.com']);
const results = [];

function wp(...args) {
    const r = spawnSync(wpCli[0], [...wpCli.slice(1), ...args], {cwd: path.resolve(here, '..'), encoding: 'utf8'});
    if (r.status) throw Error(`WP-CLI ${args.join(' ')} failed: ${r.stderr}${r.stdout}`);
    return r.stdout;
}
const wpValue = (...args) => wp(...args).trim().split('\n').at(-1).trim();
const setup = (...args) => wp('eval-file', '/var/www/html/wp-content/plugins/vstupenky-online-tests/consent-browser-setup.php', ...args);

// Form fixture: /form/<slug> runs the real linked-consent child; embeds get an empty page.
const port = Number(new URL(formOrigin).port);
const server = await createServer({root: webClient, configFile: false, logLevel: 'error', server: {host: '127.0.0.1', port, strictPort: true, hmr: false},
    plugins: [{name: 'consent-form-fixture', configureServer(s) { s.middlewares.use((req, res, next) => {
        if (!req.url.startsWith('/form/')) return next();
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.end(req.url.includes('embed=1') ? '<!doctype html><title>Embed</title>'
            : '<!doctype html><html lang="en"><body><main></main><script type="module" src="/tests/fixtures/form_measurement/consent_link_child.js"></script></body></html>');
    }); }}]});
await server.listen();

async function context(browser, extraOrigins = new Set()) {
    const ctx = await browser.newContext();
    const blocked = new Set();
    const allowed = new Set([new URL(wpUrl).origin, formOrigin, ...extraOrigins]);
    await ctx.route('**/*', route => {
        const url = new URL(route.request().url());
        if (allowed.has(url.origin)) return route.continue();
        blocked.add(url.origin);
        return route.abort();
    });
    ctx.blocked = blocked;
    return ctx;
}
const lastChoice = popup => popup.evaluate(() => window.linkChoices?.at(-1) ?? null);
const waitChoice = (popup, analytics, marketing) => popup.waitForFunction(([a, m]) =>
    window.linkChoices?.at(-1)?.analytics === a && window.linkChoices?.at(-1)?.marketing === m, [analytics, marketing], {timeout: 10000});
const noticeVisible = popup => popup.locator('.cookie-modal-notice').waitFor({state: 'visible', timeout: 10000});

async function openLink(page, selector) {
    const popupReady = page.waitForEvent('popup');
    await page.locator(selector).click();
    const popup = await popupReady;
    if (process.env.VO_DEBUG) popup.on('console', m => console.log('popup:', m.text().slice(0, 300)));
    await popup.waitForFunction(() => Array.isArray(window.linkChoices), null, {timeout: 15000});
    return popup;
}

// Website CMP drivers: accept, decline, change to decline while open.
const drivers = {
    complianz: {
        ready: page => page.locator('.cmplz-cookiebanner .cmplz-accept').waitFor({state: 'visible'}),
        accept: page => page.locator('.cmplz-cookiebanner .cmplz-accept').click(),
        decline: page => page.locator('.cmplz-cookiebanner .cmplz-deny').click(),
        async change(page) {
            await page.locator('#cmplz-manage-consent .cmplz-manage-consent').click();
            await page.locator('.cmplz-cookiebanner .cmplz-deny').click();
        },
    },
    cookieconsent: {
        ready: page => page.locator('#cc-main [data-role="all"]').waitFor({state: 'visible'}),
        accept: page => page.locator('#cc-main .cm [data-role="all"]').click(),
        decline: page => page.locator('#cc-main .cm [data-role="necessary"]').click(),
        async change(page) {
            await page.evaluate(() => window.CookieConsent.showPreferences());
            await page.locator('#cc-main .pm [data-role="necessary"]').click();
        },
    },
    cookiebot: {
        ready: page => page.locator('#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, #CybotCookiebotDialogBodyButtonAccept').first().waitFor({state: 'visible', timeout: 20000}),
        accept: page => page.locator('#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, #CybotCookiebotDialogBodyButtonAccept').first().click(),
        decline: page => page.locator('#CybotCookiebotDialogBodyButtonDecline').click(),
        async change(page) {
            await page.evaluate(() => window.Cookiebot.renew());
            await page.locator('#CybotCookiebotDialogBodyButtonDecline').waitFor({state: 'visible', timeout: 20000});
            await page.locator('#CybotCookiebotDialogBodyButtonDecline').click();
        },
    },
};

async function scenario(browserName, provider, name, run) {
    const started = Date.now();
    try { await run(); results.push({browser: browserName, provider, scenario: name, ok: true, ms: Date.now() - started}); }
    catch (error) { results.push({browser: browserName, provider, scenario: name, ok: false, error: String(error.message || error).split('\n')[0]}); }
}

async function checkMarkup(page, linkOrigin) {
    const markup = await page.evaluate(origin => {
        const script = [...document.querySelectorAll('script[src]')].find(s => s.src === origin + '/embed.js');
        const links = [...document.querySelectorAll(`a[href^="${origin}/form/"]`)].map(a => ({text: a.textContent.trim(), marked: a.hasAttribute('data-festapp-consent-link'), rel: a.rel, target: a.target}));
        return {config: script?.getAttribute('data-festapp-consent'), cookieconsent: script?.getAttribute('data-cookieconsent'), category: script?.getAttribute('data-category'), type: script?.type, links};
    }, linkOrigin);
    assert.ok(markup.config, 'helper script carries data-festapp-consent');
    assert.ok(!markup.type || markup.type === 'text/javascript', 'helper is not blocked by the website CMP: ' + markup.type);
    for (const link of markup.links) {
        if (link.target === '_blank') assert.ok(link.marked && !/noopener|noreferrer/.test(link.rel), 'new-tab link marked: ' + link.text);
        else assert.ok(!link.marked, 'same-tab link unchanged');
    }
    assert.equal(markup.links.filter(l => l.marked).length, 3, 'content link, form link block and embed fallback are marked');
    return markup;
}

async function runProvider(browserName, browser, provider) {
    const live = provider === 'cookiebot';
    const pageUrl = live ? cookiebotHost + cookiebotPath : wpUrl + '/consent-transfer/';
    const linkOrigin = live ? liveForm : formOrigin;
    const driver = drivers[provider];
    const newSite = async () => {
        const ctx = await context(browser, live ? new Set([...cookiebotOrigins, cookiebotHost, liveForm]) : undefined);
        if (live) {
            // Answer only the test path on the real website origin with the
            // WordPress page; the form origin is served by the local fixture.
            await ctx.route(url => new URL(url).origin === cookiebotHost, async route => {
                const url = new URL(route.request().url());
                if (url.pathname !== cookiebotPath) return route.abort();
                const html = await (await fetch(wpUrl + '/consent-transfer/')).text();
                return route.fulfill({status: 200, contentType: 'text/html; charset=utf-8', body: html.replaceAll(formOrigin, liveForm)});
            });
            await ctx.route(url => new URL(url).origin === liveForm, async route => {
                const url = new URL(route.request().url());
                const response = await fetch(formOrigin + url.pathname + url.search);
                return route.fulfill({status: response.status, contentType: response.headers.get('content-type') || 'text/plain', body: Buffer.from(await response.arrayBuffer())});
            });
        }
        const page = await ctx.newPage();
        await page.goto(pageUrl);
        await page.waitForFunction(() => !!window.FestappEmbed, null, {timeout: 15000});
        return {ctx, page};
    };
    await scenario(browserName, provider, 'markup', async () => {
        const {ctx, page} = await newSite();
        try { await checkMarkup(page, linkOrigin); } finally { await ctx.close(); }
    });
    await scenario(browserName, provider, 'accept, open, change on website, close website', async () => {
        const {ctx, page} = await newSite();
        try {
            await driver.ready(page); await driver.accept(page);
            const popup = await openLink(page, '#content-link a');
            await waitChoice(popup, true, true);
            await popup.locator('.festapp-consent-fab').waitFor({state: 'visible'});
            assert.equal(await popup.locator('.cookie-modal-notice').count(), 0, 'no form notice after transfer');
            assert.equal(await popup.evaluate(() => window.opener), null, 'form clears its opener');
            await driver.change(page);
            await waitChoice(popup, false, false);
            await page.close();
            await noticeVisible(popup);
        } finally { await ctx.close(); }
    });
    await scenario(browserName, provider, 'decline transfers', async () => {
        const {ctx, page} = await newSite();
        try {
            await driver.ready(page); await driver.decline(page);
            const popup = await openLink(page, `.vstupenky-online-form-link a`);
            await waitChoice(popup, false, false);
            assert.equal(await popup.locator('.cookie-modal-notice').count(), 0, 'saved refusal transfers without a notice');
        } finally { await ctx.close(); }
    });
    await scenario(browserName, provider, 'no choice keeps the form notice', async () => {
        const {ctx, page} = await newSite();
        try {
            await driver.ready(page);
            const popup = await openLink(page, '.vstupenky-online a[data-festapp-consent-link]');
            await noticeVisible(popup);
            assert.ok(!(await lastChoice(popup))?.analytics, 'nothing granted without a saved choice');
        } finally { await ctx.close(); }
    });
}

// Real settings page: suggestion, explicit save, mismatch notice and confirmation.
async function adminScenario() {
    const password = process.env.VO_WP_ADMIN_PASSWORD;
    if (!password) { results.push({provider: 'complianz', scenario: 'settings page', skipped: 'VO_WP_ADMIN_PASSWORD not set'}); return; }
    wp('option', 'update', 'complianz_active_policy_id', '1');
    setup('complianz', formOrigin);
    wp('option', 'delete', 'vstupenky_online_consent_transfer');
    const browser = await playwright.chromium.launch();
    const ctx = await context(browser);
    const page = await ctx.newPage();
    await scenario('chromium', 'complianz', 'settings page', async () => {
        await page.goto(wpUrl + '/wp-login.php');
        await page.fill('#user_login', 'admin'); await page.fill('#user_pass', password);
        await page.click('#wp-submit'); await page.waitForURL(/wp-admin/);
        await page.goto(wpUrl + '/wp-admin/options-general.php?page=vstupenky-online');
        const policy = page.locator('#vstupenky-online-consent-policy-id');
        assert.equal(await policy.inputValue(), '1', 'detected policy ID prefilled');
        assert.equal(await page.locator('#vstupenky-online-consent-provider').inputValue(), 'complianz', 'detected banner preselected');
        assert.equal(wpValue('eval', 'echo (int) $GLOBALS["wpdb"]->get_var("SELECT COUNT(*) FROM {$GLOBALS["wpdb"]->options} WHERE option_name=\'vstupenky_online_consent_transfer\'");'), '0', 'nothing saved before an explicit save');
        await page.check('input[name="vstupenky_online_consent_transfer[enabled]"]');
        await page.click('#submit');
        await page.locator('.notice-error, .error').first().waitFor({state: 'visible'});
        assert.ok(!(await page.locator('input[name="vstupenky_online_consent_transfer[enabled]"]').isChecked()), 'incomplete settings stay disabled');
        await page.fill('#vstupenky-online-consent-organization', '1');
        await page.fill('#vstupenky-online-consent-unit', '2');
        await page.fill('#vstupenky-online-consent-consent-revision', 'a'.repeat(32));
        await page.check('input[name="vstupenky_online_consent_transfer[enabled]"]');
        await page.click('#submit');
        await page.getByText('Status: enabled on this website.').waitFor();
        const before = '1';
        wp('option', 'update', 'complianz_active_policy_id', String(Number(before) + 1));
        await page.goto(wpUrl + '/wp-admin/index.php');
        await page.getByRole('link', {name: 'Review the setting'}).click();
        assert.equal(await policy.inputValue(), before, 'saved value is never overwritten');
        await page.getByRole('button', {name: 'Confirm and save the new value'}).click();
        await page.getByText('Status: enabled on this website.').waitFor();
        assert.equal(await policy.inputValue(), String(Number(before) + 1), 'explicit confirmation saved the new policy ID');
        await page.goto(wpUrl + '/wp-admin/index.php');
        assert.equal(await page.getByRole('link', {name: 'Review the setting'}).count(), 0, 'notice cleared after confirmation');
        wp('option', 'update', 'complianz_active_policy_id', before);
    });
    await browser.close();
}

try {
    await adminScenario();
    for (const provider of providers) {
        if (provider === 'cookiebot' && !cookiebotHost) { results.push({provider, scenario: 'all', skipped: 'VO_COOKIEBOT_HOST not set'}); continue; }
        const validFrom = new Date(Date.now() - 60000).toISOString();
        console.log(setup(provider, formOrigin, cookiebotHost, validFrom, process.env.VO_COOKIEBOT_BLOCKING || 'auto').trim());
        for (const browserName of browsers) {
            const browser = await playwright[browserName].launch();
            try { await runProvider(browserName, browser, provider); } finally { await browser.close(); }
        }
    }
} finally {
    setup('off', formOrigin);
    await server.close();
}
for (const r of results) console.log(JSON.stringify(r));
const failed = results.filter(r => r.ok === false);
console.log(`${results.filter(r => r.ok).length} passed, ${failed.length} failed, ${results.filter(r => r.skipped).length} skipped`);
process.exit(failed.length ? 1 : 0);
