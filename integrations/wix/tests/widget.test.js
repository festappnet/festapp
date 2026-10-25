import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {formUrl, settingsFrom, TAG_NAME, SERVICE_ORIGIN} from '../src/config.js';
import {registerTicketElement} from '../src/element.js';
import {initSettings, saveSettings} from '../src/settings_controller.js';

const tick = () => new Promise(resolve => setImmediate(resolve));
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
    assert.equal(document.scripts.length, 0);
    assert.equal(element.querySelector('a').href, `${SERVICE_ORIGIN}/napoveda/vlozeni-na-web/`);
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
  element.setAttribute('form-title', '<script>not html</script>');
  element.setAttribute('inherit-style', 'false');
  assert.equal(element.querySelector('iframe'), frame);
  assert.equal(frame.title, '<script>not html</script>');
  assert.equal(frame.hasAttribute('data-festapp-style'), false);
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
  assert.deepEqual(calls.map(call=>call.slice(0,2)), [['set','form-url'],['get','form-url'],['set','form-title'],['get','form-title'],['set','inherit-style'],['get','inherit-style']]);
  const writes=[];
  await assert.rejects(saveSettings({async setProp(name) {writes.push(name);},async getProp() {return 'unexpected';}}, {'form-url':`${SERVICE_ORIGIN}/form/ukazka`}));
  assert.deepEqual(writes,['form-url']);
  assert.equal(settingsFrom({'form-url':`${SERVICE_ORIGIN}/form/ukazka`})['inherit-style'],'true');
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
  assert.deepEqual(confirmed, ['form-url', 'form-title', 'inherit-style']);
});

test('settings page fails closed outside editor and surfaces save success', async () => {
  const html = readFileSync(new URL('../src/settings.html',import.meta.url),'utf8');
  const dom = new JSDOM(html);
  const document = dom.window.document;
  await initSettings(document, {async getProp() {throw Error('no editor');}});
  assert.equal(document.querySelector('button').disabled, true);
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
