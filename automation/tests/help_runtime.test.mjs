import test from 'node:test';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

test('built help owns its complete runtime outside the installed app cache', t=>{
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'help-runtime-'));t.after(()=>fs.rmSync(temp,{recursive:true,force:true}));
 const dist=path.join(temp,'dist'),out=path.join(temp,'napoveda');
 for(const dir of ['.vite','web-assets','assets/translations']) fs.mkdirSync(path.join(dist,dir),{recursive:true});
 fs.writeFileSync(path.join(temp,'project.conf'),'WEB_LINK=https://vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\n');
 fs.writeFileSync(path.join(dist,'.vite/manifest.json'),JSON.stringify({'src/marketing/help.js':{file:'web-assets/help.js'}}));
 fs.writeFileSync(path.join(dist,'index.html'),'<link rel="stylesheet" href="/web-assets/theme.css">');
 fs.writeFileSync(path.join(dist,'web-assets/help.js'),'import "./account.js";');
 fs.writeFileSync(path.join(dist,'web-assets/account.js'),'fetch("/assets/translations/cs.json");import("/web-assets/login.js");const deps=["web-assets/login.js"];');
 fs.writeFileSync(path.join(dist,'web-assets/login.js'),'export const login=true;');
 fs.writeFileSync(path.join(dist,'web-assets/theme.css'),'@font-face{src:url(/web-assets/font.ttf)}');
 fs.writeFileSync(path.join(dist,'web-assets/font.ttf'),Buffer.from([0,1,2,255]));
 fs.writeFileSync(path.join(dist,'assets/translations/cs.json'),'{"hello":"Ahoj"}');
 const run=spawnSync(process.execPath,['automation/release/render_help_pages.mjs','--config',path.join(temp,'project.conf'),'--output',out,'--built-index',path.join(dist,'index.html')],{encoding:'utf8'});
 assert.equal(run.status,0,run.stderr);
 const html=fs.readFileSync(path.join(out,'index.html'),'utf8');
 assert.match(html,/src="\/napoveda\/assets\/runtime\/help.js"/);
 assert.match(html,/href="\/napoveda\/assets\/runtime\/theme.css"/);
 // Exercise the actual generated pre-paint scripts, without loading the module runtime.
 const head = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
 const body = html.match(/<body[^>]*><script>([\s\S]*?)<\/script>/)?.[1];
 assert.ok(head && body, 'Theme must resolve synchronously before page content');
 assert.ok(html.indexOf(`<script>${head}`) < html.indexOf('<link'), 'Preference must resolve before stylesheets');
 for (const [saved, systemDark, expected] of [['light',true,'light'],['dark',false,'dark'],[null,true,'dark'],[null,false,'light'],['invalid',false,'light'],['blocked',true,'dark']]) {
  const classes = new Set();
  const document = {documentElement:{style:{}},body:{style:{},dataset:{},classList:{toggle(name,on){if(on) classes.add(name);else classes.delete(name);}}}};
  const context = vm.createContext({document,localStorage:{getItem(){if(saved==='blocked') throw Error('Storage blocked');return saved;}},matchMedia:()=>({matches:systemDark})});
  vm.runInContext(head,context);vm.runInContext(body,context);
  assert.equal(document.documentElement.style.colorScheme,expected);
  assert.equal(document.body.style.colorScheme,expected);
  assert.equal(classes.has('dark-mode'),expected==='dark');
  assert.equal(document.body.dataset.publicTheme,'initialized', 'OS-only CSS fallback must be disabled before paint');
 }
 const runtime=path.join(out,'assets/runtime');
 assert.equal(fs.readFileSync(path.join(runtime,'help.js'),'utf8'),'import "./account.js";');
 assert.equal(fs.readFileSync(path.join(runtime,'account.js'),'utf8'),'fetch("/napoveda/assets/translations/cs.json");import("/napoveda/assets/runtime/login.js");const deps=["napoveda/assets/runtime/login.js"];');
 assert.match(fs.readFileSync(path.join(runtime,'theme.css'),'utf8'),/url\(\/napoveda\/assets\/runtime\/font.ttf\)/);
 assert.deepEqual(fs.readFileSync(path.join(runtime,'font.ttf')),Buffer.from([0,1,2,255]));
 assert.equal(fs.readFileSync(path.join(out,'assets/translations/cs.json'),'utf8'),'{"hello":"Ahoj"}');
});
