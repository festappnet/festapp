import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

const dom = new JSDOM('<div id="app"></div><div id="form-page-container"></div>', {
    url: 'https://vstupenky.online/form/test?fbclid=facebook',
});
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.CustomEvent = dom.window.CustomEvent;
window.scrollTo = () => {};
const { FormPage } = await import('../../src/components/forms/form_page.js');
const { DbForms } = await import('../../src/components/forms/db_forms.js');
const { SupabaseService } = await import('../../src/services/supabase_service.js');
const { RouterService } = await import('../../src/services/router_service.js');
const { AppConfig } = await import('../../src/app_config.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
LocalizationService.translations = { Common: { loading: 'Načítání...', retry: 'Zkusit znovu' }, FeatureFormSettings: { loadFailed: 'Formulář se nepodařilo načíst.', formNotFound: 'Formulář nenalezen.' } };
AppConfig.isAppSupported = false;

test('form loading never leaves an empty page while the request is pending', async (t) => {
    t.after(() => dom.window.close());
    await t.test('initial routing waits for visible form content', async (t) => {
        let finish;
        let started;
        const requestStarted = new Promise(resolve => { started = resolve; });
        t.mock.method(DbForms, 'getFormByLink', () => new Promise(resolve => {
            finish = resolve;
            started();
        }));
        let handled = false;
        const loading = RouterService.handleInitialLoad().then(() => { handled = true; });
        await requestStarted;
        assert.equal(handled, false, 'startup must not report ready before rendering the form');
        assert.match(document.getElementById('form-page-container').textContent, /Načítání/);
        finish(null);
        await loading;
        assert.match(document.getElementById('form-page-container').textContent, /nenalezen/);
    });
    await t.test('a failed request offers a retry that fetches again', async (t) => {
        let calls = 0;
        t.mock.method(DbForms, 'getFormByLink', async () => {
            if (++calls === 1) throw new Error('<script>private transport detail</script>');
            return null;
        });
        const page = new FormPage('form-page-container');
        await page.init('test');
        const retry = page.host.querySelector('button');
        assert.ok(retry, 'network errors must offer recovery');
        assert.match(page.host.textContent, /nepodařilo/);
        assert.doesNotMatch(page.host.textContent, /private transport detail/);
        retry.click();
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(calls, 2, 'same-link initialization must allow a failed load to retry');
        assert.match(page.host.textContent, /nenalezen/);
    });
    await t.test('a permanently stalled RPC is bounded and aborted', async (t) => {
        let signal;
        t.mock.method(SupabaseService, 'getClient', () => ({
            rpc: () => ({ abortSignal(value) { signal = value; return new Promise(() => {}); } }),
        }));
        t.mock.timers.enable({ apis: ['setTimeout'] });
        const loading = DbForms.getFormByLink('test');
        const rejected = assert.rejects(loading, /timed out/);
        t.mock.timers.tick(20000);
        await rejected;
        assert.equal(signal.aborted, true);
    });
    await t.test('transport failures remain distinct from a nonexistent form', async (t) => {
        t.mock.method(SupabaseService, 'getClient', () => ({
            rpc: () => ({ abortSignal: async () => ({ data: null, error: { message: 'Failed to fetch' } }) }),
        }));
        await assert.rejects(DbForms.getFormByLink('test'), /Failed to fetch/);
    });
});
