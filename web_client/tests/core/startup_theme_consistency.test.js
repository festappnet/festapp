import assert from 'node:assert/strict';
import { readFile, mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import startupTheme from '../../../automation/lib/startup_theme.cjs';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const source = (await readFile(new URL('../../src/services/theme_preference.js', import.meta.url), 'utf8')).trim();
for (const shell of ['web', 'web_client']) {
    const html = await readFile(new URL(`../../../${shell}/index.html`, import.meta.url), 'utf8');
    for (const mode of ['dark', 'light', 'auto', 'legacy-dark', 'legacy-light', 'blocked']) {
        for (const osDark of [false, true]) {
            test(`${shell} pre-module theme mode=${mode} osDark=${osDark}`, t => {
                const dom = new JSDOM(html, {url: 'https://fixture.invalid/', runScripts: 'outside-only'});
                t.after(() => dom.window.close());
                const {window} = dom;
                const {document} = window;
                window.matchMedia = () => ({matches: osDark, addEventListener(){}});
                if (mode === 'blocked') Object.defineProperty(window, 'localStorage', {get(){throw new Error('denied');}});
                else if (mode.startsWith('legacy-')) window.localStorage.setItem('flutter.adaptive_theme_preferences', JSON.stringify(JSON.stringify({theme_mode: mode === 'legacy-dark' ? 1 : 0})));
                else window.localStorage.setItem('theme', mode);
                const inline = document.getElementById('festapp-startup-theme');
                assert.ok(inline, 'pre-paint policy must be inline, before application modules');
                assert.equal(inline.textContent.trim(), source, 'both shells embed the canonical runtime policy');
                window.eval(inline.textContent);
                window.applyFestappStartupTheme();
                const dark = ['dark', 'legacy-dark'].includes(mode) || (['auto', 'blocked'].includes(mode) && osDark);
                assert.equal(document.documentElement.dataset.startupTheme, dark ? 'dark' : 'light');
                assert.equal(document.documentElement.style.colorScheme, dark ? 'dark' : 'light');
                assert.equal(document.body.classList.contains('dark-mode'), dark);
                const logo = document.querySelector('.initial-logo, .startup-brand');
                assert.match(logo.getAttribute('src'), dark ? /loading-animation\.svg$/ : /loading-animation-light\.svg$/);
                const background = window.getComputedStyle(document.documentElement).backgroundColor;
                if (shell === 'web_client') assert.match(document.getElementById('web-client-startup').style.background, /--festapp-startup-background/);
                assert.equal(background, dark ? shell === 'web' ? 'rgb(25, 36, 59)' : 'rgb(35, 37, 41)' : shell === 'web' ? 'rgb(255, 255, 255)' : 'rgb(235, 241, 246)');
                const initial = document.documentElement.dataset.startupTheme;
                window.__FESTAPP_APP_READY__ = true;
                if (mode !== 'blocked') window.localStorage.setItem('theme', dark ? 'light' : 'dark');
                window.applyFestappStartupTheme();
                assert.equal(document.documentElement.dataset.startupTheme, initial, 'retired startup listener cannot override the running application');
                window.FestappThemePreference.paintTheme(!dark);
                assert.equal(document.documentElement.dataset.startupTheme, dark ? 'light' : 'dark', 'running ThemeService can still update the browser surface');
                assert.equal(document.body.style.colorScheme, dark ? 'light' : 'dark');
            });
        }
    }
}

// Configuration embeds exactly one copy before first-paint metadata consumers.
test('startup policy generation is deterministic and idempotent for both shells', async t => {
    const root = await mkdtemp(join(tmpdir(), 'festapp-startup-policy-'));
    t.after(() => rm(root, {recursive:true, force:true}));
    await mkdir(join(root, 'web_client/src/services'), {recursive:true});
    await mkdir(join(root, 'web'), {recursive:true});
    await writeFile(join(root, 'web_client/src/services/theme_preference.js'), source);
    for (const shell of ['web', 'web_client']) {
        await writeFile(join(root,shell,'index.html'), await readFile(new URL(`../../../${shell}/index.html`,import.meta.url),'utf8'));
    }
    startupTheme.configureStartupThemes(root);
    const first=await Promise.all(['web','web_client'].map(shell=>readFile(join(root,shell,'index.html'),'utf8')));
    startupTheme.configureStartupThemes(root);
    const next=await Promise.all(['web','web_client'].map(shell=>readFile(join(root,shell,'index.html'),'utf8')));
    assert.deepEqual(next,first);
    for(const html of next) {
        assert.equal(html.split('id="festapp-startup-theme"').length,2);
        assert.ok(html.indexOf('name="color-scheme"')<html.indexOf('id="festapp-startup-theme"'));
    }
});


for (const shell of ['web', 'web_client']) {
    test(`${shell} startup hides branding only for explicit embed=1`, async () => {
        const html = await readFile(new URL(`../../../${shell}/index.html`, import.meta.url), 'utf8');
        for (const query of ['?embed=1', '?embed=true', '']) {
            const dom = new JSDOM(html, {url:`https://tickets.invalid/form/a${query}`, runScripts:'outside-only'});
            const {window} = dom;
            window.matchMedia = () => ({matches:false, addEventListener(){}});
            window.eval(window.document.getElementById('festapp-embed-startup').textContent);
            window.eval(window.document.getElementById('festapp-startup-theme').textContent);
            window.applyFestappStartupTheme();
            const embedded = query === '?embed=1';
            assert.equal(window.document.documentElement.hasAttribute('data-embed-startup'), embedded);
            const brand = window.document.querySelector(shell === 'web' ? '.initial-logo' : '.startup-spinner');
            assert.equal(window.getComputedStyle(brand).display === 'none', embedded);
            if (embedded) {
                const loader = shell === 'web' ? 'loader-content' : 'web-client-startup';
                const rule = [...window.document.styleSheets].flatMap(sheet => [...sheet.cssRules])
                    .find(rule => rule.selectorText?.endsWith(`html[data-embed-startup] #${loader}`));
                assert.equal(rule.style.getPropertyValue('background'), 'transparent');
                assert.equal(rule.style.getPropertyPriority('background'), 'important');
            }
            window.close();
        }
    });
}


for (const shell of ['web', 'web_client']) {
    test(`${shell} hides the server-injected SEO summary only in explicit embed context`, async t => {
        const html = await readFile(new URL(`../../../${shell}/index.html`, import.meta.url), 'utf8');
        for (const query of ['?embed=1', '?embed=true', '']) {
            const dom = new JSDOM(html, {url:`https://tickets.invalid/form/a${query}`, runScripts:'outside-only'});
            t.after(() => dom.window.close());
            const {window} = dom;
            // Production HTML receives this public fallback before the app starts.
            window.document.body.insertAdjacentHTML('afterbegin',
                '<section id="public-seo-summary"><h1>KUŘÍN 2027 – Přihláška</h1><p>Letní tábor</p><p>3.–17. července 2027</p></section>');
            window.eval(window.document.getElementById('festapp-embed-startup').textContent);
            const summary = window.document.getElementById('public-seo-summary');
            assert.equal(window.getComputedStyle(summary).display === 'none', query === '?embed=1');
            assert.equal(summary.querySelector('h1').textContent, 'KUŘÍN 2027 – Přihláška');
        }
    });
}
