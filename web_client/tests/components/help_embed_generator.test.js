import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
const markup = readFileSync(new URL('../../../automation/release/help/embed-generator.html',import.meta.url),'utf8');
const script = readFileSync(new URL('../../../automation/release/help/help.js',import.meta.url),'utf8');
function fixture(t, english = false) {
  const content = english ? readFileSync(new URL('../../../automation/release/help/en/embed-generator.html',import.meta.url),'utf8').replaceAll('{{FORM_ORIGIN}}','https://example.test') : markup;
  const dom = new JSDOM(content,{url:'https://vstupenky.online/napoveda/vlozeni-na-web/',runScripts:'outside-only'});
  t.after(()=>dom.window.close()); dom.window.document.documentElement.lang = english ? 'en' : 'cs'; dom.window.eval(script);
  const form = dom.window.document.querySelector('form');
  const field = form.querySelector('input[type=url]');
  const submit = value => {field.value=value; form.dispatchEvent(new dom.window.Event('submit',{cancelable:true}));};
  return {dom,form,field,submit};
}
test('public generator produces isolated service code without loading checkout', t => {
  const {dom,form,submit}=fixture(t);submit('https://vstupenky.online/form/ples-2027');
  assert.equal(form.querySelector('[data-embed-output]').hidden,false);
  assert.equal(dom.window.document.querySelectorAll('iframe').length,0);
  const code=new JSDOM(form.querySelector('textarea').value);t.after(()=>code.window.close());
  const frame=code.window.document.querySelector('iframe');
  assert.equal(frame.src,'https://vstupenky.online/form/ples-2027?embed=1');
  assert.equal(frame.hasAttribute('data-festapp-embed'),true);
  assert.equal(frame.parentElement.hasAttribute('data-festapp-embed-host'),true);
  assert.equal(code.window.document.querySelector('script').src,'https://vstupenky.online/embed.js');
  assert.equal(code.window.document.querySelector('a').rel,'noopener noreferrer');
});
test('English generator uses its configured service origin and localized results',t=>{
  const {form,submit}=fixture(t,true);
  submit('https://vstupenky.online/form/wrong-tenant');
  assert.match(form.querySelector('[data-url-error]').textContent,/Paste a saved public form link/);
  assert.equal(form.querySelector('[data-embed-output]').hidden,true);
  submit('https://example.test/form/my-event');
  const code=form.querySelector('textarea').value;
  assert.match(code,/https:\/\/example.test\/embed.js/);
  assert.match(code,/title="Order form"/);assert.match(code,/Open the form in a new tab/);
  assert.match(form.querySelector('[role=status]').textContent,/Your code is ready/);
  assert.doesNotMatch(code,/vstupenky.online|Objednávkový|Otevřít/);
});
test('generator rejects other tenants, credentials, query/fragment and encoded injection', t => {
  const {form,submit}=fixture(t);
  for(const value of ['https://evil.invalid/form/a','https://vstupenky.online.evil.invalid/form/a','https://x@vstupenky.online/form/a','https://vstupenky.online/form/a?','https://vstupenky.online/form/a#','https://vstupenky.online/form/a?preview=true','https://vstupenky.online/form/a#token','https://vstupenky.online/form/a%2Fb','https://vstupenky.online/form/%22%3E%3Cscript%3E','javascript:alert(1)','https://vstupenky.online/login']) {
    submit(value);assert.equal(form.querySelector('[data-embed-output]').hidden,true,value);
    assert.equal(form.querySelector('[name=form-url]').getAttribute('aria-invalid'),'true');
  }
});
test('changing settings invalidates stale output and fixed height does not load the helper', t => {
  const {dom,form,field,submit}=fixture(t);const inherit=form.querySelector('[name=inherit-style]');inherit.checked=true;
  submit('https://vstupenky.online/form/ples');assert.match(form.querySelector('textarea').value,/data-festapp-style="inherit"/);
  field.dispatchEvent(new dom.window.Event('input'));assert.equal(form.querySelector('[data-embed-output]').hidden,true);
  const mode=form.querySelector('select');mode.value='fixed';mode.dispatchEvent(new dom.window.Event('change'));
  assert.equal(inherit.disabled,true);submit('https://vstupenky.online/form/ples');
  assert.doesNotMatch(form.querySelector('textarea').value,/<script|data-festapp-embed|data-festapp-style/);
});
test('copy action copies the current prepared code',async t=>{
  const {dom,form,submit}=fixture(t);let copied;Object.defineProperty(dom.window.navigator,'clipboard',{value:{writeText:async value=>{copied=value;}}});
  submit('https://vstupenky.online/form/ples');form.querySelector('[data-copy-embed]').click();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(copied,form.querySelector('textarea').value);assert.match(form.querySelector('[role=status]').textContent,/zkopírován/);
});
