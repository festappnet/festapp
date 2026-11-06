import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { JSDOM } from 'jsdom';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';

const source = fs.readFileSync(new URL('../../../web/index.html', import.meta.url), 'utf8');
const bootstrap = [...source.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)]
  .map(match => match[1]).find(script => script.includes('__festappPaymentLink'));
assert.ok(bootstrap, 'the real payment callback bootstrap must be present');
for (const restored of [false, true]) {
  test(`A02 callback credentials removed before bootstrap, restored=${restored}`, () => {
    const callback = '/stripe/connect/callback?code=fixture_code&state=fixture_state&error_description=private&context=kept';
    const dom = new JSDOM('', { url: `https://tickets.example${restored ? '/flutter.html?redirect=' + encodeURIComponent(callback) : callback}`, runScripts: 'outside-only' });
    try {
      dom.window.eval(bootstrap);
      assert.deepEqual(JSON.parse(dom.window.__festappStripeConnectCallback), { code: 'fixture_code', state: 'fixture_state' });
      assert.equal(dom.window.location.pathname, '/stripe/connect/callback');
      assert.equal(dom.window.location.search, '?context=kept');
      assert.equal(dom.window.localStorage.length, 0);
      assert.equal(dom.window.sessionStorage.length, 0);
    } finally { dom.window.close(); }
  });
}
test('A02 callback capture does not consume unrelated login or foreign redirects', () => {
  for (const path of ['/google-auth?code=other', '/flutter.html?redirect=' + encodeURIComponent('https://foreign.example/stripe/connect/callback?code=other')]) {
    const dom = new JSDOM('', { url: 'https://tickets.example' + path, runScripts: 'outside-only' });
    try {
      dom.window.eval(bootstrap);
      assert.equal(dom.window.__festappStripeConnectCallback, undefined);
      assert.equal(dom.window.location.href, 'https://tickets.example' + path);
    } finally { dom.window.close(); }
  }
});
test('A08/A11 pay and return scopes are captured separately before analytics with safe browser Back recovery',()=>{
  const token='a'.repeat(64);
  for(const [path,kind] of [[`/stripe/pay#pay=${token}`,'pay'],[`/stripe/return?return_handle=${token}`,'return']]) {
    const dom=new JSDOM('',{url:'https://tickets.example'+path,runScripts:'outside-only'});
    try{
      dom.window.eval(bootstrap);
      assert.deepEqual(JSON.parse(dom.window.__festappPaymentLink),{provider:'stripe',kind,token});
      assert.equal(dom.window.location.hash,'');assert.equal(dom.window.location.search,'');
      assert.equal(dom.window.sessionStorage.length,0);assert.equal(dom.window.localStorage.length,0);
      if(kind==='pay'){
        delete dom.window.__festappPaymentLink;
        dom.window.history.replaceState({festappStripePayment:{provider:'stripe',kind,token}},'','/stripe/pay');
        dom.window.eval(bootstrap);
        assert.equal(JSON.parse(dom.window.__festappPaymentLink).token,token);
      }
    }finally{dom.window.close();}
  }
});

test('A20 handoff is captured as its own single-use scope and never restored from pay history',()=>{
 const token='c'.repeat(64);const dom=new JSDOM('',{url:'https://tickets.example/stripe/pay#handoff='+token,runScripts:'outside-only'});
 try{dom.window.eval(bootstrap);assert.deepEqual(JSON.parse(dom.window.__festappPaymentLink),{provider:'stripe',kind:'handoff',token});assert.equal(dom.window.location.hash,'');assert.equal(dom.window.history.state,null);assert.equal(dom.window.sessionStorage.length,0);delete dom.window.__festappPaymentLink;dom.window.eval(bootstrap);assert.equal(dom.window.__festappPaymentLink,undefined);}finally{dom.window.close();}
});


test('generic payment bootstrap binds private scopes and history to its provider',()=>{
 const token='d'.repeat(64);
 const dom=new JSDOM('',{url:`https://tickets.example/payments/another_gateway/pay#pay=${token}`,runScripts:'outside-only'});
 try {
  dom.window.eval(bootstrap);
  assert.deepEqual(JSON.parse(dom.window.__festappPaymentLink),{provider:'another_gateway',kind:'pay',token});
  assert.equal(dom.window.location.hash,'');
  delete dom.window.__festappPaymentLink;
  dom.window.history.replaceState({festappPayment:{provider:'foreign_gateway',kind:'pay',token}},'','/payments/another_gateway/pay');
  dom.window.eval(bootstrap);assert.equal(dom.window.__festappPaymentLink,undefined);
 } finally {dom.window.close();}
});

test('Barion departure and real shell bootstrap share the provider-bound history contract',()=>{
 const dom=new JSDOM('',{url:'https://tickets.example/payments/barion/pay',runScripts:'outside-only'});
 const previous={window:globalThis.window,document:globalThis.document};
 Object.assign(globalThis,{window:dom.window,document:dom.window.document});
 const token='e'.repeat(64), navigation=[];
 const controller=CardPaymentController.fromResult({payment:{method:'barion',status:'open'},
  payment_access:{token,url:`https://tickets.example/payments/barion/pay#pay=${token}`}},
  {navigate:url=>navigation.push(url),invoke:async()=>({})});
 try {
  assert.ok(controller);
  controller.openPrepared('https://secure.test.barion.com/Pay?Id='+'a'.repeat(32));
  assert.equal(navigation.length,1);
  assert.deepEqual(dom.window.history.state.festappPayment,{provider:'barion',kind:'pay',token});
  dom.window.eval(bootstrap);
  assert.deepEqual(JSON.parse(dom.window.__festappPaymentLink),{provider:'barion',kind:'pay',token});
 } finally {controller?.dispose();dom.window.close();Object.assign(globalThis,previous);}
});
