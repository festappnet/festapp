import { register } from 'node:module';
register('../css_loader.mjs', import.meta.url);
import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<body><div id="app"></div><div id="host"></div></body>', { url: 'https://tickets.invalid/form/old?x=%2f#personal' });
for (const name of ['window','document','HTMLElement','customElements','CustomEvent','Event','DOMParser','localStorage']) globalThis[name] = name === 'window' ? dom.window : dom.window[name];
const { FormPage } = await import('../../src/components/forms/form_page.js');
const { DbForms } = await import('../../src/components/forms/db_forms.js');
const { FormModel } = await import('../../src/components/forms/form_models.js');
const { RightsService } = await import('../../src/services/rights_service.js');
const { SeoService } = await import('../../src/services/seo_service.js');
const { RouterService } = await import('../../src/services/router_service.js');
const host = () => {
    document.body.innerHTML = '<div id="app"></div><div id="host"></div>';
    const page = new FormPage('host');
    page.applyTheme = () => {};
    page.renderForm = () => { page.host.textContent = 'Loaded'; };
    page.renderError = message => { throw new Error(message); };
    page.renderWaitlistManagement = () => { page.host.textContent = 'Terminal offer'; };
    page.attachOverview = () => {};
    return page;
};
RightsService.updateAppData = async () => {};
RightsService.canSeeReservations = () => false;
SeoService.updateMetaTags = () => {};
test('an alias resolves once and does not recreate the form session on canonical init', async () => {
    window.history.replaceState(null,'','/form/old?x=%2f#personal');
    let loads = 0;
    DbForms.getFormByLink = async link => { assert.equal(link,'old'); loads++; return new FormModel({ id: 1, link: 'current', fields: [] }); };
    const page = host();
    await page.init('old');
    await page.init('current');
    assert.equal(loads,1);
    assert.equal(window.location.pathname + window.location.search + window.location.hash, '/form/current?x=%2f#personal');
});
test('a terminal offer uses its authorized canonical link without public form loading', async () => {
    window.history.replaceState(null,'','/form/old#waitlist?token=' + 'a'.repeat(64) + '&offer_id=00000000-0000-4000-8000-000000000001');
    DbForms.getFormByLink = async () => { throw new Error('public loader must not run'); };
    const page = host();
    page.waitlistCommands = { read: async () => ({ code:200, form:null, formLink:'current', pendingCount:0 }) };
    await page.init('old');
    assert.equal(window.location.pathname,'/form/current');
    assert.equal(window.location.hash.includes('token=' + 'a'.repeat(64)),true);
    assert.equal(page.currentLink,'current');
});

test('an order capability canonicalizes from its own bundle without public form access', async () => {
    window.history.replaceState(null,'','/form/old?x=1#order?token=' + 'b'.repeat(64) + '&order_id=17');
    DbForms.getFormByLink = async () => { throw new Error('public loader must not run'); };
    const page = host();
    page.waitlistCommands = { overview: async () => ({code:200, root:{title:'Order',formLink:'current'}, people:[],offers:[],orders:[],serverTime:new Date().toISOString()}) };
    await page.init('old');
    assert.equal(window.location.pathname,'/form/current');
    assert.equal(new URLSearchParams(window.location.search).get('token'), 'b'.repeat(64));
    assert.equal(page.currentLink,'current');
});
