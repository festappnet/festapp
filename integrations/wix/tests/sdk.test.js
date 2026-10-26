import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';

const registration=JSON.parse(readFileSync(new URL('../wix-app.json',import.meta.url),'utf8'));
const result=await build({entryPoints:[new URL('../src/widget.js',import.meta.url).pathname],bundle:true,write:false,format:'iife',target:['es2022']});
const bundle=result.outputFiles[0].text;
const tick=()=>new Promise(resolve=>setImmediate(resolve));

test('bundled self-managed entry binds the real Wix SDK to the assigned app before requesting Site mode',async()=>{
  const dom=new JSDOM('<vstupenky-online-form form-url="https://vstupenky.online/form/ukazka"></vstupenky-online-form>',{url:'https://wix-site.invalid',runScripts:'outside-only'});
  try {
    const calls=[];
    dom.window.clientSdk={async invoke(request){calls.push(request);return 'Site';}};
    dom.window.eval(bundle);
    await tick();
    assert.equal(calls.length,1);
    assert.equal(calls[0].applicationId,registration.appId);
    assert.equal(calls[0].namespace,'window');
    assert.equal(calls[0].method,'viewMode');
    assert.equal(dom.window.document.querySelector('iframe').src,'https://vstupenky.online/form/ukazka?embed=1');
  } finally {dom.window.close();}
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
