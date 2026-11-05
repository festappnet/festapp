import {readFileSync} from 'node:fs';
import {LocalizationService} from '../../src/services/localization_service.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {FormModel} from '../../src/components/forms/form_models.js';
import {FormAvailabilityService as Availability} from '../../src/components/forms/form_availability_service.js';
import {CountdownWidget} from '../../src/components/forms/widgets/countdown_widget.js';
import {consumeSaleOpeningLocation, renderSaleOpening} from '../../src/components/forms/sale_opening_notifications.js';

LocalizationService.translations=JSON.parse(readFileSync(new URL('../../public/assets/translations/cs.json',import.meta.url),'utf8'));
LocalizationService.currentLocale='cs';
for (const timer of [false,true]) for (const first of [false,true]) {
 test(`saved order and duplicate slots; timer ${timer}, subscription first ${first}`, () => {
  const dom = new JSDOM('<main></main>'); globalThis.document = dom.window.document;
  const slot = '<div class="html-editor-block form-sale-opening-notification"></div>';
  const cd = '<div class="html-editor-block form-countdown"></div>';
  const model = new FormModel({link:'ples',is_open:true, saleOpeningNotification:{canSubscribe:true}, data:{schedule:{start_time:'2099-01-01T12:00:00Z', enable_countdown:timer,
   countdown_title:`<p>Intro</p>${first ? slot+cd : cd+slot}<p>End</p>${slot}${cd}`}}});
  try {
   const host = document.querySelector('main');
   assert.equal(Availability.renderStatus(host,model,Availability.getStatus(model)),true);
   assert.equal(host.querySelectorAll('.sale-opening-notification').length,1);
   assert.equal(host.querySelectorAll('input[type=email]').length,1);
   const optIn=host.querySelector('.sale-opening-notification');
   assert.equal(optIn.querySelector('h2'),null);
   assert.equal(optIn.querySelector('input').placeholder,'E-mail');
   assert.equal(optIn.querySelector('button').textContent,'Upozornit mě na začátek přihlašování');
   assert.equal(optIn.querySelector('.sale-opening-status').textContent,'');
   assert.equal(optIn.querySelector('.sale-opening-form').children.length,2);
   assert.equal(host.querySelectorAll('.countdown-widget').length,timer ? 1 : 0);
   if (timer) { const html = host.innerHTML; assert.equal(html.indexOf('sale-opening-notification')<html.indexOf('countdown-widget'),first); }
   assert.match(host.textContent,/Intro/); assert.match(host.textContent,/End/);
  } finally {CountdownWidget.stop();dom.window.close();}
 });
}
test('manual closure never exposes subscription and paused slot stays inactive',()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try {
 const model=new FormModel({is_open:false,saleOpeningNotification:{canSubscribe:false},data:{schedule:{start_time:'2099-01-01',countdown_title:'<p>Intro</p><div class="html-editor-block form-sale-opening-notification"></div>'}}});
 const host=document.querySelector('main');Availability.renderStatus(host,model,Availability.getStatus(model));assert.equal(host.querySelector('input'),null);
 model.isOpen=true;Availability.renderStatus(host,model,Availability.getStatus(model));assert.equal(host.querySelector('input'),null);assert.match(host.textContent,/Intro/);
 }finally{dom.window.close();}
});
test('link GET consumes fragment without mutation; only explicit submit posts',async()=>{
 const dom=new JSDOM('<main></main>',{url:`https://test.example/form/ples#sale_opening=unsubscribe&token=${'a'.repeat(64)}`});globalThis.document=dom.window.document;
 try {
 const scope=consumeSaleOpeningLocation(dom.window.location,dom.window.history,document);
 assert.equal(dom.window.location.hash,'');assert.equal(document.querySelector('meta[name=referrer]').content,'no-referrer');
 let calls=0;renderSaleOpening(document.querySelector('main'),{link:'ples'},{scope,command:async(operation,payload)=>{calls++;assert.equal(operation,'unsubscribe');assert.equal(payload.token,'a'.repeat(64));}});
 assert.equal(calls,0);document.querySelector('form').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
 await new Promise(resolve=>setTimeout(resolve,0));assert.equal(calls,1);assert.equal(document.querySelector('form').hidden,true);
 }finally{dom.window.close();}
});
test('network failure preserves email; preview never posts',async()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try{
 const host=document.querySelector('main');let calls=0;renderSaleOpening(host,{link:'ples'},{command:async()=>{calls++;throw new Error('offline');}});
 const input=host.querySelector('input');input.value='jana@example.com';host.querySelector('form').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
 await new Promise(resolve=>setTimeout(resolve,0));assert.equal(calls,1);assert.equal(input.value,'jana@example.com');assert.equal(host.querySelector('button').disabled,false);
 host.replaceChildren();renderSaleOpening(host,{link:'ples'},{preview:true,command:async()=>{calls++;}});host.querySelector('form').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));assert.equal(calls,1);
 }finally{dom.window.close();}
});

test('HTML sanitization keeps inert subscription slot but never stored active controls',()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try{
  const model=new FormModel({is_open:true,saleOpeningNotification:{canSubscribe:false},data:{schedule:{start_time:'2099-01-01',enable_countdown:false,countdown_title:'<p>Intro</p><div class="html-editor-block form-sale-opening-notification"><input type="email" value="leak@example.invalid"><button>Unsafe</button></div><script>alert(1)</script>'}}});
  const host=document.querySelector('main');Availability.renderStatus(host,model,Availability.getStatus(model));
  assert.equal(host.querySelector('input,button,script'),null);assert.doesNotMatch(host.innerHTML,/leak@example.invalid/);
 }finally{dom.window.close();}
});

test('expired capability displays the invalid-link state without exposing transport details',async()=>{
 const {saleOpeningCommand}=await import('../../src/components/forms/sale_opening_notifications.js');
 await assert.rejects(()=>saleOpeningCommand('confirm',{token:'a'.repeat(64)},{functions:{invoke:async()=>({data:null,error:{context:new Response(JSON.stringify({error:'invalid_link'}),{status:400})}})}}),/invalid/);
});


test('single opt-in succeeds directly and subscription-only layout has no automatic date',async()=>{
 const dom=new JSDOM('<main></main>');globalThis.document=dom.window.document;
 try{
  const host=document.querySelector('main');
  const model=new FormModel({link:'ples',is_open:true,saleOpeningNotification:{canSubscribe:true},data:{schedule:{start_time:'2099-01-01T12:00:00Z',enable_countdown:false,countdown_title:'<div class="html-editor-block form-sale-opening-notification"></div>'}}});
  Availability.renderStatus(host,model,Availability.getStatus(model));
  assert.doesNotMatch(host.textContent,/2099/);
  assert.equal(host.querySelector('.countdown-widget'),null);
  host.replaceChildren();
  let calls=0, release;renderSaleOpening(host,model,{command:async(operation,payload)=>{assert.equal(operation,'subscribe');assert.equal(payload.email,'jana@example.com');calls++;await new Promise(resolve=>{release=resolve;});return {ok:true};}});
  host.querySelector('input').value='jana@example.com';
  host.querySelector('form').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
  host.querySelector('input').value='changed@example.com';release();
  await new Promise(resolve=>setTimeout(resolve,0));
  assert.equal(calls,1);assert.equal(host.querySelector('form').hidden,true);
  assert.equal(host.querySelector('.sale-opening-status').textContent,'Jakmile se otevře přihlašování, pošleme Vám zprávu na jana@example.com.');
 }finally{CountdownWidget.stop();dom.window.close();}
});
