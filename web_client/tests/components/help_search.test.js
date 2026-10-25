import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
const base=new URL('../../../automation/release/help/',import.meta.url);
const labels=JSON.parse(readFileSync(new URL('ui.json',base)));
const engine=readFileSync(new URL('search_engine.js',base),'utf8');
const script=readFileSync(new URL('search_ui.js',base),'utf8');
function fixture(t,url='https://example.org/napoveda/',locale='cs'){
 const dom=new JSDOM(`<meta name="robots" content="index,follow"><button data-search-open hidden><kbd data-search-shortcut></kbd>Search</button><dialog id="help-search-dialog"><button data-search-close>Close</button><form data-help-search><input name="q"><select name="category"><option value="">All</option><option value="orders">Orders</option><option value="tickets">Tickets</option></select><button type="button" data-search-clear hidden>Clear</button></form><div data-search-intro>Introduction</div><section data-search-results><p role="status"></p><ol></ol></section></dialog><a data-help-base href="file:///tmp/help/napoveda/index.html" hidden></a><div data-help-browse>Browse</div>`,{url,runScripts:'outside-only'});
 t.after(()=>dom.window.close());const w=dom.window;
 w.FestappHelpSearchData={locale,ui:labels[locale],helpRoot:'/napoveda/',supportUrl:'https://example.org/support/',entries:[{title:'Objednávky a doručení',description:'Přehled',category:'orders',categoryLabel:'Objednávky',url:'/napoveda/objednavky/',aliases:['nepřišly vstupenky'],sections:[{anchor:'doruceni',heading:'Doručení',text:'Pokud nepřišly vstupenky, zkontrolujte <img src=x onerror=alert(1)> a e-mail.'}]}]};
 w.HTMLDialogElement.prototype.showModal=function(){this.open=true;};
 w.HTMLDialogElement.prototype.close=function(){this.open=false;this.dispatchEvent(new w.Event('close'));};
 w.eval(engine);w.eval(script);w.document.dispatchEvent(new w.Event('DOMContentLoaded'));
 const trigger=w.document.querySelector('[data-search-open]');trigger.focus();trigger.click();
 const form=w.document.querySelector('form');const input=form.querySelector('input');
 const submit=q=>{input.value=q;form.dispatchEvent(new w.Event('submit',{cancelable:true}));};
 const key=(target,key,extra={})=>target.dispatchEvent(new w.KeyboardEvent('keydown',{key,bubbles:true,cancelable:true,...extra}));
 return {w,d:w.document,form,input,submit,key};
}
test('global dialog safely renders section results without replacing article or URL',t=>{
 const {w,d,input,submit,key}=fixture(t);submit('neprisly vstupenky');
 assert.equal(d.querySelector('dialog').open,true);
 assert.equal(d.querySelector('[data-help-browse]').hidden,false);
 assert.equal(d.querySelector('[role=status]').textContent,'1 návod');
 assert.equal(d.querySelector('ol a').getAttribute('href'),'/napoveda/objednavky/#doruceni');
 assert.equal(d.querySelector('.help-search-hit-section').textContent,'Doručení');
 assert.ok(d.querySelectorAll('mark').length>0);
 assert.equal(d.querySelectorAll('img,iframe').length,0);
 assert.equal(d.querySelector('meta').content,'index,follow');assert.equal(w.location.search,'');
 assert.equal(d.activeElement,d.querySelector('ol a'));
 key(input,'Escape');assert.equal(d.querySelector('dialog').open,false);
 assert.equal(d.activeElement,d.querySelector('[data-search-open]'));assert.equal(d.body.style.overflow,'');
});
test('filters, clear, empty feedback, keyboard results, focus wrapping and shortcut',t=>{
 const {d,form,input,submit,key,w}=fixture(t);const category=form.querySelector('select');
 category.value='tickets';category.dispatchEvent(new w.Event('change'));assert.equal(d.querySelector('[role=status]').textContent,labels.cs.searchEmpty);
 category.value='orders';category.dispatchEvent(new w.Event('change'));assert.equal(d.querySelector('[role=status]').textContent,'1 návod');
 input.focus();key(input,'ArrowDown');assert.equal(d.activeElement,d.querySelector('ol a'));
 key(d.activeElement,'Tab');assert.equal(d.activeElement,d.querySelector('[data-search-close]'));
 key(d.activeElement,'Tab',{shiftKey:true});assert.equal(d.activeElement,d.querySelector('ol a'));
 submit('zzzzz');assert.equal(d.querySelector('[role=status]').textContent,labels.cs.searchEmpty);
 submit('<script>alert(1)</script>');assert.equal(d.querySelectorAll('script').length,0);
 d.querySelector('[data-search-clear]').click();assert.equal(input.value,'');assert.equal(category.value,'');assert.equal(d.querySelector('[data-search-intro]').hidden,false);assert.equal(d.activeElement,input);
 d.querySelector('[data-search-close]').click();key(d,'k',{ctrlKey:true});assert.equal(d.querySelector('dialog').open,true);assert.equal(d.activeElement,input);
});
test('static previews use file section links without local history rewrite',t=>{
 const {w,d,submit}=fixture(t,'file:///tmp/help/napoveda/index.html');submit('neprisly vstupenky');
 assert.equal(d.querySelector('ol a').href,'file:///tmp/help/napoveda/objednavky/index.html#doruceni');assert.equal(w.location.search,'');
});
test('incoming search links open the dialog and English labels use runtime locale',t=>{
 const {d,input}=fixture(t,'https://example.org/napoveda/?q=vstupenky&category=orders','en');
 assert.equal(input.value,'vstupenky');assert.equal(d.querySelector('dialog').open,true);assert.equal(d.querySelector('[role=status]').textContent,'1 guide');
});
