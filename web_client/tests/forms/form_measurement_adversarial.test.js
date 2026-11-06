import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormMeasurementRuntime} from '../../src/components/forms/form_measurement_runtime.js';
import {analyticsPayload,attributionContext} from '../../src/components/forms/form_measurement_contract.js';
import {serveMeasurement} from '../../../workers/form-measurement/src/worker.mjs';

const origin='https://unit-measurement.pages.dev',host='https://tickets.example';
function setup(t){
 const dom=new JSDOM('<body></body>',{url:host+'/form/summer',pretendToBeVisual:true});
 let callbacks=0,safe=true;
 const policy={enabled:true,organization_allowed:true,runtime_supported:true,privacy_url:"https://organizer.example/privacy",eligible:true,organization:1,unit:2,
  runtime_origin:origin,valid_for_seconds:60,policy_revision:1,configuration_revision:'one'};
 const model={link:'summer',data:{analytics:policy}};
 const runtime=new FormMeasurementRuntime({win:dom.window,model,canRun:()=>safe,onReady:()=>callbacks++});
 t.after(()=>{runtime.destroy();dom.window.close()});
 const send=(type,{source=runtime.frame?.contentWindow,instance=runtime.instance,messageOrigin=origin}={})=>dom.window.dispatchEvent(new dom.window.MessageEvent('message',{
  source,origin:messageOrigin,data:{namespace:'festapp-measurement',protocol:1,type,instance},
 }));
 return{dom,runtime,model,send,callbacks:()=>callbacks,unsafe:()=>safe=false};
}

test('detaching a ready iframe invalidates sends and the next renewal creates a fresh browsing context',t=>{
 const f=setup(t),r=f.runtime;r.start();f.send('ready');f.send('ack');
 const old=r.frame,oldWindow=old.contentWindow,oldInstance=r.instance;
 old.remove();assert.equal(r.measurementAllowed(),false);assert.equal(r.track({event:'page_view'}),false);
 r.updatePolicy();assert.notEqual(r.frame,old);assert.equal(r.frame.isConnected,true);
 f.send('ack',{source:oldWindow,instance:oldInstance});assert.equal(r.measurementAllowed(),false);
 f.send('ready');f.send('ack');assert.equal(r.measurementAllowed(),true);
});

test('a detached frame cannot finish its pending handshake',t=>{
 const f=setup(t),r=f.runtime;r.start();const source=r.frame.contentWindow,instance=r.instance;r.frame.remove();
 f.send('ack',{source,instance});assert.equal(f.callbacks(),0);assert.equal(r.measurementAllowed(),false);
});

test('expired policy drops an ACK even when its expiry timer has not run yet',t=>{
 const f=setup(t),r=f.runtime;r.start();const source=r.frame.contentWindow,instance=r.instance;
 r.policyUntil=Date.now()-1;f.send('ack',{source,instance});
 assert.equal(f.callbacks(),0);assert.equal(r.frame,null);assert.equal(r.measurementAllowed(),false);
});

test('an unsafe document cannot finish an earlier valid handshake',t=>{
 const f=setup(t),r=f.runtime;r.start();f.unsafe();f.send('ack');
 assert.equal(f.callbacks(),0);assert.equal(r.frame,null);
});

function generator(seed){return()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/2**32;};}

test('seeded event mutation keeps the receiver idempotent, bounded and free of injected fields',()=>{
 const next=generator(73306),secret='PRIVATE_SENTINEL_733';
 for(let i=0;i<1500;i++){
  const valid={event:'purchase',email:secret,user_data:{email:secret},__proto__:{phone:secret},
   ecommerce:{currency:'CZK',transaction_id:'11111111-1111-4111-8111-111111111111',payment_type:'card',
    items:[{item_id:'product_1',item_name:'Koncert',price:Math.round(next()*100000)/100,quantity:1+Math.floor(next()*20),token:secret}]}};
  const mode=i%8;
  if(mode===0)valid.ecommerce.items[0].quantity=next()>0.5?NaN:Infinity;
  if(mode===1)valid.ecommerce.items[0].price=-next();
  if(mode===2)valid.ecommerce.currency='CZK\n'+secret;
  if(mode===3)valid.ecommerce.transaction_id=secret;
  if(mode===4)valid.ecommerce.items=new Array(201).fill(valid.ecommerce.items[0]);
  if(mode===5)valid.ecommerce.items[0].item_id='seat_'+i;
  const payload=analyticsPayload(valid);
  if(payload){assert(!JSON.stringify(payload).includes(secret));assert.deepEqual(analyticsPayload(payload),payload);assert(payload.ecommerce.items.length<=200);}
  else assert(mode<6,'valid generated input should remain valid');
 }
});

test('script-breaking text, wrong scope and malformed backend responses fail at the actual Worker fetch/JSON seam',async t=>{
 const credential='SERVER_ONLY_SENTINEL_733';
 const config={organization:1,unit:2,form_id:3,form_link:'summer',runtime_origin:origin,parent_origin:host,profile:'gtm-v1',ancestor_origins:[host],collector_origins:[],
  policy:{eligible:true,runtime_supported:true},gtm_container:'GTM-AB12',scripts:'</ScRiPt><script>window.XSS="SECRET"</script>\u2028\u2029'};
 const env={ORGANIZATION_ID:1,UNIT_ID:2,FESTAPP_API_URL:'https://api.festapp.net',SUPABASE_SERVICE_ROLE_KEY:credential};
 const request=new Request(origin+'/runtime?form=summer&parent='+encodeURIComponent(host));
 let response;
 t.mock.method(globalThis,'fetch',async(url,options)=>{
  assert.equal(url,'https://api.festapp.net/rest/v1/rpc/get_form_measurement_runtime_config');assert.equal(options.redirect,'error');
  assert.equal(options.headers.authorization,'Bearer '+credential);assert.equal(JSON.parse(options.body).p_unit,2);
  return response;
 });
 for(const value of [new Response('not json',{status:200}),new Response('backend failure '+credential,{status:500}),Response.json({...config,unit:99})]){
  response=value;const result=await serveMeasurement(request,env);assert.equal(result.status,404);assert(!(await result.text()).includes(credential));
 }
 response=Response.json({...config,arbitrary_secret:credential});const result=await serveMeasurement(request,env);assert.equal(result.status,200);
 const html=await result.text();assert(!html.includes(credential));assert(!html.includes(config.scripts));
 const boot=JSON.parse(html.match(/id="measurement-config">([\s\S]*?)<\/script>/)[1]);assert.equal(boot.scripts,config.scripts);
});

test('seeded attribution mutations never expose query/fragment credentials or forged referrer paths',()=>{
 const next=generator(42);
 for(let i=0;i<500;i++){
  const value=attributionContext({page_location:host+'/form/summer',page_referrer:'https://ref.example/private?access_token=SECRET#secret',gclid:'safe_'+i,
   utm_source:next()>0.5?'newsletter':'private@example.test',access_token:'SECRET',history:{capability:'SECRET'}});
  assert(value);assert.equal(value.page_referrer,'https://ref.example/');assert(!JSON.stringify(value).includes('SECRET'));assert(!JSON.stringify(value).includes('@'));
 }
});

test('extreme cart mutations never export totals outside exact integer-cent arithmetic',()=>{
 const next=generator(99173);
 for(let i=0;i<500;i++){
  const price=(99000000000+Math.floor(next()*900000000))/100;
  const quantity=9000+Math.floor(next()*999);
  const items=Array.from({length:200},(_,index)=>({item_id:'product_'+(index+1),item_name:'Koncert',price,quantity}));
  const total=BigInt(Math.round(price*100))*BigInt(quantity)*200n;
  assert(total>BigInt(Number.MAX_SAFE_INTEGER));
  assert.equal(analyticsPayload({event:'view_item',ecommerce:{currency:'CZK',items}}),null);
 }
});

test('a real postMessage failure is a failed send and keeps the frame',t=>{
 const f=setup(t),r=f.runtime;r.start();f.send('ready');f.send('ack');const instance=r.instance;
 const target=r.frame.contentWindow,send=target.postMessage;target.postMessage=()=>{throw new DOMException('closed transport','DataCloneError')};
 assert.equal(r.track({event:'page_view'}),false);assert.equal(r.instance,instance);
 target.postMessage=send;assert.equal(r.track({event:'page_view'}),true);
});

test('seeded contact mutation: only a valid e-mail and E.164 phone leave, only on the two conversions',()=>{
 const next=generator(73307),secret='PRIVATE_SENTINEL_734',ecommerce={currency:'CZK',transaction_id:'11111111-1111-4111-8111-111111111111',payment_type:'card',items:[{item_id:'product_1',item_name:'Koncert',price:10,quantity:1}]};
 const lead={event:'generate_lead',event_id:'11111111-1111-4111-8111-111111111111',currency:'CZK',value:0,lead_source:'waitlist'};
 const hostile=[secret,secret+'@',secret+'@x',' '+secret+'@example.test',secret+'@example.test\n',secret+'@'+'x'.repeat(260)+'.cz','+'+secret,'+0123456789','<img src=x onerror=alert(1)>@example.test'.replace('@',' @'),{toString:()=>secret},[secret],null];
 for(let i=0;i<1500;i++){
  const pick=hostile[Math.floor(next()*hostile.length)],user_data={email:pick,phone_number:pick,phone:secret,name:secret,sha256_email_address:secret,__proto__:{email:secret}};
  for(const input of [{event:'purchase',ecommerce,user_data},{...lead,user_data}]){
   assert.equal(JSON.stringify(analyticsPayload(input)).includes(secret),false,JSON.stringify(pick));
  }
  for(const event of ['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','page_view','form_start','form_submit_error'])
   assert.equal(analyticsPayload({event,ecommerce,user_data:{email:'visitor@example.test',phone_number:'+420601234567'}})?.user_data,undefined,event);
 }
});
