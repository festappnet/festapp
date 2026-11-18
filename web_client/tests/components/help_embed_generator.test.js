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
  const code=new JSDOM(form.querySelector('[data-embed-output] textarea').value);t.after(()=>code.window.close());
  const frame=code.window.document.querySelector('iframe');
  assert.equal(frame.src,'https://vstupenky.online/form/ples-2027?embed=1');
  assert.equal(frame.hasAttribute('data-festapp-embed'),true);
  assert.equal(frame.hasAttribute('data-festapp-datalayer'),true,'generated embeds explicitly select host transport');
  assert.equal(frame.getAttribute('data-festapp-style'),null);
  assert.equal(frame.getAttribute('allow'),'clipboard-write');
  assert.equal(frame.style.display,'block');
  assert.equal(frame.style.width,'100%');
  assert.equal(frame.hasAttribute('width'),false);
  assert.equal(frame.style.maxWidth,'100%');
  assert.equal(frame.style.colorScheme,'light dark','canvas must support the child before the deferred helper loads');
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
  const code=form.querySelector('[data-embed-output] textarea').value;
  assert.match(code,/https:\/\/example.test\/embed.js/);
  assert.match(code,/title="Order form"/);assert.match(code,/Open the form in a new tab/);
  assert.match(form.querySelector('[role=status]').textContent,/Your code is ready/);
  assert.doesNotMatch(code,/vstupenky.online|Objednávkový|Otevřít/);
  const mode=form.querySelector('[name=height-mode]');
  mode.value='fixed';mode.dispatchEvent(new form.ownerDocument.defaultView.Event('change'));
  mode.value='automatic';mode.dispatchEvent(new form.ownerDocument.defaultView.Event('change'));
});
test('generator leaves appearance to the saved form in both height modes',t=>{
  const {dom,form,field,submit}=fixture(t);
  const mode=form.querySelector('[name=height-mode]');
  assert.equal(form.querySelector('[name=inherit-style]'),null);
  submit('https://vstupenky.online/form/ples');
  assert.doesNotMatch(form.querySelector('[data-embed-output] textarea').value,/data-festapp-style/);
  mode.value='fixed';mode.dispatchEvent(new dom.window.Event('change'));
  submit('https://vstupenky.online/form/ples');
  assert.doesNotMatch(form.querySelector('[data-embed-output] textarea').value,/data-festapp-style/);
  assert.match(form.querySelector('[data-embed-output] textarea').value,/data-festapp-height="fixed"/);
});
test('copy action copies the current prepared code',async t=>{
  const {dom,form,submit}=fixture(t);let copied;Object.defineProperty(dom.window.navigator,'clipboard',{value:{writeText:async value=>{copied=value;}}});
  submit('https://vstupenky.online/form/ples');form.querySelector('[data-copy-embed]').click();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(copied,form.querySelector('[data-embed-output] textarea').value);assert.match(form.querySelector('[role=status]').textContent,/zkopírován/);
});

test('both generator guides distinguish organizer approval from saving a website',t=>{
 for(const english of [false,true]) {
  const {dom}=fixture(t,english);
  assert.match(dom.window.document.body.textContent,/dataLayer/);
  assert.doesNotMatch(dom.window.document.body.textContent,/data-festapp-datalayer/);
  assert.match(dom.window.document.body.textContent,english
    ? /After initial organizer approval, save the website address/
    : /Po prvním povolení pořadatele stačí uložit adresu webu/);
  assert.match(dom.window.document.body.textContent,english
    ? /run the organizer’s GTM in Festapp/
    : /spustíte GTM pořadatele ve Festappu/);
  assert.doesNotMatch(dom.window.document.body.textContent,/Doména webu musí být schválená|domain must be approved/);
 }
});

for(const english of [false,true])test('measurement option defaults to host and toggles independently of height: '+(english?'en':'cs'),async t=>{
  const {dom,form,submit}=fixture(t,english),win=dom.window;
  const option=form.querySelector('[name=host-datalayer]'),mode=form.querySelector('[name=height-mode]');
  const url=english?'https://example.test/form/my-event':'https://vstupenky.online/form/ples';
  assert.equal(option.type,'checkbox');assert.equal(option.checked,true);
  assert.match(option.closest('label').textContent,english?/Send events to your website’s dataLayer/:/Posílat události do dataLayer Vašeho webu/);
  for(const height of ['automatic','fixed']) {
    mode.value=height;mode.dispatchEvent(new win.Event('change'));
    submit(url);const host=form.querySelector('[data-embed-output] textarea').value;
    assert.match(host,/data-festapp-datalayer/);
    option.click();
    assert.equal(form.querySelector('[data-embed-output]').hidden,true,'changing the option invalidates the previous code');
    submit(url);const runtime=form.querySelector('[data-embed-output] textarea').value;
    assert.equal(runtime,host.replace(' data-festapp-datalayer',''));
    let copied;Object.defineProperty(win.navigator,'clipboard',{configurable:true,value:{writeText:async value=>{copied=value;}}});
    form.querySelector('[data-copy-embed]').click();await new Promise(resolve=>setImmediate(resolve));
    assert.equal(copied,runtime);
    option.click();submit(url);
    assert.equal(form.querySelector('[data-embed-output] textarea').value,host);
  }
});

test('HTML/Webnode imports one server export and escapes only generated owned links/script',t=>{
 const {form,submit}=fixture(t);
 const exported={schemaVersion:1,serviceOrigin:'https://vstupenky.online',websiteOrigin:'https://website.example',
 binding:{id:'11111111-1111-1111-1111-111111111111',version:1},providerConfig:{provider:'cookieconsent',organization:1,unit:2,
 consentRevision:'a'.repeat(32),origin:'https://website.example',revision:1,categories:{analytics:'</script><script>alert(1)</script>',marketing:'reklama'}}};
 form.querySelector('[name=consent-export]').value=JSON.stringify(exported);form.querySelector('[name=consent-enabled]').checked=true;
 submit('https://vstupenky.online/form/saved');
 const code=new JSDOM(form.querySelector('[data-embed-output] textarea').value);t.after(()=>code.window.close());
 assert.equal(code.window.document.scripts.length,1);
 assert.deepEqual(JSON.parse(code.window.document.scripts[0].getAttribute('data-festapp-consent')),exported);
 assert.equal(code.window.document.querySelector('a').hasAttribute('data-festapp-consent-link'),true);
 assert.equal(code.window.document.querySelector('a').hasAttribute('rel'),false);
 form.querySelector('[name=consent-enabled]').checked=false;submit('https://vstupenky.online/form/saved');
 assert.doesNotMatch(form.querySelector('[data-embed-output] textarea').value,/data-festapp-consent/);
});
test('HTML/Webnode invalid or foreign export blocks stale output and copy',t=>{
 const {form,submit}=fixture(t);submit('https://vstupenky.online/form/saved');
 form.querySelector('[name=consent-enabled]').checked=true;
 for(const raw of ['{','null',JSON.stringify({schemaVersion:2}),JSON.stringify({schemaVersion:1,serviceOrigin:'https://foreign.example'})]) {
  form.querySelector('[name=consent-export]').value=raw;submit('https://vstupenky.online/form/saved');
  assert.equal(form.querySelector('[data-embed-output]').hidden,true);
  assert.equal(form.querySelector('[name=consent-export]').getAttribute('aria-invalid'),'true');
 }
});

test('WordPress HTML examples match the complete default generator output',t=>{
 for(const english of [false,true]) {
  const {form,submit}=fixture(t,english);
  const origin=english?'https://example.test':'https://vstupenky.online';
  const slug=english?'YOUR-FORM':'VAS-FORMULAR';
  submit(`${origin}/form/${slug}`);
  const guide=new JSDOM(readFileSync(new URL('../../../automation/release/help/'+(english?'en/':'')+'wordpress.html',import.meta.url),'utf8'));
  t.after(()=>guide.window.close());
  const snippet=guide.window.document.querySelector('[data-code-example] code').textContent;
  assert.equal(snippet.replaceAll('https://vstupenky.online',origin),form.querySelector('[data-embed-output] textarea').value);
 }
});
