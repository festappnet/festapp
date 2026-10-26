import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {JSDOM,VirtualConsole} from 'jsdom';

for(const locale of ['cs','en']) test(`self-contained ${locale} preview binds the real generator after document creation`,async t=>{
 const root=new URL('../../../',import.meta.url);
 const run=spawnSync(process.execPath,[new URL('automation/release/preview_help.mjs',root).pathname,...(locale==='en'?['--en']:[])],{encoding:'utf8'});
 assert.equal(run.status,0,run.stderr);
 const file=new URL(`.private/help-preview/${locale}/napoveda/${locale==='en'?'embed':'vlozeni-na-web'}/index.html`,root);
 const errors=[];const console=new VirtualConsole();console.on('jsdomError',error=>{if(error.type==='unhandled-exception')errors.push(error.message);});
 const dom=new JSDOM(readFileSync(file,'utf8'),{url:file.href,runScripts:'dangerously',virtualConsole:console,beforeParse(window){ window.matchMedia=query=>({matches:false,media:query,addEventListener(){},removeEventListener(){}}); }});
 t.after(()=>dom.window.close());
 await new Promise(resolve=>dom.window.addEventListener('load',resolve,{once:true}));
 const form=dom.window.document.querySelector('[data-embed-generator]');
 const input=form.querySelector('input[type=url]');
 input.value=new dom.window.URL(input.placeholder).origin+'/form/example';
 form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));
 assert.deepEqual(errors,[]);
 assert.equal(form.querySelector('[data-embed-output]').hidden,false);
 const code=form.querySelector('textarea').value;
 assert.match(code,/<iframe data-festapp-embed/);
 assert.ok(code.includes(`/form/example?embed=1`));
 assert.ok(code.includes(locale==='en'?'Order form':'Objednávkový formulář'));
});
