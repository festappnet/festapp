import test from 'node:test';
import assert from 'node:assert/strict';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
import {FormDataLayer} from '../../src/components/forms/form_datalayer.js';
import {analyticsPayload} from '../../src/components/forms/form_measurement_contract.js';
import {renderSaleOpening} from '../../src/components/forms/sale_opening_notifications.js';
import {FormAvailabilityService as Availability} from '../../src/components/forms/form_availability_service.js';
import {FormModel} from '../../src/components/forms/form_models.js';
import {CountdownWidget} from '../../src/components/forms/widgets/countdown_widget.js';
import {fixture, settle} from '../support/measurement_fixture.js';
register('../css_loader.mjs',import.meta.url);

const slot='<div class="html-editor-block form-sale-opening-notification"></div>';
for(const variant of ['subscribe','paused','missing-slot','unavailable','full','preview'])test('presale measurement entry: '+variant,async t=>{
 const dom=new JSDOM('<div id="page"></div>',{url:'https://tickets.test/form/summer'});
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,HTMLElement:dom.window.HTMLElement,CustomEvent:dom.window.CustomEvent});
 dom.window.scrollTo=()=>{};
 const [{FormPage},{DbForms},{RightsService},{SeoService}]=await Promise.all([
  import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),
  import('../../src/services/rights_service.js'),import('../../src/services/seo_service.js')]);
 const model=new FormModel({link:'summer',is_open:true,registrationMode:'closed',saleOpeningNotification:{canSubscribe:!['paused','unavailable'].includes(variant)},
  data:{schedule:{start_time:'2099-01-01',countdown_title:variant==='missing-slot'?'Intro':variant==='unavailable'?null:slot}}});
 if(variant==='full'){model.data.schedule.start_time=null;model.registrationMode='full';}
 t.mock.method(DbForms,'getFormByLink',async()=>model);
 t.mock.method(RightsService,'canSeeReservations',()=>false);
 t.mock.method(SeoService,'updateMetaTags',()=>{});
 const page=new FormPage('page');t.mock.method(page,'applyTheme',()=>{});
 const start=t.mock.method(page,'startMeasurement',()=>null);
 t.after(()=>{page.clear();CountdownWidget.stop();dom.window.close();});
 if(variant==='preview')Availability.renderStatus(page.host,model,Availability.getStatus(model),{showPreview:true,onSaleOpening:()=>page.startMeasurement()});
 else await page.init('summer');
 assert.equal(start.mock.callCount(),variant==='subscribe'?1:0);
 if(variant==='subscribe')assert.deepEqual(start.mock.calls[0].arguments,[model,false,'sale_opening']);
});

for(const mode of ['success','failure','unsubscribe','preview'])test('notification lead: '+mode,async t=>{
 const dom=new JSDOM('<html lang="cs"><main></main></html>');globalThis.document=dom.window.document;
 t.after(()=>dom.window.close());
 const host=document.querySelector('main'),sent=[];
 const model={link:'summer',visibleFields:[{type:'product_type',options:[{currency:'EUR'}]}]};
 const layer=new FormDataLayer({win:dom.window,model,sink:{record:p=>{sent.push(analyticsPayload(p));return true;},capture:()=>p=>{sent.push(analyticsPayload(p));return true;}}});
 let calls=0,release;
 renderSaleOpening(host,model,{analytics:layer,preview:mode==='preview',scope:mode==='unsubscribe'?{operation:'unsubscribe',token:'a'.repeat(64)}:null,
  command:async()=>{calls++;await new Promise(resolve=>{release=resolve;});if(mode==='failure')throw Error('offline');}});
 const input=host.querySelector('input');if(input){input.value='Jana@Example.com';input.dispatchEvent(new dom.window.Event('input'));}
 const form=host.querySelector('form'),submit=()=>form.dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
 submit();submit();assert.equal(calls,mode==='preview'?0:1);
 if(release)release();await settle();
 if(mode==='success'){
  submit();const leads=sent.filter(p=>p.event==='generate_lead');assert.equal(leads.length,1);
  assert.deepEqual(leads[0],{event:'generate_lead',lead_source:'sale_opening_notification',value:0,currency:'EUR',event_id:leads[0].event_id,user_data:{email:'jana@example.com'}});
  assert.match(leads[0].event_id,/^[0-9a-f-]{36}$/);assert.equal(sent.filter(p=>p.event==='form_start').length,1);
 }else assert.equal(sent.some(p=>p.event==='generate_lead'),false);
});

test('sale-opening page and captured lead use the normal session boundary',async t=>{
 const f=fixture(t);f.session.onActive=()=>f.layer.page('sale_opening');await f.start();
 assert.deepEqual(f.sent,[{page_type:'sale_opening',user_type:'b2c',language:'cs'},{event:'page_view'}]);
 const complete=f.layer.captureSaleOpening(' JANA@example.com ');complete();complete();
 assert.equal(f.sent.filter(p=>p.event==='generate_lead').length,1);
 const stale=f.layer.captureSaleOpening('jana@example.com');f.identity('staff');stale();
 assert.equal(f.sent.filter(p=>p.event==='generate_lead').length,1);
});

for(const role of ['anonymous','staff','ineligible'])test('shared presale stack keeps embed consent and policy exclusion: '+role,async t=>{
 const dom=new JSDOM('<div id="page"></div>',{url:'https://tickets.test/form/summer?embed=1'});
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,HTMLElement:dom.window.HTMLElement,CustomEvent:dom.window.CustomEvent});
 const [{FormPage},{DbForms},{SupabaseService},{policy}]=await Promise.all([
  import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),
  import('../../src/services/supabase_service.js'),import('../support/measurement_fixture.js')]);
 t.mock.method(DbForms,'getMeasurementPolicy',async()=>({...policy,visitor_role:role==='staff'?'staff':'anonymous',eligible:role!=='ineligible'}));
 t.mock.method(SupabaseService,'getClient',()=>({auth:{}}));
 const page=new FormPage('page'),sent=[];let connected=0,attached;
 page.embedBridge={setMeasurementRuntime(runtime){attached=runtime;},connectConsent(_policy,notify){connected++;notify({analytics:true,marketing:true});return ()=>{};},
  activate(grant){grant.onReady();},track(p){sent.push(analyticsPayload(p));return true;},stop(){},destroy(){}};
 t.after(()=>{page.clear();dom.window.close();});
 const model=new FormModel({link:'summer'});
 const layer=page.startMeasurement(model,false,'sale_opening');await settle();
 assert.equal(page.startMeasurement(model,false,'sale_opening'),layer,'one stack per page');
 assert.equal(attached,page.measurementRuntime);assert.equal(attached.embedded,true);assert.equal(connected,1);
 assert.deepEqual(sent,role==='anonymous'?[{page_type:'sale_opening',user_type:'b2c'},{event:'page_view'}]:[]);
});
