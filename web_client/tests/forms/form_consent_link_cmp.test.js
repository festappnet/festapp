import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM, CookieJar} from 'jsdom';
import {installHostConsentLink} from '../../src/embed/host_consent_link.js';
import {createComplianzSource} from '../../src/embed/host_complianz.js';
import {complianzFixture, complianzConfig, consentRevision} from '../support/complianz_fixture.js';
import {createConsentSourceRegistry} from '../../src/components/forms/measurement_consent_source.js';

// Real website helper, Klaro and FormMeasurementSession over asynchronous
// postMessage. The Complianz public APIs are a modeled external boundary.
const bundle = await build({stdin:{contents:`
import {startMeasurementConsent} from './src/components/forms/form_measurement_cmp.js';
import {FormMeasurementSession} from './src/components/forms/form_measurement_session.js';
import {LocalizationService} from './src/services/localization_service.js';
window.startLinkedForm = (translations, policySource, transport) => {
 LocalizationService.translations = translations;
 const model = {link:'test', data:{}};
 const consentSource = {connect:(policy, notify) => {
  const cleanup = startMeasurementConsent({model, setConsent:notify, host:document.querySelector('main')});
  return () => cleanup();
 }};
 const session = new FormMeasurementSession({model, transport, consentSource, entryAllowed:true, policySource});
 session.start();
 return session;
};`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
const translations = JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
const settle = (ms=30) => new Promise(resolve => setTimeout(resolve, ms));
const none = {analytics:false, marketing:false}, both = {analytics:true, marketing:true};
const HOST = 'https://host.example', PRODUCT = 'https://tickets.example';
const basePolicy = () => ({enabled:true, organization_allowed:true, runtime_supported:true, eligible:true, organization:1, unit:2,
 runtime_origin:'https://festapp-measurement-unit-2.pages.dev', measurement_consent_bridge:true, privacy_url:'https://organizer.example/privacy',
 approved_hosts:[HOST], measurement_protocol:3, form_link:'test', profile:'gtm-v1', required_purposes:['analytics','marketing'],
 consent_revision:consentRevision, processing_revision:'rev-1', runtime_revision:1, policy_revision:1, valid_for_seconds:60});

function website() {
 const dom = new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Koupit</a>', {url:HOST});
 const win = dom.window;
 const cmp = complianzFixture(win);
 const registry = createConsentSourceRegistry();
 const disconnect = registry.connect(createComplianzSource(win, complianzConfig));
 const stop = installHostConsentLink(win, PRODUCT, registry);
 return {win, choose:cmp.choose, registry, requests:[], sent:[], closed:false, close() { stop(); disconnect(); win.close(); }};
}
function transportLog() {
 const log = {activations:[], stops:0, updates:[], renews:[]};
 log.transport = {
  selection:() => 'runtime',
  activate(grant) { log.activations.push({consent:{...grant.consent}, leaseId:grant.leaseId, expiresAt:grant.expiresAt}); grant.onReady(); },
  stop() { log.stops++; },
  updateConsent(value) { log.updates.push({analytics:value.analytics, marketing:value.marketing}); },
  renew(deadline) { log.renews.push(deadline); },
  track:() => true,
 };
 return log;
}
// Opens the form from a click on the website, like a real visitor.
function linkedForm(site, {jar = new CookieJar(), policy = basePolicy(), opener = true} = {}) {
 const dom = new JSDOM('<html lang="cs"><body style="overflow:auto"><main></main></body></html>',
  {url:PRODUCT + '/form/test', referrer:HOST + '/event', cookieJar:jar, runScripts:'outside-only', pretendToBeVisual:true});
 const win = dom.window, grants = [];
 const form = {win, grants, policy, closed:false};
 const clone = data => JSON.parse(JSON.stringify(data));
 const hostProxy = {get closed() { return site.closed; }, postMessage(data, origin) {
  if (origin !== HOST || site.closed) return;
  site.requests.push(clone(data));
  setTimeout(() => site.win.dispatchEvent(new site.win.MessageEvent('message', {source:childProxy, origin:PRODUCT, data:clone(data)})), 0);
 }};
 const childProxy = {get closed() { return form.closed; }, postMessage(data, origin) {
  if (origin !== PRODUCT || form.closed) return;
  site.sent.push(clone(data));
  setTimeout(() => form.deliver(data), 0);
 }};
 form.deliver = data => { if (!form.closed) win.dispatchEvent(new win.MessageEvent('message', {source:site.unloading ? null : hostProxy, origin:HOST, data:clone(data)})); };
 if (opener) {
  site.win.open = () => childProxy;
  site.win.document.querySelector('a').dispatchEvent(new site.win.MouseEvent('click', {bubbles:true, cancelable:true}));
  win.name = 'festapp-consent-link-00000000-0000-0000-0000-000000000000';
  win.opener = hostProxy;
 }
 win.eval(bundle.outputFiles[0].text);
 form.log = transportLog();
 const transport = {...form.log.transport, activate:grant => { form.log.transport.activate(grant); }};
 form.session = win.startLinkedForm(translations, () => form.policy, transport);
 // The session reports consent to the transport; read it there, like the runtime does.
 form.consent = () => { const s = form.session; return {analytics:s.consent.analytics, marketing:s.consent.marketing}; };
 form.notice = () => !!win.document.querySelector('.cookie-modal-notice');
 form.fab = () => win.document.querySelector('.festapp-consent-fab');
 form.close = () => { form.closed = true; form.session.dispose(); win.close(); };
 return form;
}
// Ready once the session has a manifest and the first website answer (if any) was applied.
const ready = async form => {
 for (let i = 0; i < 100 && !form.session.manifest; i++) await settle(10);
 for (let i = 0; i < 100 && form.win.document.querySelector('.festapp-consent-fab')?.hidden !== false && !form.notice(); i++) await settle(10);
 await settle(100);
};

test('Complianz link: a saved website choice reaches the transport with its lease and writes no cookie', async () => {
 const site = website(), form = (site.choose(both), linkedForm(site));
 try {
  await ready(form);
  assert.deepEqual(form.consent(), both);
  assert.equal(form.notice(), false); assert.equal(form.fab().hidden, false);
  const active = form.log.activations.at(-1);
  assert.equal(typeof active.leaseId, 'string', 'the grant is bound to the source lease');
  assert.deepEqual(form.log.updates.at(-1), both, 'the transport receives the imported choice');
  assert.ok(active.expiresAt <= Date.now() + 60000, 'transport never outlives the source lease');
  assert.equal(form.win.document.cookie, '', 'the import writes no cookie');
 } finally { form.close(); site.close(); }
});

// A: a changed processing scope mid-visit ends the import for good.
const changes = {
 processing_revision:p => { p.processing_revision = 'rev-2'; },
 policy_revision:p => { p.policy_revision = 2; },
 runtime_revision:p => { p.runtime_revision = 2; },
 bridge_disabled:p => { p.measurement_consent_bridge = false; p.processing_revision = 'rev-2'; },
 host_removed:p => { p.approved_hosts = ['https://other.example']; p.processing_revision = 'rev-2'; },
};
for (const [name, change] of Object.entries(changes)) test(`Complianz link: ${name} mid-visit ends the import, denies the transport and never re-imports`, async () => {
 const site = website(); site.choose(none); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  assert.deepEqual(form.consent(), both);
  const requests = site.requests.filter(m => m.type === 'request').length;
  const stops = form.log.stops;
  change(form.policy);
  await form.session.refresh(); await settle(60);
  assert.ok(form.log.stops > stops, 'the old grant is stopped');
  assert.deepEqual(form.consent(), none, 'the transport has no imported consent');
  assert.ok(form.log.activations.slice(-1).every(a => !a.consent.analytics && !a.consent.marketing), 'any new grant is denied');
  assert.ok(form.notice(), 'the form asks with its own notice');
  assert.equal(site.requests.filter(m => m.type === 'request').length, requests, 'no new request to the website');
  assert.ok(site.requests.some(m => m.type === 'detach'), 'the old channel is detached');
  // The website choice changes again; the new scope stays local.
  site.choose(none); site.choose(both); await settle(1200);
  assert.deepEqual(form.consent(), none);
  assert.equal(form.win.document.cookie, '');
 } finally { form.close(); site.close(); }
});

test('Complianz link: approved hosts change without a new revision keeps the server-derived scope', async () => {
 // processing_revision hashes parent_origins, so the server never changes hosts
 // alone. Documented here so a future contract change is noticed.
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  form.policy.approved_hosts = ['https://other.example'];
  await form.session.refresh(); await settle(60);
  assert.deepEqual(form.consent(), both, 'unchanged manifest keeps the live lease');
 } finally { form.close(); site.close(); }
});

// B: the explicit-source regressions, over the Complianz path.
test('Complianz link: replayed and out-of-order host messages cannot restore an old grant', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  const granted = site.sent.find(m => m.type === 'response' && m.choice.analytics);
  site.choose(none); await settle(1200);
  assert.deepEqual(form.consent(), none);
  form.deliver(granted); form.deliver({...granted}); await settle();
  assert.deepEqual(form.consent(), none, 'an old sequence is inert');
 } finally { form.close(); site.close(); }
});

test('Complianz link: absolute lease deadline revokes after a suspended timer, and policy renewal never extends it', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 const realNow = form.win.Date.now.bind(form.win.Date);
 try {
  await ready(form);
  const lease = form.log.activations.at(-1).expiresAt;
  assert.ok(form.log.renews.every(deadline => deadline <= lease), 'renewal is clamped to the lease');
  // Freeze the website so no heartbeat renews, then jump past the lease.
  site.closed = true;
  const skew = lease - realNow() + 1000;
  form.win.Date.now = () => realNow() + skew;
  await form.session.refresh(); await settle(60);
  assert.equal(form.session.permitted(), false, 'policy renewal cannot extend an expired source lease');
  form.deliver(site.sent.at(-1)); await settle(1100);
  assert.deepEqual(form.consent(), none);
  assert.ok(form.notice(), 'expiry restores the local notice');
 } finally { form.win.Date.now = realNow; form.close(); site.close(); }
});

test('Complianz link: a local choice in another tab wins over later website updates', async () => {
 const jar = new CookieJar(), site = website(); site.choose(both);
 const a = linkedForm(site, {jar});
 let b;
 try {
  await ready(a);
  assert.deepEqual(a.consent(), both);
  b = linkedForm(site, {jar, opener:false}); await ready(b);
  b.win.document.querySelector('.cn-decline').click(); await settle();
  site.choose({marketing:false}); await settle(1200);
  assert.deepEqual(a.consent(), none, 'the newer local decline is adopted');
  site.choose(both); await settle(1200);
  assert.deepEqual(a.consent(), none, 'the website no longer controls this visit');
 } finally { a.close(); b?.close(); site.close(); }
});

test('Complianz link: a website change during open settings never re-enables a switched-off purpose', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  form.fab().click(); await settle();
  form.win.document.querySelector('#service-item-analytics').click(); await settle();
  assert.deepEqual(form.consent(), {analytics:false, marketing:true}, 'a draft refusal applies immediately');
  site.choose({marketing:false}); await settle(1200);
  assert.deepEqual(form.consent(), none, 'the website narrows marketing; the draft keeps analytics off');
  assert.equal(form.win.document.cookie, '');
 } finally { form.close(); site.close(); }
});

test('Complianz link: Escape in settings restores the website choice without cookies', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  form.fab().click(); await settle();
  form.win.document.querySelector('#service-item-analytics').click(); await settle();
  assert.deepEqual(form.consent(), {analytics:false, marketing:true});
  form.win.document.activeElement.dispatchEvent(new form.win.KeyboardEvent('keydown', {key:'Escape', bubbles:true, cancelable:true})); await settle(100);
  assert.deepEqual(form.consent(), both, 'Escape restores the imported choice');
  assert.equal(form.win.document.cookie, '', 'Escape writes no cookie');
  assert.equal(form.notice(), false);
 } finally { form.close(); site.close(); }
});

test('Complianz link: closing the website ends the import within a second', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  site.closed = true; await settle(1200);
  assert.deepEqual(form.consent(), none); assert.ok(form.notice());
 } finally { form.close(); site.close(); }
});

test('Complianz link: a website revoke followed by a reload ends the import and asks locally', async () => {
 // Complianz reloads the page after a revoke: the denial streams first, then the page leaves.
 const site = website(); site.choose(both);
 const form = linkedForm(site);
 try {
  await ready(form);
  site.choose(none); await settle(1200);
  assert.deepEqual(form.consent(), none); assert.equal(form.notice(), false);
  // Browsers report another source for messages posted by an unloading page.
  site.unloading = true; site.win.dispatchEvent(new site.win.Event('pagehide')); await settle(100);
  assert.equal(site.sent.at(-1).type, 'end');
  assert.ok(form.notice(), 'the form asks with its own notice after the website left');
 } finally { form.close(); site.close(); }
});

test('Complianz link: an undecided website leaves the form notice; a saved refusal does not', async () => {
 const fresh = website(); fresh.choose(null);
 const a = linkedForm(fresh);
 try {
  await ready(a);
  assert.ok(a.notice(), 'a fresh website visit is undecided: the form asks');
  assert.equal(fresh.sent.at(-1)?.type, 'end');
  assert.deepEqual(a.consent(), none);
 } finally { a.close(); fresh.close(); }
 const refused = website(); refused.choose(none);
 const b = linkedForm(refused);
 try {
  await ready(b);
  assert.equal(b.notice(), false, 'an explicit refusal is taken over without a notice');
  assert.equal(b.fab().hidden, false); assert.deepEqual(b.consent(), none);
  assert.equal(b.win.document.cookie, '');
 } finally { b.close(); refused.close(); }
});

test('Complianz link: a fresh form cannot relabel an old choice with a new semantic scope', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site, {policy:{...basePolicy(), consent_revision:'b'.repeat(32), processing_revision:'new-processing'}});
 try { await ready(form); assert.deepEqual(form.consent(), none); assert.ok(form.notice()); }
 finally { form.close(); site.close(); }
});
test('Complianz link: a fresh form after a runtime-only deploy can reuse the same notice', async () => {
 const site = website(); site.choose(both);
 const form = linkedForm(site, {policy:{...basePolicy(), runtime_revision:2, processing_revision:'new-runtime'}});
 try { await ready(form); assert.deepEqual(form.consent(), both); assert.equal(form.notice(), false); }
 finally { form.close(); site.close(); }
});
