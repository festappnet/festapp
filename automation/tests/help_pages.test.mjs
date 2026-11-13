import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root=path.resolve(import.meta.dirname,'../..');
test('compiled help owns fresh bundle sitemap and synchronizes unchanged documents',t=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-built-help-'));t.after(()=>fs.rmSync(temporary,{recursive:true,force:true}));
 const put=(file,content)=>{const target=path.join(temporary,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);};
 put('project.conf','WEB_LINK=https://vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\nWEB_ORGANIZER_CONTENT_PROFILE=vstupenky-cs\nWEB_SUPPORTED_LANGUAGES=cs\n');
 put('dist/index.html','<html><head><title>Compiled public client</title></head></html>');
 put('dist/.vite/manifest.json',JSON.stringify({'src/marketing/help.js':{file:'web-assets/help.js'}}));
 put('dist/web-assets/help.js','/* compiled helper */');put('dist/assets/translations/cs.json','{}');
 put('bundle/sitemap.xml','<urlset><url><loc>https://vstupenky.online/events</loc></url></urlset>');
 const render=()=>spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',path.join(temporary,'project.conf'),'--built-index',path.join(temporary,'dist/index.html'),'--output',path.join(temporary,'bundle/napoveda')],{encoding:'utf8'});
 const first=render();assert.equal(first.status,0,first.stderr);
 assert.match(fs.readFileSync(path.join(temporary,'bundle/sitemap.xml'),'utf8'),/https:\/\/vstupenky\.online\/napoveda\/zaciname\//);
 const index=path.join(temporary,'bundle/napoveda/index.html'),mtime=fs.statSync(index).mtimeMs;
 put('bundle/napoveda/stale.html','retired guide');const repeat=render();assert.equal(repeat.status,0,repeat.stderr);
 assert.equal(fs.statSync(index).mtimeMs,mtime);assert.equal(fs.existsSync(path.join(temporary,'bundle/napoveda/stale.html')),false);
 const sitemap=fs.readFileSync(path.join(temporary,'bundle/sitemap.xml'),'utf8');
 assert.equal(sitemap.split('https://vstupenky.online/napoveda/zaciname/').length-1,1,'one canonical sitemap entry');
});
test('public guides render crawlable linked documents, code generator without unpublished plugin downloads',t=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-help-'));t.after(()=>fs.rmSync(temporary,{recursive:true,force:true}));
 const target=path.join(temporary,'napoveda');const config=path.join(temporary,'project.conf');
 fs.writeFileSync(config,'WEB_LINK=https://vstupenky.online\nWEB_ORGANIZER_LANDING_ENABLED=true\nWEB_ORGANIZER_CONTENT_PROFILE=vstupenky-cs\nWEB_SUPPORTED_LANGUAGES=cs\n');
 const render=()=>spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',target],{encoding:'utf8'});
 let run=render();assert.equal(run.status,0,run.stderr);
 const pages=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/pages.json')));
 const coreTopics=['getting-started','form','ticket-pricing','seating','ticket-design','payments','orders','check-in','scanner-settings'];
 for(const id of [...coreTopics,'event-settings','bank-accounts','fio-token']) assert.ok(pages.some(page=>page.id===id),`Missing core organizer guide: ${id}`);
 assert.deepEqual([...new Set(pages.filter(page=>page.category).map(page=>page.category))],['basics','administration','tickets','banking','integrations','orders','check-in','troubleshooting']);
 const categories=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/categories.json'))).map(c=>({...c.cs,id:'category.'+c.id}));
 for(const page of [...pages,...categories]){
  const html=fs.readFileSync(path.join(target,page.slug,'index.html'),'utf8');
  assert.equal((html.match(/<h1>/g)||[]).length,1);assert.match(html,/<html lang="cs">/);assert.ok(html.includes(page.description));
  assert.ok(html.includes(`rel="canonical" href="https://vstupenky.online/napoveda/${page.slug?page.slug+'/':''}"`));
  assert.match(html,/data-help-search/);assert.match(html,/assets\/search\.[a-f0-9]+\.js/);assert.match(html,/BreadcrumbList/);if(page.id.startsWith('category.'))assert.match(html,/ItemList/);
  assert.match(html,/application\/ld\+json/);assert.doesNotMatch(html,/\{\{/);
  assert.match(html, /property="og:image" content="https:\/\/vstupenky\.online\/organizers-media\/organizers-social\.png"/);
  assert.match(html, /name="twitter:card" content="summary_large_image"/);
  assert.match(html, /name="twitter:description"/);

  if(page.id==='ai-agents') assert.doesNotMatch(html,/codex/i,'MCP guide metadata and body are client independent');
  if(page.id==='fio-token') {
   assert.equal((html.match(/<iframe /g)||[]).length,1);
   assert.match(html,/src="https:\/\/www\.youtube-nocookie\.com\/embed\/px9MCABSQbI"/);
   assert.match(html,/referrerpolicy="strict-origin-when-cross-origin"/);
  } else assert.doesNotMatch(html,/<iframe/);
  assert.match(html,/<header class="site-header/);assert.match(html,/<footer class="site-footer wrap"/);
  assert.doesNotMatch(html,/class="help-header|class="help-footer/);
  if(coreTopics.includes(page.id)) assert.match(html,/<figure class="guide-screenshot(?: guide-screenshot-mobile)?">/,`Missing actual product screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/napoveda\/[^"#]*)(?:#[^"]*)?"/g)) {
   const local=match[1].slice('/napoveda/'.length);const file=local.endsWith('/')||!local?path.join(target,local,'index.html'):path.join(target,local);
   assert.ok(fs.existsSync(file),`Missing guide/asset ${match[1]}`);
  }
 }
 const creation = fs.readFileSync(path.join(target,'zaciname/index.html'),'utf8');
 assert.match(creation, /href="\/events\?help=organization" target="_blank"/);
 assert.doesNotMatch(creation, /href="\/events" target="_blank"[^>]*>seznam akcí/);
 for (const slug of ['bankovni-ucet', 'fio-api-token']) {
   const guide = fs.readFileSync(path.join(target,slug,'index.html'),'utf8');
   assert.match(guide, /href="\/events\?help=bank-accounts" target="_blank"/);
 }
 const home=fs.readFileSync(path.join(target,'index.html'),'utf8');
 for (const route of ['/rezervacni-system-s-planem-salu']) {
  assert.ok(home.slice(0,home.indexOf('<footer')).includes(`href="${route}"`),'topic is discoverable from help overview');
  assert.ok(home.slice(home.indexOf('<footer')).includes(`href="${route}"`),'topic is linked in shared footer');
 }

 assert.ok(home.indexOf('href="/napoveda/zaciname-s-akci/"')<home.indexOf('href="/napoveda/integrace/"'));
 for(const category of categories){
  const listing=fs.readFileSync(path.join(target,category.slug,'index.html'),'utf8');
  const expected=pages.filter(p=>p.category===category.id.replace('category.','')).length;
  assert.equal((listing.match(/class="guide-preview(?:[^"]*)"/g)||[]).length,expected,'every listed guide has a preview');
 }
 assert.equal((home.match(/class="guide-preview(?:[^"]*)"/g)||[]).length,categories.length+3,'overview has category and entry-point previews');
 const mediaById=new Map(JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/media.json'))).map(item=>[item.id,item]));
 for(const page of pages.filter(p=>p.category)) assert.equal(mediaById.get(page.preview)?.locale,'cs','previews use real media from their own locale');
 for(const slug of ['odbaveni-navstevniku','pomoc-a-reseni-potizi']){
  const directoryHtml=fs.readFileSync(path.join(target,slug,'index.html'),'utf8');
  assert.match(directoryHtml,/class="guide-device"/,'portrait previews use a complete phone frame');
 }
 const bank=fs.readFileSync(path.join(target,'fio-api-token/index.html'),'utf8');
 assert.match(bank,/https:\/\/www\.youtube\.com\/watch\?v=px9MCABSQbI/);
 assert.match(bank,/data-help-workflow="organization"/);
 assert.match(bank,/class="guide-video-player"/);
 const wizard=fs.readFileSync(path.join(target,'zaciname/index.html'),'utf8');
 assert.match(wizard,/data-help-workflow="wizard"/);
 const existing=fs.readFileSync(path.join(target,'planek-salu/index.html'),'utf8');
 assert.match(existing,/data-help-workflow="administration"/);
 assert.doesNotMatch(existing,/cs-seating-saved|cs-seating-templates/,'wizard-only captures do not illustrate administration');
 const form=fs.readFileSync(path.join(target,'prodejni-formular/index.html'),'utf8');
 assert.ok(form.indexOf('class="help-step-action"')<form.indexOf('<h2 id="pole">'),'app link belongs to the opening step');
 assert.match(form,/href="\/events\?help=forms" target="_blank"/);
 assert.doesNotMatch(form,/help-app-action/);assert.match(form,/guide-screenshot-mobile/);
 const scanner=fs.readFileSync(path.join(target,'nastaveni-skeneru/index.html'),'utf8');
 assert.match(scanner,/href="\/events\?help=scanner-settings" target="_blank"/);
 const embed=fs.readFileSync(path.join(target,'vlozeni-na-web/index.html'),'utf8');assert.match(embed,/data-embed-generator/);
 const wordpress=fs.readFileSync(path.join(target,'wordpress/index.html'),'utf8');assert.match(wordpress,/Vlastní HTML/);assert.match(wordpress,/https:\/\/cs\.wordpress\.org\/plugins\/vstupenky-online\//);assert.doesNotMatch(wordpress,/inherit_style=|data-festapp-style/);assert.match(wordpress,/jedno uložené nastavení/);assert.match(wordpress,/240-4000/);assert.match(wordpress,/wordpress-02-block-editor/);
 assert.equal(fs.readdirSync(path.join(target,'assets')).some(name=>name.endsWith('.zip')),false,'plugin ZIP payloads stay out of help; link to the public directory');
 const joomla=fs.readFileSync(path.join(target,'joomla/index.html'),'utf8');assert.match(joomla,/Přístupný název iframe/);assert.match(joomla,/Uložený veřejný odkaz na formulář/);
 const wix=fs.readFileSync(path.join(target,'wix/index.html'),'utf8');assert.match(wix,/Add to Site/);assert.match(wix,/Přístupný název formuláře/);
 const measurement=fs.readFileSync(path.join(target,'mereni-formularu/index.html'),'utf8');
 const presetName=measurement.match(/href="\/napoveda\/assets\/(festapp-host-gtm\.[a-f0-9]+\.json)" download/)[1];
 const presetBytes=fs.readFileSync(path.join(target,'assets',presetName));
 assert.deepEqual(presetBytes,fs.readFileSync(path.join(root,'integrations/measurement/festapp-host-gtm.json')),'public download is the validated canonical preset');
 assert.ok(JSON.parse(presetBytes).containerVersion.tag.every(tag=>tag.paused),'customer imports start paused');
 assert.ok(embed.includes('/napoveda/mereni-formularu/'),'embed generator guide leads to measurement setup');
 const before=fs.readFileSync(path.join(target,'index.html'));run=render();assert.equal(run.status,0,run.stderr);assert.deepEqual(fs.readFileSync(path.join(target,'index.html')),before);
 const enTarget=path.join(temporary,'help');
 fs.writeFileSync(config,'WEB_LINK=https://tickets.festapp.net\nAPP_NAME=Festapp Tickets\nWEB_ORGANIZER_LANDING_ENABLED=true\nWEB_ORGANIZER_CONTENT_PROFILE=festapp-en\nWEB_SUPPORTED_LANGUAGES=en\n');
 const apiHelp=fs.readFileSync(path.join(target,'integrace/index.html'),'utf8');
 assert.match(apiHelp,/id="api"/);
 assert.ok(apiHelp.includes('href="https://api.vstupenky.online/integrations/v1/proofs/dpop/docs/" target="_blank"'));
 assert.ok(apiHelp.includes('href="https://api.vstupenky.online/integrations/v1/proofs/dpop/openapi.json"'));
 const apiSearchSource=fs.readFileSync(path.join(target,'assets',fs.readdirSync(path.join(target,'assets')).find(name=>/^search\.[a-f0-9]+\.js$/.test(name))),'utf8');
 const apiSearchData=JSON.parse(apiSearchSource.slice('globalThis.FestappHelpSearchData='.length,apiSearchSource.indexOf(';\n')));
 const apiEntry=apiSearchData.entries.find(entry=>entry.id==='api-reference');
 assert.equal(apiEntry.url,'/napoveda/integrace/#api');
 assert.ok(apiEntry.aliases.includes('Swagger'));
 const english=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',enTarget,'--preview'],{encoding:'utf8'});
 assert.equal(english.status,0,english.stderr);
 const globalApiHelp=fs.readFileSync(path.join(enTarget,'integrations/index.html'),'utf8');
 assert.ok(globalApiHelp.includes('href="https://api.festapp.net/integrations/v1/proofs/dpop/docs/" target="_blank"'));
 assert.ok(globalApiHelp.includes('href="https://api.festapp.net/integrations/v1/proofs/dpop/openapi.json"'));
 assert.doesNotMatch(globalApiHelp,/api\.vstupenky\.online/);
 const englishPages=JSON.parse(fs.readFileSync(path.join(root,'automation/release/help/pages.en.json')));
 const regionalTopics=new Set(['wordpress','joomla','wix','ai-agents','mcp-reference']);
 assert.deepEqual(englishPages.map(p=>p.id),pages.filter(p=>!regionalTopics.has(p.id)).map(p=>p.id),'global help publishes only integrations currently available globally');
 for(const page of englishPages){
  const html=fs.readFileSync(path.join(enTarget,page.slug,'index.html'),'utf8');
  assert.match(html,/<html lang="en">/);assert.match(html,/noindex,nofollow/);
  for (const tag of ['property="og:image"', 'name="twitter:image"']) assert.ok(html.includes(`${tag} content="https://tickets.festapp.net/organizers-media/global/festapp-tickets-social.png"`));
  assert.match(html, /property="og:locale" content="en_US"/);
  assert.match(html, /property="og:image:width" content="1200"/);
  assert.match(html, /property="og:image:height" content="630"/);
  assert.match(html, /name="twitter:card" content="summary_large_image"/);

  assert.doesNotMatch(html,/vstupenky\.online|\{\{|Nápověda|Přihlásit se|cs-webnode-/,'English guide has no regional branding, Czech chrome or screenshot fallback');
  assert.match(html,/https:\/\/cal\.com\/michael-bujnovsky-5srszz\/ukazka/,'all guides use the canonical booking target');
  if(coreTopics.includes(page.id))assert.match(html,/<figure class="guide-screenshot(?: guide-screenshot-mobile)?">/,`Missing localized screenshot: ${page.id}`);
  for(const match of html.matchAll(/(?:href|src)="(\/help\/[^"#]*)(?:#[^"]*)?"/g)){
   const local=match[1].slice('/help/'.length);assert.ok(fs.existsSync(local.endsWith('/')||!local?path.join(enTarget,local,'index.html'):path.join(enTarget,local)),match[1]);
  }
 }
 for(const slug of ['', 'integrations', 'form-measurement'])assert.doesNotMatch(fs.readFileSync(path.join(enTarget,slug,'index.html'),'utf8'),/WordPress|Joomla|Wix|MCP|agent access/,'global help does not promote withheld integrations');
 assert.equal(fs.existsSync(path.join(enTarget,'assets/mcp-reference.json')),false,'regional-only MCP metadata is not shipped');
 const enMeasurement=fs.readFileSync(path.join(enTarget,'form-measurement/index.html'),'utf8');
 assert.ok(enMeasurement.includes(presetName),'both languages download one canonical preset');
 const published=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',enTarget],{encoding:'utf8'});
 assert.equal(published.status,0,published.stderr);
 const publishedHome=fs.readFileSync(path.join(enTarget,'index.html'),'utf8');
 assert.match(publishedHome,/rel="canonical" href="https:\/\/tickets\.festapp\.net\/help\/"/);
 assert.match(publishedHome,/name="robots" content="index,follow"/);
 fs.writeFileSync(config,'WEB_LINK=https://other.invalid\nWEB_ORGANIZER_LANDING_ENABLED=false\nWEB_ORGANIZER_CONTENT_PROFILE=festapp-en\nWEB_SUPPORTED_LANGUAGES=en\n');
 const disabled=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output',enTarget],{encoding:'utf8'});
 assert.equal(disabled.status,0,disabled.stderr);assert.equal(fs.existsSync(enTarget),false,'disabled tenant does not retain English help');

});

test('disabled organizer help cleans both language outputs for other tenant locales',t=>{
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-disabled-help-'));t.after(()=>fs.rmSync(temporary,{recursive:true,force:true}));
 const config=path.join(temporary,'project.conf');
 fs.writeFileSync(config,'WEB_LINK=https://other.invalid\nWEB_ORGANIZER_LANDING_ENABLED=false\nWEB_SUPPORTED_LANGUAGES=sk\n');
 for(const language of ['napoveda','help'])fs.mkdirSync(path.join(temporary,'output',language),{recursive:true});
 const result=spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--output-root',path.join(temporary,'output')],{encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
 for(const language of ['napoveda','help'])assert.equal(fs.existsSync(path.join(temporary,'output',language)),false);
});

test('phone scanner guides use only mobile webclient captures in both locales',()=>{
 const directory=path.join(root,'automation/release/help');
 const media=new Map(JSON.parse(fs.readFileSync(path.join(directory,'media.json'))).map(item=>[item.id,item]));
 for(const [locale,doorFile,settingsFile] of [['cs','odbaveni.html','nastaveni-skeneru.html'],['en','en/check-in.html','en/scanner-settings.html']]){
  const door=fs.readFileSync(path.join(directory,doorFile),'utf8');
  const settings=fs.readFileSync(path.join(directory,settingsFile),'utf8');
  const figures=[...`${door}\n${settings}`.matchAll(/\{\{MEDIA:([^}]+)\}\}/g)];
  assert.match(settings,/\{\{APP_LINK:scanner-settings\}\}/,'organizer settings must open the matching help intent');
  assert.doesNotMatch(door,/MEDIA:[^}]+\/(?:field-options|advanced|preview)\}\}/,'door staff recovery stays separate from organizer setup');
  for(const state of [...(locale==='cs'?['invalid-access']:[]),'not-found','settings','field-options','advanced','preview']) {
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
