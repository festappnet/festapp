import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';

const registration=JSON.parse(readFileSync(new URL('../wix-app.json',import.meta.url),'utf8'));
const result=await build({entryPoints:[new URL('../src/widget.js',import.meta.url).pathname],bundle:true,write:false,format:'iife',target:['es2022']});
const bundle=result.outputFiles[0].text;
const tick=()=>new Promise(resolve=>setImmediate(resolve));

test('bundled entry accepts a late native token while Wix is still hydrating',async t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    dom.window.Headers=Headers;
    dom.window.clientSdk={async invoke(){return 'Site';}};
    const requests=[];
    dom.window.fetch=async(url,init)=>{
      assert.equal(init.signal.aborted,false,'native hydration must not exhaust the request deadline');
      requests.push({url,init});
      return {ok:true,json:async()=>({context:'cHJvdmVuYW5jZQ.'+'a'.repeat(64),expiresAt:Math.floor(Date.now()/1000)+86400})};
    };
    dom.window.eval(bundle);
    await tick();
    const element=dom.window.document.querySelector('vstupenky-online-form');
    t.mock.timers.tick(20000);
    await tick();
    assert.equal(element.mode,'Site','slow native initialization must keep the widget waiting');
    assert.equal(requests.length,0);
    assert.equal(element.querySelector('iframe'),null);
    element.accessTokenListener(async()=>'qa-late-native-token');
    await tick();
    assert.equal(requests.length,1);
    assert.equal(new Headers(requests[0].init.headers).get('authorization'),'qa-late-native-token');
    assert.ok(element.querySelector('iframe'));
  } finally {dom.window.close();}
});

test('bundled entry bounds missing native authentication and aborts a token delivered after expiry',async t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    dom.window.Headers=Headers;
    dom.window.clientSdk={async invoke(){return 'Site';}};
    let requests=0;
    dom.window.fetch=async(url,init)=>{
      if(init.signal.aborted)throw new dom.window.DOMException('Aborted','AbortError');
      requests++;
      throw Error('expired authentication must not send a request');
    };
    dom.window.eval(bundle);
    await tick();
    const element=dom.window.document.querySelector('vstupenky-online-form');
    t.mock.timers.tick(61000);
    await tick();
    assert.equal(element.mode,'Unavailable');
    assert.equal(element.querySelector('iframe'),null);
    element.accessTokenListener(async()=>'qa-expired-native-token');
    await tick();
    assert.equal(requests,0);
    assert.equal(element.querySelector('iframe'),null);
  } finally {dom.window.close();}
});

test('hidden time does not expire native authentication and visibility changes retain the remaining budget',async t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    let visibility='hidden', now=0;
    Object.defineProperty(dom.window.document,'visibilityState',{get:()=>visibility});
    dom.window.performance.now=()=>now;
    dom.window.Headers=Headers;
    dom.window.clientSdk={async invoke(){return 'Site';}};
    let requests=0;
    dom.window.fetch=async(url,init)=>{
      if(init.signal.aborted)throw new dom.window.DOMException('Aborted','AbortError');
      requests++;
      throw Error('expired authentication must not send a request');
    };
    dom.window.eval(bundle);
    await tick();
    const element=dom.window.document.querySelector('vstupenky-online-form');
    now+=120000;t.mock.timers.tick(120000);await tick();
    assert.equal(element.mode,'Site');
    visibility='visible';dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));
    now+=50000;t.mock.timers.tick(50000);await tick();
    assert.equal(element.mode,'Site');
    visibility='hidden';dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));
    now+=120000;t.mock.timers.tick(120000);await tick();
    assert.equal(element.mode,'Site');
    visibility='visible';dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'));
    now+=10001;t.mock.timers.tick(10001);await tick();
    assert.equal(element.mode,'Unavailable','visibility changes must not reset the visible timeout');
    element.accessTokenListener(async()=>'qa-expired-after-visible-budget');
    await tick();
    assert.equal(requests,0);
  } finally {dom.window.close();}
});

test('a native token delivered after a long hidden startup still mounts the verified checkout',async t=>{
  t.mock.timers.enable({apis:['setTimeout']});
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    Object.defineProperty(dom.window.document,'visibilityState',{value:'hidden'});
    dom.window.Headers=Headers;
    dom.window.clientSdk={async invoke(){return 'Site';}};
    let requests=0;
    dom.window.fetch=async(url,init)=>{
      assert.equal(init.signal.aborted,false);
      requests++;
      return {ok:true,json:async()=>({context:'cHJvdmVuYW5jZQ.'+'a'.repeat(64),expiresAt:Math.floor(Date.now()/1000)+86400})};
    };
    dom.window.eval(bundle);await tick();
    t.mock.timers.tick(120000);await tick();
    const element=dom.window.document.querySelector('vstupenky-online-form');
    assert.equal(element.mode,'Site');
    assert.equal(requests,0);
    element.accessTokenListener(async()=>'qa-hidden-late-token');
    await tick();
    assert.equal(requests,1);
    assert.ok(element.querySelector('iframe'));
  } finally {dom.window.close();}
});

test('bundled entry captures script-scoped Wix authentication before a widget is inserted later',async()=>{
  const dom=new JSDOM('<body></body>',{url:'https://wix-site.invalid',runScripts:'dangerously'});
  try {
    dom.window.Headers=Headers;
    dom.window.clientSdk={async invoke(){return 'Site';}};
    let tokenProbes=0;
    dom.window.wixEmbedsAPI={getAccessTokenFunction(){
      assert.equal(dom.window.document.currentScript?.tagName,'SCRIPT');
      tokenProbes++;
      return async()=>'qa-script-scoped-token';
    }};
    const requests=[];
    dom.window.fetch=async(url,init)=>{
      requests.push({url,init});
      return {ok:true,json:async()=>({context:'cHJvdmVuYW5jZQ.'+'a'.repeat(64),expiresAt:Math.floor(Date.now()/1000)+86400})};
    };
    const script=dom.window.document.createElement('script');
    script.textContent=bundle;
    dom.window.document.head.append(script);
    assert.equal(dom.window.document.currentScript,null);
    const element=dom.window.document.createElement('vstupenky-online-form');
    element.setAttribute('form-url','https://vstupenky.online/form/ukazka');
    dom.window.document.body.append(element);
    await tick();
    assert.equal(tokenProbes,1,'Wix can identify the app only while its script executes');
    assert.equal(requests.length,1,'delayed widget insertion must reach the proof endpoint without manual token injection');
    assert.equal(new Headers(requests[0].init.headers).get('authorization'),'qa-script-scoped-token');
    assert.ok(element.querySelector('iframe'));
  } finally {dom.window.close();}
});

test('bundled self-managed entry binds the real Wix SDK to the assigned app before requesting Site mode',async()=>{
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    dom.window.Headers=Headers;
    const calls=[];
    dom.window.clientSdk={async invoke(request){calls.push(request);return 'Site';}};
    const origin='cHJvdmVuYW5jZQ.'+'a'.repeat(64);
    const requests=[];
    dom.window.fetch=async(url,init)=>{
      requests.push({url,init});
      return {ok:true,json:async()=>({context:origin,expiresAt:Math.floor(Date.now()/1000)+86400})};
    };
    dom.window.eval(bundle);
    dom.window.document.querySelector('vstupenky-online-form').accessTokenListener(async()=>'qa-wix-token');
    await tick();
    assert.equal(calls.length,1);
    assert.equal(calls[0].applicationId,registration.appId);
    assert.equal(calls[0].namespace,'window');
    assert.equal(calls[0].method,'viewMode');
    assert.equal(requests.length,1);
    assert.equal(requests[0].url,'https://api.festapp.net/functions/v1/wix-checkout-context');
    assert.equal(new Headers(requests[0].init.headers).get('authorization'),'qa-wix-token');
    assert.deepEqual(JSON.parse(requests[0].init.body),{formLink:'ukazka'});
    assert.equal(dom.window.document.querySelector('iframe').src,`https://vstupenky.online/form/ukazka?embed=1&checkout_origin=${origin}`);
    assert.ok([...dom.window.document.querySelectorAll('a')].some(a=>a.href===`https://vstupenky.online/form/ukazka?checkout_origin=${origin}`));
  } finally {dom.window.close();}
});

test('bundled Wix entry never requests attribution in Editor or Preview',async()=>{
  for(const mode of ['Editor','Preview']) {
    const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
    try {
      dom.window.Headers=Headers;
      dom.window.clientSdk={async invoke(){return mode;}};
      let requests=0;dom.window.fetch=async()=>{requests++;throw new Error('unexpected request');};
      dom.window.eval(bundle);await tick();
      assert.equal(requests,0);assert.equal(dom.window.document.querySelector('iframe'),null);
    } finally {dom.window.close();}
  }
});

test('bundled self-managed entry fails closed when the real Wix host is unavailable',async()=>{
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    dom.window.eval(bundle);
    await tick();
    assert.equal(dom.window.document.querySelector('iframe'),null);
    assert.equal(dom.window.document.scripts.length,0);
    assert.match(dom.window.document.body.textContent,/nepodařilo načíst/);
  } finally {dom.window.close();}
});
