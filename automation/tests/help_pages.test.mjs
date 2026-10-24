import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'../..');
test('public guides render crawlable linked documents, code generator and exact plugin download',t=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-help-'));t.after(()=>fs.rmSync(temporary,{recursive:true,force:true}));
 const target=path.join(temporary,'napoveda');const config=path.join(temporary,'project.conf');
 fs.writeFileSync(config,'WEB_LINK=https://vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\n');
 const render=()=>spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',target],{encoding:'utf8'});
 let run=render();assert.equal(run.status,0,run.stderr);
 const pages=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/pages.json')));
 const coreTopics=['getting-started','form','ticket-pricing','seating','ticket-design','payments','orders','check-in'];
 for(const id of coreTopics) assert.ok(pages.some(page=>page.id===id),`Missing core organizer guide: ${id}`);
 assert.deepEqual([...new Set(pages.filter(page=>page.category).map(page=>page.category))],['integrations','basics','tickets','orders','check-in','troubleshooting']);
 for(const page of pages){
  const html=fs.readFileSync(path.join(target,page.slug,'index.html'),'utf8');
  assert.equal((html.match(/<h1>/g)||[]).length,1);assert.match(html,/<html lang="cs">/);assert.ok(html.includes(page.description));
  assert.ok(html.includes(`rel="canonical" href="https://vstupenky.online/napoveda/${page.slug?page.slug+'/':''}"`));
  assert.match(html,/application\/ld\+json/);assert.doesNotMatch(html,/\{\{|<iframe/);
  assert.match(html,/<header class="site-header/);assert.match(html,/<footer class="site-footer wrap"/);
  assert.doesNotMatch(html,/class="help-header|class="help-footer/);
  if(coreTopics.includes(page.id)) assert.match(html,/<figure class="guide-screenshot">/,`Missing actual product screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/napoveda\/[^"#]*)(?:#[^"]*)?"/g)) {
   const local=match[1].slice('/napoveda/'.length);const file=local.endsWith('/')||!local?path.join(target,local,'index.html'):path.join(target,local);
   assert.ok(fs.existsSync(file),`Missing guide/asset ${match[1]}`);
  }
 }
 const embed=fs.readFileSync(path.join(target,'vlozeni-na-web/index.html'),'utf8');assert.match(embed,/data-embed-generator/);
 const wordpress=fs.readFileSync(path.join(target,'wordpress/index.html'),'utf8');assert.match(wordpress,/Vlastní HTML/);assert.match(wordpress,/vstupenky_online url=/);
 const zip=fs.readdirSync(path.join(target,'assets')).find(name=>name.endsWith('.zip'));const packageZip=fs.readFileSync(path.join(root,'integrations/wordpress/dist',zip));
 assert.equal(createHash('sha256').update(fs.readFileSync(path.join(target,'assets',zip))).digest('hex'),createHash('sha256').update(packageZip).digest('hex'));
 const before=fs.readFileSync(path.join(target,'index.html'));run=render();assert.equal(run.status,0,run.stderr);assert.deepEqual(fs.readFileSync(path.join(target,'index.html')),before);
 const english=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',target,'--locale','en','--preview'],{encoding:'utf8'});
 assert.equal(english.status,0,english.stderr);
 const englishPages=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/pages.en.json')));
 assert.deepEqual(englishPages.map(p=>p.id),pages.map(p=>p.id),'both locales address the same topics');
 for(const page of englishPages){
  const html=fs.readFileSync(path.join(target,page.slug,'index.html'),'utf8');
  assert.match(html,/<html lang="en">/);assert.match(html,/noindex,nofollow/);
  assert.doesNotMatch(html,/\{\{|Nápověda|Přihlásit se|cs-webnode-/,'English preview has no Czech chrome or screenshot fallback');
  if(coreTopics.includes(page.id)) assert.match(html,/<figure class="guide-screenshot">/,`Missing localized screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/napoveda\/[^"#]*)(?:#[^"]*)?"/g)){
   const local=match[1].slice('/napoveda/'.length);assert.ok(fs.existsSync(local.endsWith('/')||!local?path.join(target,local,'index.html'):path.join(target,local)),match[1]);
  }
 }
 const refused=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',target,'--locale','en'],{encoding:'utf8'});
 assert.notEqual(refused.status,0,'English publication requires completed localized evidence');
 assert.ok(fs.existsSync(path.join(target,'index.html')),'invalid invocation does not delete the preview');
 fs.writeFileSync(config,'WEB_LINK=https://other.invalid\nWEB_ORGANIZER_LANDING_ENABLED=false\n');run=render();assert.equal(run.status,0,run.stderr);assert.equal(fs.existsSync(target),false,'tenant switch removes Czech help and download');
});
