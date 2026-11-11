import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {FormMeasurementRuntime} from '../../src/components/forms/form_measurement_runtime.js';
import {EmbedBridge} from '../../src/services/embed_bridge.js';
import {measurementManifest,measurementProtocol} from '../../src/components/forms/form_measurement_contract.js';
import {runtimeSource} from '../../../workers/form-measurement/src/runtime_source.mjs';
import {FormMeasurementRuntime as OldRuntime} from '../fixtures/measurement_protocol_2/runtime.mjs';
import {EmbedBridge as OldBridge} from '../fixtures/measurement_protocol_2/bridge.mjs';
import {measurementManifest as oldManifest} from '../fixtures/measurement_protocol_2/contract.mjs';
import {runtimeSource as oldSource} from '../fixtures/measurement_protocol_2/bootstrap.mjs';
import {policy,purchase,fixture as sessionFixture} from '../support/measurement_fixture.js';

const parentOrigin='https://tickets.example',runtimeOrigin='https://unit-measurement.pages.dev';
for (const [name,Client,manifestForClient,source,manifestForWorker,expectsActive,contact] of [
 ['new/new',FormMeasurementRuntime,measurementManifest,runtimeSource,measurementManifest,true,true],
 ['new/old',FormMeasurementRuntime,measurementManifest,oldSource,oldManifest,false,false],
 ['old/new',OldRuntime,oldManifest,runtimeSource,measurementManifest,false,false],
 ['old/old with new SQL',OldRuntime,oldManifest,oldSource,oldManifest,true,false],
]) test(`frozen artifact matrix ${name}`,t=>{
 const parent=new JSDOM('<body><form><button>Submit</button></form>',{url:parentOrigin+'/form/summer',runScripts:'outside-only'});
 const transport=new Client({win:parent.window,model:{link:'summer'}});let active=false;
 const timers=new Map();let timer=0;parent.window.setTimeout=(fn,delay)=>{timers.set(++timer,{fn,delay});return timer;};parent.window.clearTimeout=id=>timers.delete(id);
 const currentPolicy={...policy,consent_revision:'a'.repeat(32),processing_revision:'sql-protocol-3'};
 const manifest=manifestForClient(currentPolicy,'summer'),workerManifest=manifestForWorker(currentPolicy,'summer');
 transport.activate({runtimeOrigin,manifest,generation:7,consent:{analytics:true,marketing:true},expiresAt:Date.now()+60000,onReady:()=>{active=true;},onMismatch(){}});
 const worker=new JSDOM('<script type="application/json" id="measurement-config"></script>',{url:runtimeOrigin+'/runtime',runScripts:'outside-only'});
 t.after(()=>{transport.destroy();parent.window.close();worker.window.close();});
 const frame=transport.frame.contentWindow;
 Object.defineProperty(worker.window,'parent',{value:{postMessage:message=>parent.window.dispatchEvent(new parent.window.MessageEvent('message',{source:frame,origin:runtimeOrigin,data:message}))}});
 frame.postMessage=message=>worker.window.dispatchEvent(new worker.window.MessageEvent('message',{source:worker.window.parent,origin:parentOrigin,data:message}));
 worker.window.document.getElementById('measurement-config').textContent=JSON.stringify({manifest:workerManifest,parent_origin:parentOrigin,form_link:'summer'});
 worker.window.eval(source);
 assert.equal(active,expectsActive);
 const sent=transport.track({...purchase,user_data:{email:'buyer@example.test'}});
 assert.equal(sent,expectsActive);
 const conversions=worker.window.dataLayer.filter(entry=>entry.event==='purchase');
 assert.equal(conversions.length,expectsActive?1:0);
 if(expectsActive)assert.equal(Boolean(conversions[0].user_data),contact);
 else {for(const {fn,delay} of [...timers.values()])if(delay===8000)fn();assert.equal(transport.frame,null);}
 // Measurement never changes the form's ability to submit.
 let submitted=false;parent.window.document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();submitted=true;});
 parent.window.document.querySelector('button').click();assert.equal(submitted,true);
});

test('new session rejects an actual old policy without manufacturing a current version',async t=>{
 const {measurement_protocol,...oldPolicy}=policy;
 assert.equal(oldManifest(oldPolicy,'summer')?.profile,'gtm-v1');assert.equal(measurementManifest(oldPolicy,'summer'),null);
 const f=sessionFixture(t,{source:async()=>oldPolicy});await f.start();assert.equal(f.starts.length,0);assert.equal(f.session.record(purchase),false);
});

for(const [helperName,BridgeClass,selection] of [['helper.js',EmbedBridge,null],['current',OldBridge,null],['current',EmbedBridge,'host']])test(`real helper/client matrix ${helperName}/${BridgeClass===OldBridge?'old':'new'}`,()=>{
 const host=new JSDOM('<iframe data-festapp-embed data-festapp-datalayer src="https://tickets.example/form/summer?embed=1"></iframe>',{url:'https://host.example',runScripts:'outside-only'});
 const frame=host.window.document.querySelector('iframe'),sent=[];frame.contentWindow.postMessage=message=>sent.push(message);
 const helper=readFileSync(new URL(helperName==='current'?'../../public/embed.js':'../fixtures/measurement_protocol_2/helper.js',import.meta.url),'utf8');host.window.eval(helper);
 const child=new JSDOM('<body></body>',{url:parentOrigin+'/form/summer?embed=1',pretendToBeVisual:true});
 const win=child.window;Object.defineProperty(win,'parent',{value:{postMessage(){}}});win.ResizeObserver=class{observe(){}disconnect(){}};
 globalThis.window=win;globalThis.document=win.document;
 const bridge=new BridgeClass(win);
 try{bridge.start();win.dispatchEvent(new win.MessageEvent('message',{source:win.parent,origin:'https://host.example',data:sent[0]}));assert.equal(bridge.selection(),selection);assert.equal(bridge.track(purchase),false);}
 finally{bridge.destroy();child.window.close();host.window.close();delete globalThis.window;delete globalThis.document;}
});
