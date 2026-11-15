import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {formUrl, settingsFrom, TAG_NAME, SERVICE_ORIGIN, HELP_URL, PROPERTIES} from '../src/config.js';
import {registerTicketElement} from '../src/element.js';
import {initSettings, saveSettings} from '../src/settings_controller.js';

const tick = () => new Promise(resolve => setImmediate(resolve));

test('verified provenance survives direct-link fallback and stale form responses cannot replace checkout',async()=>{
  const dom=new JSDOM('<body></body>',{url:'https://wix-site.invalid'});
  const pending=[];
  registerTicketElement(dom.window,async()=>'Site',{
    injectToken:()=>()=>{},context:url=>new Promise(resolve=>pending.push({url,resolve})),
  });
  const e=dom.window.document.createElement(TAG_NAME);
  e.setAttribute('form-url',`${SERVICE_ORIGIN}/form/a`);dom.window.document.body.append(e);
  try {
    await tick();assert.equal(dom.window.document.querySelector('iframe'),null);
    e.setAttribute('form-url',`${SERVICE_ORIGIN}/form/b`);await tick();
    pending[0].resolve('old-proof');await tick();assert.equal(dom.window.document.querySelector('iframe'),null);
    pending[1].resolve('current-proof');await tick();
    const frame=dom.window.document.querySelector('iframe');
    assert.equal(frame.src,`${SERVICE_ORIGIN}/form/b?embed=1&checkout_origin=current-proof`);
    assert.equal(dom.window.document.querySelector('a').href,`${SERVICE_ORIGIN}/form/b?checkout_origin=current-proof`);
    e.setAttribute('form-title','Updated title');await tick();
    assert.equal(dom.window.document.querySelector('iframe'),frame);assert.equal(pending.length,2);
  } finally {dom.window.close();}
});

test('context failure cannot silently render an unattributed Wix checkout',async()=>{
  const dom=new JSDOM('<body></body>',{url:'https://wix-site.invalid'});
  registerTicketElement(dom.window,async()=>'Site',{injectToken:()=>()=>{},context:async()=>{throw new Error('unavailable');}});
  const e=dom.window.document.createElement(TAG_NAME);e.setAttribute('form-url',`${SERVICE_ORIGIN}/form/a`);
  dom.window.document.body.append(e);
  try {await tick();assert.equal(dom.window.document.querySelector('iframe'),null);
    assert.equal([...dom.window.document.querySelectorAll('a')].some(a=>a.href.startsWith(`${SERVICE_ORIGIN}/form/`)),false);
  } finally {dom.window.close();}
});
function host(mode) {
  const dom = new JSDOM('<body></body>', {url: 'https://wix-site.invalid'});
  registerTicketElement(dom.window, mode);
  const element = dom.window.document.createElement(TAG_NAME);
  element.setAttribute('form-url', `${SERVICE_ORIGIN}/form/ukazka`);
  dom.window.document.body.append(element);
  return {dom, element, document: dom.window.document};
}

test('only canonical public tenant forms pass; credentials, query tokens, normalization and injection are rejected', () => {
  assert.equal(formUrl(`${SERVICE_ORIGIN}/form/ukazka`), `${SERVICE_ORIGIN}/form/ukazka`);
  assert.equal(formUrl(`${SERVICE_ORIGIN}/form/${encodeURIComponent('Český_ples-2027')}`), `${SERVICE_ORIGIN}/form/${encodeURIComponent('Český_ples-2027')}`);
  for (const path of ['/login','/form/','/form/a/b','/form/a/../b','/form/a?token=secret','/form/a#edit','/form/a?','/form/a#','/form/a%2Fb','/form/a%252Fb','/form/a%20b','/form/%00','/form/%3Cscript%3E','/form/a/']) assert.equal(formUrl(SERVICE_ORIGIN + path), null, path);
  for (const url of ['https://other.invalid/form/a','http://vstupenky.online/form/a','https://vstupenky.online.evil.invalid/form/a','https://user:pass@vstupenky.online/form/a','https://vstupenky.online:444/form/a']) assert.equal(formUrl(url), null, url);
});

test('Editor, Preview and unavailable Wix context never load a live form or service helper', async () => {
  for (const mode of ['Editor','Preview',undefined]) {
    const {dom, element, document} = host(async () => mode);
    await tick();
    assert.equal(element.querySelector('iframe'), null);
    element.setAttribute('inherit-style', 'false');
    assert.equal(element.querySelector('iframe'), null);
    assert.equal(document.scripts.length, 0);
    assert.equal(element.querySelector('a').href, HELP_URL);
    dom.window.close();
  }
  const {dom, element, document} = host(async () => {throw Error('no Wix context');});
  await tick();
  assert.match(element.textContent, /nepodařilo/);
  assert.equal(element.querySelector('p a').href, `${SERVICE_ORIGIN}/form/ukazka`);
  assert.equal(document.scripts.length, 0);
  dom.window.close();
});

test('late Wix mode response after removal cannot mount a remote frame', async () => {
  let resolve;
  const {dom, element, document} = host(() => new Promise(done => {resolve = done;}));
  await tick();
  element.remove(); resolve('Site'); await tick();
  assert.equal(element.childElementCount, 0);
  assert.equal(document.scripts.length, 0);
  dom.window.close();
});

test('live widgets isolate frames, reuse the canonical helper and preserve checkout on presentation updates', async () => {
  const {dom, element, document} = host(async () => 'Site');
  const second = document.createElement(TAG_NAME);
  second.setAttribute('form-url', `${SERVICE_ORIGIN}/form/another`);
  document.body.append(second);
  await tick();
  const frame = element.querySelector('iframe');
  assert.equal(document.scripts.length, 1);
  assert.equal(document.scripts[0].src, `${SERVICE_ORIGIN}/embed.js`);
  assert.equal(frame.src, `${SERVICE_ORIGIN}/form/ukazka?embed=1`);
  assert.notEqual(frame, second.querySelector('iframe'));
  assert.ok(frame.parentElement.hasAttribute('data-festapp-embed-host'));
  assert.equal(frame.hasAttribute('width'), false);
  assert.equal(frame.style.width, '100%');
  element.setAttribute('form-title', '<script>not html</script>');
  element.setAttribute('inherit-style', 'false');
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(frame.title, '<script>not html</script>');
  assert.equal(frame.dataset.festappStyle, undefined);
  assert.equal(frame.src, `${SERVICE_ORIGIN}/form/ukazka?embed=1`);
  element.setAttribute('inherit-style', 'true');
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(frame.dataset.festappStyle, undefined);
  element.setAttribute('inherit-style', '"><script>bad</script>');
  assert.equal(frame.dataset.festappStyle, undefined);
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(second.querySelector('iframe').dataset.festappStyle, undefined);
  assert.equal(document.scripts.length, 1);
  assert.equal(element.querySelector('script'), null);
  element.setAttribute('form-url', 'https://other.invalid/form/a');
  assert.equal(element.querySelector('iframe'), null);
  assert.ok(second.querySelector('iframe'));
  dom.window.close();
});

test('settings validate before any writes, serialize readbacks and stop on a failed write', async () => {
  const calls = [], data = {};
  const api = {async setProp(name,value) {calls.push(['set',name,value]);data[name]=value;},async getProp(name) {calls.push(['get',name]);return data[name];}};
  await assert.rejects(saveSettings(api, {'form-url':'https://evil.invalid/form/a'}));
  assert.equal(calls.length, 0);
  await saveSettings(api, {'form-url':`${SERVICE_ORIGIN}/form/ukazka`,'form-title':'Test','inherit-style':'false'});
  assert.deepEqual(calls.map(call=>call.slice(0,2)), PROPERTIES.flatMap(name=>[['set',name],['get',name]]));
  assert.equal(data['inherit-style'], undefined);
  const writes=[];
  await assert.rejects(saveSettings({async setProp(name) {writes.push(name);},async getProp() {return 'unexpected';}}, {'form-url':`${SERVICE_ORIGIN}/form/ukazka`}));
  assert.deepEqual(writes,['form-url']);
  assert.equal(settingsFrom({'form-url':`${SERVICE_ORIGIN}/form/ukazka`})['inherit-style'],undefined);
  for (const value of [false, 'false', '0', '', 'yes', {}, '<script>']) {
    assert.equal(settingsFrom({'form-url':`${SERVICE_ORIGIN}/form/ukazka`, 'inherit-style':value})['inherit-style'], undefined);
  }
});

test('settings wait for propagated readback before writing sibling properties', async () => {
  let pending, reads = 0;
  const confirmed = [];
  await saveSettings({
    async setProp(name, value) {
      assert.equal(pending, undefined, 'previous property must be confirmed first');
      pending = {name, value};
      reads = 0;
    },
    async getProp(name) {
      assert.equal(name, pending.name);
      if (++reads < 3) return undefined;
      const value = pending.value;
      confirmed.push(name);
      pending = undefined;
      return value;
    },
  }, {'form-url':`${SERVICE_ORIGIN}/form/ukazka`,'form-title':'Delayed','inherit-style':'false'});
  assert.deepEqual(confirmed, PROPERTIES);
});

test('settings page fails closed outside editor and surfaces save success', async () => {
  const html = readFileSync(new URL('../src/settings.html',import.meta.url),'utf8');
  const dom = new JSDOM(html);
  const document = dom.window.document;
  await initSettings(document, {async getProp() {throw Error('no editor');}});
  assert.equal(document.querySelector('button').disabled, true);
  assert.ok([...document.querySelectorAll('form input')].every(input => input.disabled));
  assert.equal(document.querySelector('form').getAttribute('aria-busy'), 'false');
  assert.match(document.getElementById('status').textContent,/editoru Wix/);
  dom.window.close();
  const success = new JSDOM(html);
  const values={'form-url':`${SERVICE_ORIGIN}/form/ukazka`};
  await initSettings(success.window.document, {async getProp(name) {return values[name];},async setProp(name,value) {values[name]=value;}});
  success.window.document.querySelector('form').dispatchEvent(new success.window.Event('submit', {cancelable:true}));
  await tick();
  assert.match(success.window.document.getElementById('status').textContent,/Uloženo/);
  assert.equal(success.window.document.querySelector('button').disabled,false);
  success.window.close();
});


test('a failed helper can recover on a later widget without reloading checkout or duplicating requests', async () => {
  const {dom, element, document} = host(async () => 'Site');
  await tick();
  const frame = element.querySelector('iframe');
  const failed = document.scripts[0];
  failed.dispatchEvent(new dom.window.Event('error'));
  assert.equal(document.scripts.length, 0);
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(element.querySelector('p a').href, `${SERVICE_ORIGIN}/form/ukazka`);
  const second = document.createElement(TAG_NAME);
  second.setAttribute('form-url', `${SERVICE_ORIGIN}/form/another`);
  document.body.append(second);
  await tick();
  assert.equal(document.scripts.length, 1);
  assert.notEqual(document.scripts[0], failed);
  element.setAttribute('form-title', 'Updated');
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(document.scripts.length, 1);
  // A loaded canonical helper does not need reinserting even without its script tag.
  document.defaultView.__festappEmbedV1 = true;
  document.scripts[0].remove();
  element.setAttribute('form-title', 'Another update');
  assert.equal(document.scripts.length, 0);
  dom.window.close();
});

test('settings lock values during loading and saving, then unlock for correction after a failed write', async () => {
  const html = readFileSync(new URL('../src/settings.html',import.meta.url),'utf8');
  const dom = new JSDOM(html);
  const document = dom.window.document;
  const form = document.querySelector('form');
  const controls = [...form.querySelectorAll('input, button')];
  let finishRead, finishWrite, failWrite = false;
  const values = {'form-url':`${SERVICE_ORIGIN}/form/ukazka`};
  const api = {
    async getProp(name) {
      if (name === 'form-url' && !finishRead) await new Promise(resolve => {finishRead = resolve;});
      return values[name];
    },
    async setProp(name, value) {
      if (failWrite) throw Error('Write failed');
      if (name === 'form-url') await new Promise(resolve => {finishWrite = resolve;});
      values[name] = value;
    },
  };
  const initializing = initSettings(document, api);
  assert.ok(controls.every(control => control.matches(':disabled')));
  assert.equal(form.getAttribute('aria-busy'), 'true');
  finishRead(); await initializing;
  assert.ok(controls.every(control => !control.matches(':disabled')));
  form.dispatchEvent(new dom.window.Event('submit', {cancelable:true}));
  await tick();
  assert.ok(controls.every(control => control.matches(':disabled')));
  assert.equal(form.getAttribute('aria-busy'), 'true');
  finishWrite(); await tick();
  assert.match(document.getElementById('status').textContent, /Uloženo/);
  assert.equal(form.getAttribute('aria-busy'), 'false');
  assert.ok(controls.every(control => !control.matches(':disabled')));
  failWrite = true;
  form.dispatchEvent(new dom.window.Event('submit', {cancelable:true}));
  await tick();
  assert.match(document.getElementById('status').textContent, /Write failed/);
  assert.ok(controls.every(control => !control.matches(':disabled')));
  assert.equal(form.getAttribute('aria-busy'), 'false');
  dom.window.close();
});


test('settings leave stale appearance properties inert and expose no local control', async () => {
  const html=readFileSync(new URL('../src/settings.html',import.meta.url),'utf8');
  const dom=new JSDOM(html);
  const values={'form-url':`${SERVICE_ORIGIN}/form/ukazka`,'inherit-style':'false'};
  const writes=[];
  try {
    await initSettings(dom.window.document, {async getProp(name){return values[name];},async setProp(name,value){writes.push(name);values[name]=value;}});
    assert.equal(dom.window.document.getElementById('inherit-style'),null);
    dom.window.document.querySelector('form').dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
    await tick();
    assert.deepEqual(writes,PROPERTIES);
    assert.equal(values['inherit-style'],'false','existing stored data is never reinterpreted as authority');
    assert.match(dom.window.document.getElementById('status').textContent,/Uloženo/);
  } finally {dom.window.close();}
});

test('measurement defaults preserve old widgets and allow explicit website mode',async()=>{
 assert.equal(settingsFrom({'form-url':`${SERVICE_ORIGIN}/form/a`}).measurement,'unit');
 assert.equal(settingsFrom({'form-url':`${SERVICE_ORIGIN}/form/a`,measurement:'host'}).measurement,'host');
 const dom=new JSDOM('<body></body>');registerTicketElement(dom.window,async()=>'Site');
 try {
  const e=dom.window.document.createElement(TAG_NAME);e.setAttribute('form-url',`${SERVICE_ORIGIN}/form/a`);dom.window.document.body.append(e);await tick();
  const frame=e.querySelector('iframe');assert.equal(frame.hasAttribute('data-festapp-datalayer'),false);
  e.setAttribute('measurement','host');assert.equal(frame.hasAttribute('data-festapp-datalayer'),true);
  e.setAttribute('measurement','unit');assert.equal(frame.hasAttribute('data-festapp-datalayer'),false);
 } finally {dom.window.close();}
});
for(const existing of [true,false])test('settings default only new widgets to host: existing='+existing,async()=>{
 const dom=new JSDOM(readFileSync(new URL('../src/settings.html',import.meta.url),'utf8'));
 try {await initSettings(dom.window.document,{getProp:async name=>existing&&name==='form-url'?`${SERVICE_ORIGIN}/form/a`:''});
 assert.equal(dom.window.document.querySelector('[name="measurement"]').value,existing?'unit':'host');
 } finally {dom.window.close();}
});

// Wix host SDK/CMP is modeled here; actual native cookie reset was checked on
// the recorded public development site without publishing or placing orders.
const nativeExport=(version=1)=>({schemaVersion:1,serviceOrigin:SERVICE_ORIGIN,websiteOrigin:'https://wix-site.invalid',
 binding:{id:'11111111-1111-1111-1111-111111111111',version},providerConfig:{provider:'wix',organization:1,unit:2,consentRevision:'a'.repeat(32),
 origin:'https://wix-site.invalid',consentValidFrom:'2026-01-01T00:00:00.000Z',maxAgeSeconds:86400}});
test('Wix import stays off by default, validates envelope before writes and persists complete export',async()=>{
 const base={'form-url':`${SERVICE_ORIGIN}/form/a`};
 assert.equal(settingsFrom(base)['consent-enabled'],'off');
 const raw=JSON.stringify(nativeExport());
 const valid=settingsFrom({...base,'consent-export':raw,'consent-enabled':'on'});
 assert.equal(valid['consent-enabled'],'on');assert.deepEqual(JSON.parse(valid['consent-export']),nativeExport());
 for(const value of ['{',JSON.stringify({...nativeExport(),serviceOrigin:'https://foreign.example'})]) {
  let calls=0;await assert.rejects(saveSettings({setProp:()=>calls++},{...base,'consent-export':value,'consent-enabled':'on'}));assert.equal(calls,0);
 }
});
test('Wix element delegates managed import, preserves iframe and retires source on off/removal',async()=>{
 const dom=new JSDOM('',{url:'https://wix-site.invalid'});const win=dom.window;
 let source,connections=0,stops=0;
 win.FestappEmbed={connectMeasurementSource(value){source=value;connections++;return ()=>{stops++;source=null;};}};
 win.consentPolicyManager={getCurrentConsentPolicy:()=>({defaultPolicy:false,createdDate:new Date(),policy:{essential:true,functional:false,analytics:true,advertising:true,dataToThirdParty:true}})};
 registerTicketElement(win,async()=>'Site');
 const element=win.document.createElement(TAG_NAME);element.setAttribute('form-url',`${SERVICE_ORIGIN}/form/a`);
 element.setAttribute('consent-export',JSON.stringify(nativeExport()));element.setAttribute('consent-enabled','on');win.document.body.append(element);
 try {
  await tick();await tick();assert.equal(connections,1);assert.ok(source);
  const iframe=element.querySelector('iframe');assert.equal(element.querySelector('a').hasAttribute('data-festapp-consent-link'),true);
  const requested={organization:1,unit:2,processingRevision:'technical',consentRevision:'a'.repeat(32),requiredPurposes:['analytics','marketing'],binding:nativeExport().binding,websiteOrigin:win.location.origin};
  assert.equal(source.read(requested).analytics,true);
  element.setAttribute('form-title','Updated');await tick();assert.equal(connections,1);assert.equal(element.querySelector('iframe'),iframe);
  element.setAttribute('consent-export',JSON.stringify(nativeExport(2)));await tick();assert.equal(source.read(requested),null);
  element.setAttribute('consent-enabled','off');await tick();assert.equal(source,null);assert.ok(stops>=2);
  assert.equal(element.querySelector('a').rel,'noopener noreferrer');assert.equal(element.querySelector('iframe'),iframe);
  element.remove();await tick();
 }finally{win.close();}
});
test('Wix conflicting or foreign site imports fail closed without rewriting manual links',async()=>{
 const dom=new JSDOM('<a id="manual" target="_blank" rel="noopener noreferrer" href="https://vstupenky.online/form/a">Open</a>',{url:'https://wix-site.invalid'});const win=dom.window;let source;
 win.FestappEmbed={connectMeasurementSource(value){source=value;return ()=>{source=null;};}};
 registerTicketElement(win,async()=>'Site');
 try {
  for(const version of [1,2]) {const e=win.document.createElement(TAG_NAME);e.setAttribute('form-url',`${SERVICE_ORIGIN}/form/a`);e.setAttribute('consent-enabled','on');e.setAttribute('consent-export',JSON.stringify(nativeExport(version)));win.document.body.append(e);}
  await tick();await tick();assert.equal(source.read({}),null);assert.equal(win.document.querySelector('#manual').rel,'noopener noreferrer');
 }finally{win.close();}
});
