import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM,VirtualConsole} from 'jsdom';
import {initHelpNavigation} from '../../src/marketing/help_navigation.js';
const html = (title, content = '', runtime = 'current.js') => `<!doctype html><html lang="cs"><head><title>${title}</title><meta name="description" content="${title}"><link rel="canonical" href="https://vstupenky.online/napoveda/${title}/"><link href="/napoveda/assets/help.123.css" rel="stylesheet"></head><body><user-header>Account</user-header><div id="help-search-dialog">Search</div><div class="help-layout"><nav><a href="/napoveda/objednavky/">Orders</a><a href="/napoveda/vlozeni-na-web/">Embed</a></nav><main><h1>${title}</h1>${content}</main></div><script data-help-runtime src="/napoveda/assets/runtime/${runtime}"></script></body></html>`;
const response = text => ({ok:true,headers:new Headers({'content-type':'text/html'}),text:async()=>text});
function fixture(t, fetch) {
 const dom=new JSDOM(html('Home'),{url:'https://vstupenky.online/napoveda/',runScripts:'outside-only',virtualConsole:new VirtualConsole()});
 t.after(()=>dom.window.close());dom.window.fetch=fetch;dom.window.scrollTo=()=>{};
 initHelpNavigation(dom.window);return dom.window;
}
const done = win => new Promise(resolve=>win.document.addEventListener('help:navigated',resolve,{once:true}));
const click = (win,path) => win.document.querySelector(`a[href="${path}"]`).dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true,button:0}));

test('guide navigation keeps the account and search nodes, updates URL/SEO/focus and supports back/forward',async t=>{
 let calls=0;const win=fixture(t,async path=>{calls++;return response(html(path.includes('objednavky')?'Orders':'Home'));});
 const header=win.document.querySelector('user-header'),search=win.document.querySelector('#help-search-dialog');
 let changed=done(win);assert.equal(click(win,'/napoveda/objednavky/'),false);await changed;
 assert.equal(win.document.querySelector('user-header'),header);assert.equal(win.document.querySelector('#help-search-dialog'),search);
 assert.equal(win.location.pathname,'/napoveda/objednavky/');assert.equal(win.document.title,'Orders');
 assert.equal(win.document.querySelector('meta[name=description]').content,'Orders');assert.equal(win.document.activeElement,win.document.querySelector('h1'));
 changed=done(win);win.history.back();await changed;assert.equal(win.location.pathname,'/napoveda/');assert.equal(win.document.title,'Home');
 changed=done(win);win.history.forward();await changed;assert.equal(win.document.title,'Orders');assert.equal(calls,2,'forward reuses the verified document');
});

test('pending/rapid navigation retains visible content and only the latest destination wins',async t=>{
 const complete=new Map();const win=fixture(t,path=>new Promise(resolve=>complete.set(path,resolve)));
 const previous=win.document.querySelector('.help-layout');click(win,'/napoveda/objednavky/');click(win,'/napoveda/vlozeni-na-web/');
 assert.equal(win.document.querySelector('.help-layout'),previous);assert.equal(previous.getAttribute('aria-busy'),'true');
 let changed=done(win);complete.get('/napoveda/vlozeni-na-web/')(response(html('Embed')));await changed;
 complete.get('/napoveda/objednavky/')(response(html('Orders')));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(win.document.title,'Embed');assert.equal(win.location.pathname,'/napoveda/vlozeni-na-web/');
});

test('modified clicks, new tabs, downloads, anchors and external links retain normal browser behavior',t=>{
 let calls=0;const win=fixture(t,()=>{calls++;throw Error('Unexpected fetch');});
 const a=win.document.querySelector('a');
 for(const attrs of [{href:'/napoveda/#topic'},{href:'/events'},{href:'https://other.test/napoveda/'},{href:'/napoveda/objednavky/',target:'_blank'},{href:'/napoveda/objednavky/',download:'file'}]){
  a.removeAttribute('target');a.removeAttribute('download');for(const[key,value]of Object.entries(attrs))a.setAttribute(key,value);
  assert.equal(a.dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true,button:0})),true);
 }
 a.removeAttribute('download');a.href='/napoveda/objednavky/';assert.equal(a.dispatchEvent(new win.MouseEvent('click',{bubbles:true,cancelable:true,ctrlKey:true,button:0})),true);
 assert.equal(calls,0);
});

test('generator binds on a newly inserted guide without a page reload or duplicate handlers',async t=>{
 const content=readFileSync(new URL('../../../automation/release/help/embed-generator.html',import.meta.url),'utf8');
 const generator=readFileSync(new URL('../../../automation/release/help/help.js',import.meta.url),'utf8');
 const win=fixture(t,async()=>response(html('Embed',content)));
 win.eval(generator);const changed=done(win);click(win,'/napoveda/vlozeni-na-web/');await changed;
 const form=win.document.querySelector('[data-embed-generator]');form.querySelector('input[type=url]').value='https://vstupenky.online/form/example';
 form.dispatchEvent(new win.Event('submit',{bubbles:true,cancelable:true}));
 assert.equal(form.querySelector('[data-embed-output]').hidden,false);assert.match(form.querySelector('textarea').value,/iframe/);
});

test('back and forward restore the reading position of each guide',async t=>{
 const win=fixture(t,async path=>response(html(path.includes('objednavky')?'Orders':'Home')));
 let y=180;Object.defineProperty(win,'scrollY',{get:()=>y});win.scrollTo=({top})=>{y=top;};
 let changed=done(win);click(win,'/napoveda/objednavky/');await changed;y=640;
 changed=done(win);win.history.back();await changed;assert.equal(y,180);
 changed=done(win);win.history.forward();await changed;assert.equal(y,640);
});

test('a changed release uses normal navigation instead of mixing its runtime with the open page',async t=>{
 const dom=new JSDOM(html('Home'),{url:'https://vstupenky.online/napoveda/',virtualConsole:new VirtualConsole()});t.after(()=>dom.window.close());
 const win=dom.window;let destination;
 win.fetch=async()=>response(html('New release','','next.js'));win.scrollTo=()=>{};
 const wrapped=new Proxy(win,{get(target,key){if(key==='location')return {origin:win.location.origin,pathname:win.location.pathname,search:'',assign:url=>{destination=url;}};return Reflect.get(target,key,target);}});
 initHelpNavigation(wrapped);click(win,'/napoveda/objednavky/');await new Promise(resolve=>setImmediate(resolve));
 assert.equal(destination,'https://vstupenky.online/napoveda/objednavky/');assert.equal(win.document.title,'Home');
});
