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
  const cleanup = startMeasurementConsent({model, setConsent:notify, host:document.querySelector('main'), includePurchaseConsent:true});
  return () => cleanup();
 }};
 const session = new FormMeasurementSession({model, transport, consentSource, entryAllowed:true, policySource});
 session.start();
 return session;
};`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
// The return regressions construct the session through production startMeasurement,
// including its onActive closure. Only the runtime's iframe/ACK boundary is modeled.
// IIFE evaluation has no module URL; the real preview uses it only for its stylesheet.
const PRODUCTION_MODULE_URL='https://tickets.example/src/components/forms/order_preview.js';
const productionBundle = await build({stdin:{contents:`
import {FormPage} from './src/components/forms/form_page.js';
import {FormModel} from './src/components/forms/form_models.js';
import {FormMeasurementRuntime} from './src/components/forms/form_measurement_runtime.js';
import {LocalizationService} from './src/services/localization_service.js';
import {DbForms} from './src/components/forms/db_forms.js';
import {SupabaseService} from './src/services/supabase_service.js';
import {FormAvailabilityService} from './src/components/forms/form_availability_service.js';
import {RightsService} from './src/services/rights_service.js';
import {SeoService} from './src/services/seo_service.js';
import {OrderResult} from './src/components/forms/order_result.js';
import {FormNetwork} from './src/components/forms/form_network.js';
import {purchaseConsentSnapshot} from './src/components/forms/meta_purchase_consent.js';
import {EmbedBridge} from './src/services/embed_bridge.js';
import {measurementManifest,measurementProtocol} from './src/components/forms/form_measurement_contract.js';
window.testModules={FormModel,DbForms,SupabaseService,FormAvailabilityService,RightsService,SeoService,OrderResult,FormNetwork,purchaseConsentSnapshot,EmbedBridge,measurementManifest,measurementProtocol};
window.startProductionForm = (translations, policySource, transport) => {
 LocalizationService.translations=translations;
 DbForms.getMeasurementPolicy=policySource;
 SupabaseService.getClient=()=>({auth:{},rpc:async()=>({error:null})});
 for(const method of ['activate','stop','renew','updateConsent','track']) FormMeasurementRuntime.prototype[method]=transport[method].bind(transport);
 const page=new FormPage(document.querySelector('main'));
 page.currentLink='test';
 page.currentSession={payload:{fields:[{4:11}]}};
 page.startMeasurement(window.returnModel(policySource()));
 return page;
};
window.returnModel = policy => ({link:'test',occasionTitle:'Letní koncert',data:{analytics:policy},visibleFields:[
 {id:4,type:'product_type',productTypeData:{title:'Vstupenky'},options:[{id:11,title:'Vstupenka',price:100,currency:'CZK'}]}]});
`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser',define:{'import.meta.url':JSON.stringify(PRODUCTION_MODULE_URL)},loader:{'.css':'empty'},plugins:[{name:'vite-asset-url',setup(builder){
 builder.onResolve({filter:/\?url$/},args=>({path:args.path,namespace:'asset-url'}));
 builder.onLoad({filter:/.*/,namespace:'asset-url'},()=>({contents:'export default "/fixture-asset.js"',loader:'js'}));
 }}],logLevel:'silent'});
const hostBundle = await build({stdin:{contents:`
import {createHostMeasurement} from './src/embed/host_measurement.js';
window.createTestHost = createHostMeasurement;
`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
const translations = JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
const settle = (ms=30) => new Promise(resolve => setTimeout(resolve, ms));
const none = {analytics:false, marketing:false}, both = {analytics:true, marketing:true};
const HOST = 'https://host.example', PRODUCT = 'https://tickets.example';
const basePolicy = () => ({enabled:true, organization_allowed:true, runtime_supported:true, eligible:true, organization:1, unit:2,
 runtime_origin:'https://festapp-measurement-unit-2.pages.dev', measurement_consent_bridge:true, privacy_url:'https://organizer.example/privacy',
 approved_hosts:[HOST], measurement_protocol:3, form_link:'test', profile:'gtm-v1', required_purposes:['analytics','marketing'],
 consent_revision:consentRevision, processing_revision:'rev-1', runtime_revision:1, policy_revision:1, valid_for_seconds:60});

function website() {
 const dom = new JSDOM('<a data-festapp-consent-link target="_blank" href="https://tickets.example/form/test">Koupit</a>', {url:HOST,runScripts:'outside-only'});
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
function linkedForm(site, {jar = new CookieJar(), policy = basePolicy(), opener = true, production = false} = {}) {
 const dom = new JSDOM('<html lang="cs"><body style="overflow:auto"><main></main></body></html>',
  {url:PRODUCT + '/form/test', referrer:HOST + '/event', cookieJar:jar, runScripts:'outside-only', pretendToBeVisual:true});
 const win = dom.window, grants = [];
 win.structuredClone=structuredClone;
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
 win.eval((production ? productionBundle : bundle).outputFiles[0].text);
 form.log = transportLog();
 form.events=[];
 form.log.transport.track=payload=>{form.events.push(clone(payload));return true;};
 const transport = {...form.log.transport, activate:grant => { form.log.transport.activate(grant); }};
 if(production) {
  form.page=win.startProductionForm(translations, () => form.policy, transport);
  form.session=form.page.measurementSession;
 }else form.session = win.startLinkedForm(translations, () => form.policy, transport);
 // The session reports consent to the transport; read it there, like the runtime does.
 form.consent = () => { const s = form.session; return {analytics:s.consent.analytics, marketing:s.consent.marketing}; };
 form.notice = () => !!win.document.querySelector('.cookie-modal-notice');
 form.fab = () => win.document.querySelector('.festapp-consent-fab');
 form.close = () => { form.closed = true; form.page?.clear(); form.session.dispose(); win.close(); };
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

// Keep the real link/CMP/session and real FormPage init/result lifecycle. Only
// backend, availability and form widgets are replaced at their boundaries.
async function returningPage(t, form) {
 const win=form.win;
 win.scrollTo=()=>{};
 const {DbForms,FormAvailabilityService,RightsService,SeoService,OrderResult}=win.testModules;
 const page=form.page;
 const runtime=page.measurementRuntime;
 const availability={getStatus:FormAvailabilityService.getStatus,renderStatus:FormAvailabilityService.renderStatus};
 t.mock.method(DbForms,'getFormByLink',async link=>({...win.returnModel(form.policy),link}));
 t.mock.method(DbForms,'getMeasurementPolicy',async()=>form.policy);
 t.mock.method(FormAvailabilityService,'getStatus',()=>({}));
 t.mock.method(FormAvailabilityService,'renderStatus',()=>false);
 t.mock.method(RightsService,'updateAppData',async()=>{});
 t.mock.method(RightsService,'canSeeReservations',()=>false);
 t.mock.method(SeoService,'updateMetaTags',()=>{});
 page.applyTheme=()=>{};
 page.renderForm=(model,preview)=>{
  page.currentSession={payload:{fields:[{4:11}]}};
  page.startMeasurement(model,preview);
 };
 t.mock.method(OrderResult,'render',(host,_success,_data,_model,back)=>{
  const button=win.document.createElement('button');button.className='btn-back-to-form';button.onclick=back;host.append(button);
 });
 return {page,runtime,availability,async back(){
  page.showFullScreenResult(true,{},{link:'test'});
  win.document.querySelector('.btn-back-to-form').click();
  await settle(120); // JSDOM history.back dispatches a real asynchronous popstate.
  assert.equal(win.document.querySelector('.fullscreen-result-overlay'),null);
 }};
}

test('Back to form after success retains the linked lease and second-order purchase consent',async t=>{
 const site=website(),binding={id:'00000000-0000-4000-8000-000000000001',version:1};
 site.registry.connect({read:()=>({consentRevision,analytics:true,marketing:true,binding,
  purchaseConsent:{source:'complianz',ad_storage:true,ad_user_data:true,ad_personalization:true}}),subscribe:()=>()=>{}});
 const form=linkedForm(site,{production:true,policy:{...basePolicy(),binding,websiteOrigin:HOST}});
 try{
  await ready(form);
  const {page,runtime,back}=await returningPage(t,form);
  const {purchaseConsentSnapshot}=form.win.testModules;
  const notice={revision:'checkout-revision',origin:HOST};
  const first=purchaseConsentSnapshot(form.session.consent,notice);assert.ok(first);
  const orders=page.purchaseConsentOrders;
  const attempt=orders.capture(first,notice);assert.equal(orders.canDispatch(attempt),true);
  orders.authorize(attempt,{orderId:1,token:'a'.repeat(64)});
  const lease=form.session.consent.leaseId,expires=form.session.consent.expiresAt,requests=site.requests.length;
  await back();
  assert.equal(page.measurementSession,form.session);assert.notEqual(runtime.disposed,true);
  assert.equal(form.win.opener,null);assert.equal(form.notice(),false);
  assert.equal(form.session.consent.leaseId,lease);assert.equal(form.session.consent.expiresAt,expires);
  assert.equal(site.requests.length,requests,'no second handshake or detach');
  assert.equal(page.purchaseConsentOrders,orders);
  const second=purchaseConsentSnapshot(page.measurementSession.consent,notice);assert.ok(second);
  assert.deepEqual(second.binding,first.binding);assert.equal(second.source,first.source);
  const {FormNetwork}=form.win.testModules;
  let sentPayload,finished;
  const shown=new Promise(resolve=>finished=resolve);
  t.mock.method(FormNetwork,'submitOrder',async(payload,options)=>{
   assert.equal(options.canSendMetaPurchaseConsent(),true);sentPayload=payload;
   return {success:true,data:{orderOverviewUrl:PRODUCT+'/order?order_id=2&token='+'b'.repeat(64)}};
  });
  page.currentSession={payload:{form:'test',ticket:[]},awaitPendingReservations:async()=>{},
   captureReservationCapability:()=>null,completeReservation:()=>{}};
  page.closePreview=()=>{};page.collectMetaCheckoutMatching=async()=>null;
  page.showFullScreenResult=()=>finished();
  page.submitOrder(form.win.document.createElement('form'),{},null,null,second);
  await shown;
  assert.deepEqual(sentPayload.metaPurchaseConsent,second);
  assert.equal(orders.orders.size,2);
  assert.deepEqual([...orders.orders.values()].map(order=>order.scope.orderId),[1,2]);
  const sequence=site.sent.at(-1).sequence;
  form.deliver({...site.sent.at(-1),sequence,choice:{analytics:false,marketing:false}});
  await settle();assert.deepEqual(form.consent(),both,'old sequence remains inert after return');
  const revoked=[];
  t.mock.method(form.win.testModules.SupabaseService,'getClient',()=>({auth:{},rpc:async(name,args)=>{
   assert.equal(name,'revoke_meta_purchase_consent');revoked.push(args.p_order_id);return {error:null};
  }}));
  const response=site.sent.at(-1);
  form.deliver({...response,sequence:sequence+1,choice:{analytics:false,marketing:false,purchaseConsent:{
   ...response.choice.purchaseConsent,ad_storage:false,ad_user_data:false,ad_personalization:false}}});
  await settle(80);assert.deepEqual(revoked.sort(),[1,2]);
  assert.equal(orders.orders.size,0,'both authorized orders observe the same withdrawal');
 }finally{form.close();site.close();}
});

test('Back to form keeps the same Meta CAPI lease without a GTM runtime',async t=>{
 const site=website(),binding={id:'00000000-0000-4000-8000-000000000001',version:1};
 site.registry.connect({read:()=>({consentRevision,analytics:true,marketing:true,binding,
  purchaseConsent:{source:'complianz',ad_storage:true,ad_user_data:true,ad_personalization:true}}),subscribe:()=>()=>{}});
 const policy={...basePolicy(),consent_only:true,runtime_supported:false,runtime_revision:0,profile:null,
  website_consent_bindings:[{...binding,websiteOrigin:HOST,effective:true}]};
 const form=linkedForm(site,{production:true,policy});
 try{
  await ready(form);
  const {page,back}=await returningPage(t,form);
  const notice={revision:'checkout-revision',origin:HOST};
  const lease=form.session.consent.leaseId;
  const requests=site.requests.length;
  assert.ok(page.currentPurchaseConsent(notice));
  await back();
  assert.equal(form.session.consent.leaseId,lease);
  assert.equal(site.requests.length,requests);
  assert.equal(form.session.grant,null);
  assert.ok(page.currentPurchaseConsent(notice));
  form.policy={...policy,website_consent_bindings:[{...binding,websiteOrigin:HOST,effective:false}]};
  await form.session.refresh();
  await settle();
  assert.equal(page.currentPurchaseConsent(notice),null);
 }finally{form.close();site.close();}
});

test('a failed policy refresh keeps checkout available without using the old purchase consent',async t=>{
 const site=website(),binding={id:'00000000-0000-4000-8000-000000000001',version:1};
 site.registry.connect({read:()=>({consentRevision,analytics:true,marketing:true,binding,
  purchaseConsent:{source:'complianz',ad_storage:true,ad_user_data:true,ad_personalization:true}}),subscribe:()=>()=>{}});
 const form=linkedForm(site,{production:true,policy:{...basePolicy(),binding,websiteOrigin:HOST}});
 try{
  await ready(form);
  const {page,back}=await returningPage(t,form);
  const notice={revision:'checkout-revision',origin:HOST};
  assert.ok(page.currentPurchaseConsent(notice));
  let offline=true;
  t.mock.method(form.win.testModules.DbForms,'getMeasurementPolicy',async()=>{
   if(offline)throw Error('offline');
   return form.policy;
  });
  const previousCheckout=page.currentSession;
  await back();
  assert.notEqual(page.currentSession,previousCheckout);
  assert.equal(page.measurementRefreshPending,null);
  assert.ok(form.session.consent.purchaseConsent,'the live choice survives for verified recovery');
  assert.equal(page.currentPurchaseConsent(notice),null);
  offline=false;
  await form.session.refresh();
  assert.ok(page.currentPurchaseConsent(notice));
 }finally{form.close();site.close();}
});

for(const end of ['expired','detached','closed','withdrawn','unknown','scope-changed'])test(`Back to form keeps fail-closed behavior when source is ${end}`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  if(end==='detached')site.win.dispatchEvent(new site.win.Event('pagehide'));
  if(end==='closed')site.closed=true;
  if(end==='withdrawn')site.choose(none);
  if(end==='unknown')site.choose(null);
  if(end==='scope-changed')form.policy={...form.policy,processing_revision:'different-revision'};
  if(end==='expired'){
   const deadline=form.session.consent.expiresAt;
   const original=form.win.Date.now;form.win.Date.now=()=>deadline+1;
   form.win.dispatchEvent(new form.win.Event('pageshow'));
   form.win.Date.now=original;
  }
  await settle(end==='closed'?1100:80);
  if(end==='scope-changed'){
   let releasePolicy;
   const freshPolicy=new Promise(resolve=>{releasePolicy=()=>resolve(form.policy);});
   t.mock.method(form.win.testModules.DbForms,'getMeasurementPolicy',()=>freshPolicy);
   const previousSession=page.currentSession;
   form.events.length=0;await back();
   try{
    assert.notEqual(page.currentSession,previousSession,'checkout renders while policy refresh is pending');
    assert.deepEqual(form.events,[],'checkout waits for fresh policy before sending events');
   }finally{releasePolicy();}
   await settle(80);
  }else await back();
  assert.equal(page.measurementSession,form.session);
  assert.deepEqual(form.consent(),none);
  if(end!=='withdrawn')assert.equal(form.notice(),true);
 }finally{form.close();site.close();}
});

for(const {link,path} of [{link:'different',path:'/form/test'},{link:'test',path:'/form/different'}])test(`success re-init tears down linked consent when requested link ${link} differs from ${path}`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,runtime}=await returningPage(t,form);
  // Do not create another real runtime; this test inspects teardown at load.
  page.renderForm=()=>{};
  form.win.history.replaceState({},'',path);
  await page.init(link,{forceReload:true,preserveMeasurement:true});
  assert.equal(form.session.disposed,true);assert.equal(runtime.disposed,true);
  assert.equal(page.measurementSession,null);
  assert.equal(site.requests.at(-1).type,'detach');
 }finally{form.close();site.close();}
});

for(const mode of ['waitlist-return','offer-success','waitlist-registration'])test(`${mode} tears down the previous linked consent owner`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,runtime}=await returningPage(t,form);
  if(mode==='waitlist-return'){
   page.renderWaitlistOutcome('registered',{form:{link:'test',data:{}}});
   form.win.document.querySelector('.btn-back-to-form').click();
   await settle(120);
  }else{
   let finished;const shown=new Promise(resolve=>finished=resolve);
   page.currentSession={payload:{ticket:[]},awaitPendingReservations:async()=>{},
    captureReservationCapability:()=>null,completeReservation:()=>{}};
   const overviewUrl=PRODUCT+'/order?order_id=1&token='+'a'.repeat(64);
   const oldSession=form.session;
   page.currentSession.formModel={key:'test',visibleFields:[]};
   page.currentSession.state={tickets:[]};
   page.waitlistCommands={accept:async()=>({order:{}}),command:async()=>({orderOverviewUrl:overviewUrl}),
    overview:async()=>{assert.equal(oldSession.disposed,true,'teardown precedes overview construction');throw Error('OVERVIEW_UNAVAILABLE');}};
   page.closePreview=()=>{};page.showFullScreenResult=()=>finished();
   page.submitOrder(form.win.document.createElement('form'),mode==='offer-success'?{offerBundle:true}:{registrationMode:'waitlist'});
   await shown;
  }
  assert.equal(form.session.disposed,true);assert.equal(runtime.disposed,true);
  assert.notEqual(page.measurementSession,form.session);
  assert.equal(site.requests.at(-1).type,'detach');
 }finally{form.close();site.close();}
});

for(const timing of ['active','ready-during-fetch','ready-after-render'])test(`return emits the fresh-session funnel and cart baseline: ${timing}`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  const {DbForms}=form.win.testModules;
  let resolveFetch;
  if(timing==='ready-during-fetch')t.mock.method(DbForms,'getFormByLink',()=>new Promise(resolve=>resolveFetch=resolve));
  let pendingGrant;
  if(timing==='ready-after-render')form.log.transport.activate=grant=>{pendingGrant=grant;};
  page.analytics.page('confirmation');
  form.events.length=0;
  await back();
  if(timing==='ready-during-fetch'){
   assert.equal(page.analytics,null);assert.equal(form.session.state,'active','runtime ACK preceded the form response');
   resolveFetch(form.win.returnModel(form.policy));await settle(80);
  }
  if(timing==='ready-after-render'){
   assert.equal(form.session.state,'starting');assert.equal(form.events.length,0);
   pendingGrant.onReady();await settle();
  }
  const returned=structuredClone(form.events);
  assert.deepEqual(returned.filter(p=>p.event).map(p=>p.event),['page_view','view_item']);
  assert.equal(returned.find(p=>p.page_type).page_type,'product');
  assert.equal(page.analytics.previous[0].quantity,1);
  page.analytics.observe(page.currentSession);await settle();
  assert.equal(form.events.some(p=>p.event==='add_to_cart'),false,'initial selection is a baseline, not a cart delta');
  // This is main's old full-teardown behavior, using the same production
  // constructors/model/transport, for a direct event-for-event comparison.
  if(resolveFetch)t.mock.method(DbForms,'getFormByLink',async()=>form.win.returnModel(form.policy));
  if(pendingGrant)form.log.transport.activate=grant=>grant.onReady();
  form.events.length=0;
  await page.init('test',{forceReload:true});await settle(100);
  assert.deepEqual(form.events,returned);
 }finally{form.close();site.close();}
});

for(const exit of ['404','error','full','closed','countdown','preview','sale-opening'])test(`return to ${exit} disposes the preserved session`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,runtime,availability,back}=await returningPage(t,form);
  const {DbForms,FormAvailabilityService,RightsService}=form.win.testModules;
  if(exit==='404')t.mock.method(DbForms,'getFormByLink',async()=>null);
  if(exit==='error')t.mock.method(DbForms,'getFormByLink',async()=>{throw Error('offline');});
  if(['full','closed','countdown'].includes(exit)){
   t.mock.method(FormAvailabilityService,'getStatus',availability.getStatus);
   t.mock.method(FormAvailabilityService,'renderStatus',availability.renderStatus);
   t.mock.method(DbForms,'getFormByLink',async()=>({...form.win.returnModel(form.policy),
    registrationMode:exit==='full'?'full':'closed',
    ...(exit==='countdown'?{startTime:new form.win.Date('2099-01-01'),enableCountdown:true}:{}),
   }));
  }
  if(exit==='preview'){
   form.win.history.replaceState(null,'','?preview=true');
   t.mock.method(RightsService,'canSeeReservations',()=>true);page.renderEditButton=()=>{};
  }
  if(exit==='sale-opening')page.saleOpeningScope={operation:'invalid'};
  await back();
  assert.equal(form.session.disposed,true);assert.equal(runtime.disposed,true);
  assert.equal(page.measurementSession,null);assert.equal(page.analytics,null);
  assert.equal(site.requests.at(-1).type,'detach');
 }finally{form.close();site.close();}
});

test('availability subscription starts new measurement without the previous checkout lease',async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  t.mock.method(form.win.testModules.FormAvailabilityService,'renderStatus',(_host,_model,_status,context)=>{context.onSaleOpening();return true;});
  form.events.length=0;await back();
  assert.notEqual(page.measurementSession,form.session);
  assert.equal(form.session.disposed,true);
  assert.equal(page.measurementSession.consent.leaseId,undefined);
  assert.equal(site.requests.at(-1).type,'detach');
  assert.equal(form.events.some(p=>p.event==='view_item'),false);
 }finally{form.close();site.close();}
});

for(const action of ['onReload','retry'])test(`${action} performs full teardown`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  const {DbForms,FormAvailabilityService}=form.win.testModules;
  if(action==='onReload'){
   let reload;
   t.mock.method(FormAvailabilityService,'renderStatus',(_host,_model,_status,context)=>{context.onSaleOpening();reload=context.onReload;return true;});
   await back();const openingSession=page.measurementSession;
   assert.notEqual(openingSession,form.session);
   await reload();assert.equal(openingSession.disposed,true);
  }else{
   t.mock.method(DbForms,'getFormByLink',async()=>{throw Error('offline');});
   let retry;page.renderError=(_message,callback)=>retry=callback;
   await back();assert.equal(form.session.disposed,true);
   // Keep an independent live stack to ensure the retry itself tears down,
   // rather than merely observing disposal by the preceding error screen.
   page.startMeasurement(form.win.returnModel(form.policy));const before=page.measurementSession;
   await retry();assert.equal(before.disposed,true);
  }
  assert.equal(form.session.disposed,true);
 }finally{form.close();site.close();}
});

for(const timing of ['active','ready-during-fetch'])test(`embedded return restores the host dataLayer funnel: ${timing}`,async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);
  const {page}=form;page.disposeMeasurement();
  const win=form.win,{EmbedBridge,measurementProtocol}=win.testModules;
  win.history.replaceState(null,'','/form/test?embed=1');
  win.ResizeObserver=class {observe(){} disconnect(){}};
  let host;
  const frame=site.win.document.createElement('iframe');frame.setAttribute('data-festapp-datalayer','');
  const record={};const frames=new Map([[frame,record]]);
  const parent={postMessage:data=>setTimeout(()=>host?.receive(frame,record,structuredClone(data)),0)};
  Object.defineProperty(win,'parent',{value:parent});
  const message=(type,values={})=>win.dispatchEvent(new win.MessageEvent('message',{
   source:parent,origin:HOST,data:{namespace:'festapp-embed',protocol:1,instance:'one',type,...values}}));
  record.channel={send:(type,values)=>setTimeout(()=>message(type,values),0)};
  site.win.eval(hostBundle.outputFiles[0].text);
  host=site.win.createTestHost({frames,currentRecord:(f,r)=>frames.get(f)===r,disposeRecord:()=>{},scan:()=>{},consentSource:site.registry});
  const bridge=page.embedBridge=new EmbedBridge(win);bridge.start();
  message('init',{viewportHeight:600,dataLayer:true,measurementProtocol});
  page.startMeasurement(win.returnModel(form.policy));form.session=page.measurementSession;
  await settle(120);assert.equal(form.session.state,'active');
  const {back}=await returningPage(t,form);
  let release;
  if(timing==='ready-during-fetch')t.mock.method(win.testModules.DbForms,'getFormByLink',()=>new Promise(resolve=>release=resolve));
  page.analytics.page('confirmation');await settle();site.win.dataLayer=[];
  await back();
  if(release){
   assert.equal(page.analytics,null);assert.equal(form.session.state,'active');
   release(win.returnModel(form.policy));await settle(80);
  }
  const returned=JSON.parse(JSON.stringify(site.win.dataLayer));
  assert.deepEqual(returned.filter(p=>p.event).map(p=>p.event),['form_page_view','view_item']);
  assert.equal(returned.find(p=>p.event==='form_page_view').page_type,'product');
  assert.equal(page.analytics.previous[0].quantity,1);
  page.analytics.observe(page.currentSession);await settle();
  assert.equal(site.win.dataLayer.some(p=>p.event==='add_to_cart'),false);
  // Compare with main's full-teardown behavior over the same real bridge and host adapter.
  t.mock.method(win.testModules.DbForms,'getFormByLink',async()=>win.returnModel(form.policy));
  site.win.dataLayer=[];
  await page.init('test',{forceReload:true});await settle(120);
  assert.deepEqual(JSON.parse(JSON.stringify(site.win.dataLayer)),returned);
  host.stopHeartbeat(record);
 }finally{form.close();site.close();}
});

test('superseding load and dispose prevent a stale RPC or onActive from activating a replacement layer',async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  let release;
  t.mock.method(form.win.testModules.DbForms,'getFormByLink',()=>new Promise(resolve=>release=resolve));
  await back();const oldActive=form.session.onActive;
  t.mock.method(form.win.testModules.DbForms,'getFormByLink',async()=>null);
  await page.init('another',{forceReload:true});
  form.events.length=0;release(form.win.returnModel(form.policy));oldActive();await settle();
  assert.equal(page.analytics,null);assert.equal(page.measurementSession,null);assert.deepEqual(form.events,[]);
  page.clear();oldActive();assert.deepEqual(form.events,[]);
 }finally{form.close();site.close();}
});

test('a disposed same-link session is never reused',async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page,back}=await returningPage(t,form);
  form.session.dispose();await back();
  assert.notEqual(page.measurementSession,form.session);
  assert.equal(form.session.disposed,true);
 }finally{form.close();site.close();}
});

test('entering a waitlist capability route tears down before reading its bundle',async t=>{
 const site=website();site.choose(both);const form=linkedForm(site,{production:true});
 try{
  await ready(form);const {page}=await returningPage(t,form);
  let read=false;
  page.waitlistCommands={read:async()=>{
   read=true;assert.equal(form.session.disposed,true);assert.equal(page.measurementSession,null);
   throw Error('INVALID_CAPABILITY');
  }};
  form.win.history.replaceState(null,'','/order?waitlist=1&order_id=1&token='+'a'.repeat(64));
  await page.init('test',{forceReload:true,preserveMeasurement:true});
  assert.equal(read,true);assert.equal(form.session.disposed,true);
 }finally{form.close();site.close();}
});

test('Back to form fetches the new Meta notice revision for the real preview and rejects stale checkout matching',async t=>{
 const site=website(),binding={id:'00000000-0000-4000-8000-000000000001',version:1};
 site.registry.connect({read:()=>({consentRevision,analytics:true,marketing:true,binding,
  purchaseConsent:{source:'complianz',ad_storage:true,ad_user_data:true,ad_personalization:true}}),subscribe:()=>()=>{}});
 const form=linkedForm(site,{production:true,policy:{...basePolicy(),website_consent_bindings:[{...binding,websiteOrigin:HOST,effective:true}]}});
 try{
  await ready(form);
  const win=form.win,{page}=form;
  const {FormModel,EmbedBridge,measurementProtocol,SupabaseService,DbForms,FormNetwork}=win.testModules;
  // Real embed and host adapters provide a nonempty positive matching control;
  // only RPC/order transport and the isolated measurement iframe are modeled.
  page.disposeMeasurement();win.history.replaceState(null,'','/form/test?embed=1');
  win.ResizeObserver=class {observe(){} disconnect(){}};
  let host;
  const frame=site.win.document.createElement('iframe');frame.setAttribute('data-festapp-datalayer','');
  const record={},frames=new Map([[frame,record]]),matchingRequests=[];
  const parent={postMessage:data=>setTimeout(()=>{
   if(data.type==='meta-checkout-matching-request')matchingRequests.push(structuredClone(data.matchingRequest));
   host?.receive(frame,record,structuredClone(data));
  },0)};
  Object.defineProperty(win,'parent',{value:parent});
  const message=(type,values={})=>win.dispatchEvent(new win.MessageEvent('message',{
   source:parent,origin:HOST,data:{namespace:'festapp-embed',protocol:1,instance:'one',type,...values}}));
  record.channel={send:(type,values)=>setTimeout(()=>message(type,values),0)};
  site.win.eval(hostBundle.outputFiles[0].text);
  host=site.win.createTestHost({frames,currentRecord:(f,r)=>frames.get(f)===r,disposeRecord:()=>{},scan:()=>{},consentSource:site.registry});
  page.embedBridge=new EmbedBridge(win);page.embedBridge.start();
  message('init',{viewportHeight:600,dataLayer:true,measurementProtocol});
  page.startMeasurement(win.returnModel(form.policy));form.session=page.measurementSession;
  await settle(120);assert.equal(form.session.state,'active');
  await returningPage(t,form);
  delete page.renderForm; // Exercise production renderForm, including metaPurchaseNotice.
  const model=()=>new FormModel({id:1,key:'test-key',link:'test',title:'Letní koncert',is_open:true,
   fields:[],data:{analytics:form.policy}});
  t.mock.method(DbForms,'getFormByLink',async()=>model());
  let revision='b'.repeat(32),noticeReads=0;
  t.mock.method(SupabaseService,'publicCheckoutRpc',async(name,args)=>{
   assert.equal(name,'get_meta_purchase_consent');assert.equal(args.p_form_link,'test');noticeReads++;
   return {data:{revision,origin:HOST}};
  });
  const payloads=[];
  t.mock.method(FormNetwork,'submitOrder',async(payload,options)=>{
   assert.equal(options.canSendMetaPurchaseConsent(),true);payloads.push(structuredClone(payload));
   return {success:true,data:{orderOverviewUrl:PRODUCT+'/order?order_id='+payloads.length+'&token='+'a'.repeat(64)}};
  });
  const waitFor=async predicate=>{
   for(let i=0;i<100&&!predicate();i++)await settle(10);
   assert.ok(predicate(),'expected checkout UI/state to settle');
  };
  const submitPreview=async()=>{
   const checkout=page.host.querySelector('form');assert.ok(checkout);
   await page.handlePreview(checkout,page.currentSession.formModel);
   await waitFor(()=>win.document.querySelector('#order-preview-overlay .btn-submit-order'));
   win.document.querySelector('#order-preview-overlay .btn-submit-order').click();
   await waitFor(()=>win.document.querySelector('.fullscreen-result-overlay .btn-back-to-form'));
  };
  const oldMatching='fb.1.1700000000000.first';
  site.win.document.cookie='_fbp='+oldMatching+';path=/';
  page.renderForm(model(),false);
  await page.metaPurchaseNotice.choice;
  const firstModel=page.currentSession.formModel;
  assert.equal(page.metaPurchaseNotice.model,firstModel);
  await submitPreview();
  const firstSnapshot=payloads[0].metaPurchaseConsent;
  assert.equal(firstSnapshot.revision,'b'.repeat(32));assert.equal(firstSnapshot.matching.fbp,oldMatching);
  const retained=page.measurementSession,readsBeforeBack=noticeReads;
  revision='c'.repeat(32);
  const newMatching='fb.1.1700000000001.second';
  site.win.document.cookie='_fbp='+newMatching+';path=/';
  win.document.querySelector('.fullscreen-result-overlay .btn-back-to-form').click();
  await waitFor(()=>page.currentSession?.formModel!==firstModel&&page.metaPurchaseNotice?.model===page.currentSession?.formModel);
  assert.equal((await page.metaPurchaseNotice.choice).revision,revision);
  assert.ok(noticeReads>readsBeforeBack,'return fetched a fresh notice through real DbForms');
  assert.equal(page.measurementSession,retained);
  const beforeStale=matchingRequests.length;
  const rejected=await page.collectMetaCheckoutMatching(page.currentSession.formModel,firstSnapshot);
  assert.deepEqual(JSON.parse(JSON.stringify(rejected)),{});
  assert.equal(matchingRequests.length,beforeStale,'old revision is rejected before requesting host identifiers');
  await submitPreview();
  assert.equal(payloads.length,2);
  assert.equal(payloads[1].metaPurchaseConsent.revision,revision);
  assert.equal(payloads[1].metaPurchaseConsent.matching.fbp,newMatching);
  assert.notEqual(payloads[1].metaPurchaseConsent.matching.fbp,oldMatching);
  assert.deepEqual(matchingRequests.map(request=>request.revision),['b'.repeat(32),'c'.repeat(32)]);
  host.stopHeartbeat(record);
 }finally{form.close();site.close();}
});
