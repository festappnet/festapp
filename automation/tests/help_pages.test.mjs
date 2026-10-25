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
 for(const id of [...coreTopics,'event-settings','bank-accounts','fio-token']) assert.ok(pages.some(page=>page.id===id),`Missing core organizer guide: ${id}`);
 assert.deepEqual([...new Set(pages.filter(page=>page.category).map(page=>page.category))],['basics','administration','tickets','banking','integrations','orders','check-in','troubleshooting']);
 const categories=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/categories.json'))).map(c=>({...c.cs,id:'category.'+c.id}));
 for(const page of [...pages,...categories]){
  const html=fs.readFileSync(path.join(target,page.slug,'index.html'),'utf8');
  assert.equal((html.match(/<h1>/g)||[]).length,1);assert.match(html,/<html lang="cs">/);assert.ok(html.includes(page.description));
  assert.ok(html.includes(`rel="canonical" href="https://vstupenky.online/napoveda/${page.slug?page.slug+'/':''}"`));
  assert.match(html,/data-help-search/);assert.match(html,/assets\/search\.[a-f0-9]+\.js/);assert.match(html,/BreadcrumbList/);if(page.id.startsWith('category.'))assert.match(html,/ItemList/);
  assert.match(html,/application\/ld\+json/);assert.doesNotMatch(html,/\{\{|<iframe/);
  assert.match(html,/<header class="site-header/);assert.match(html,/<footer class="site-footer wrap"/);
  assert.doesNotMatch(html,/class="help-header|class="help-footer/);
  if(coreTopics.includes(page.id)) assert.match(html,/<figure class="guide-screenshot(?: guide-screenshot-mobile)?">/,`Missing actual product screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/napoveda\/[^"#]*)(?:#[^"]*)?"/g)) {
   const local=match[1].slice('/napoveda/'.length);const file=local.endsWith('/')||!local?path.join(target,local,'index.html'):path.join(target,local);
   assert.ok(fs.existsSync(file),`Missing guide/asset ${match[1]}`);
  }
 }
 const home=fs.readFileSync(path.join(target,'index.html'),'utf8');
 assert.ok(home.indexOf('href="/napoveda/zaciname-s-akci/"')<home.indexOf('href="/napoveda/integrace/"'));
 const bank=fs.readFileSync(path.join(target,'fio-api-token/index.html'),'utf8');
 assert.match(bank,/https:\/\/www\.youtube\.com\/watch\?v=px9MCABSQbI/);
 assert.match(bank,/data-help-workflow="organization"/);
 const wizard=fs.readFileSync(path.join(target,'zaciname/index.html'),'utf8');
 assert.match(wizard,/data-help-workflow="wizard"/);
 const existing=fs.readFileSync(path.join(target,'planek-salu/index.html'),'utf8');
 assert.match(existing,/data-help-workflow="administration"/);
 assert.doesNotMatch(existing,/cs-seating-saved|cs-seating-templates/,'wizard-only captures do not illustrate administration');
 const form=fs.readFileSync(path.join(target,'prodejni-formular/index.html'),'utf8');
 assert.ok(form.indexOf('class="help-step-action"')<form.indexOf('<h2 id="pole">'),'app link belongs to the opening step');
 assert.match(form,/href="\/login\?redirect=%2Fhelp-action%2Fforms" target="_blank"/);
 assert.doesNotMatch(form,/help-app-action/);assert.match(form,/guide-screenshot-mobile/);
 const scanner=fs.readFileSync(path.join(target,'odbaveni/index.html'),'utf8');
 assert.match(scanner,/href="\/login\?redirect=%2Fhelp-action%2Fscanner-settings" target="_blank"/);
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
  if(coreTopics.includes(page.id)) assert.match(html,/<figure class="guide-screenshot(?: guide-screenshot-mobile)?">/,`Missing localized screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/napoveda\/[^"#]*)(?:#[^"]*)?"/g)){
   const local=match[1].slice('/napoveda/'.length);assert.ok(fs.existsSync(local.endsWith('/')||!local?path.join(target,local,'index.html'):path.join(target,local)),match[1]);
  }
 }
 const refused=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',target,'--locale','en'],{encoding:'utf8'});
 assert.notEqual(refused.status,0,'English publication requires completed localized evidence');
 assert.ok(fs.existsSync(path.join(target,'index.html')),'invalid invocation does not delete the preview');
 fs.writeFileSync(config,'WEB_LINK=https://other.invalid\nWEB_ORGANIZER_LANDING_ENABLED=false\n');run=render();assert.equal(run.status,0,run.stderr);assert.equal(fs.existsSync(target),false,'tenant switch removes Czech help and download');
});

test('phone scanner guides use only mobile webclient captures in both locales',()=>{
 const directory=path.join(root,'automation/release/help');
 const media=new Map(JSON.parse(fs.readFileSync(path.join(directory,'media.json'))).map(item=>[item.id,item]));
 for(const [locale,file] of [['cs','odbaveni.html'],['en','en/check-in.html']]){
  const html=fs.readFileSync(path.join(directory,file),'utf8');
  const figures=[...html.matchAll(/\{\{MEDIA:([^}]+)\}\}/g)];
  assert.ok(figures.length>=2,'include verified mobile webclient controls and result');
  assert.match(html,/\{\{APP_LINK:scanner-settings\}\}/,'settings instruction must open the matching help intent');
  for(const state of ['invalid-access','not-found','settings','field-options','advanced','preview']) {
   assert.ok(figures.some(([,id])=>id===`${locale}/scanner-advanced/${state}`),`Missing actual ${locale} scanner walkthrough: ${state}`);
  }
  for(const [,id] of figures){
   const item=media.get(id);assert.ok(item,`Missing capture ${id}`);
   assert.equal(item.locale,locale);assert.equal(item.device,'mobile');
   assert.equal(item.platform,'web-client','the guide must show the mobile webclient, never Flutter');
   assert.equal(item.physicalDevice,false,'mobile viewport capture does not certify physical phone hardware');
  }
 }
});
