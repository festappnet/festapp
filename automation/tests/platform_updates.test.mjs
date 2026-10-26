import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import {resolveUpdates} from '../release/platform_updates/context.mjs';
import {renderUpdate} from '../release/platform_updates/render.mjs';
import {readConfig,resolveContext,publicManifest} from '../release/organizers/context.mjs';
const origin='https://vstupenky.online';
function fixture(t) {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'platform-updates-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const contentDir=path.join(dir,'content');fs.mkdirSync(contentDir);
 const add=(id,patch={})=>{const folder=path.join(contentDir,id);fs.mkdirSync(folder,{recursive:true});const meta={id,status:'published',kind:'feature',publishedAt:'2026-10-25T12:00:00Z',translations:{cs:{title:'Český titulek',summary:'Český přínos'},en:{title:'English title',summary:'English benefit'}},...patch};fs.writeFileSync(path.join(folder,'meta.json'),JSON.stringify(meta));for(const lang of ['cs','en']) fs.writeFileSync(path.join(folder,lang+'.md'),'## Content\n\nA paragraph with [help](https://example.org).\n\n- First\n- Second');return meta;};
 const options={contentDir,assetsDir:dir,now:new Date('2026-10-26T12:00:00Z')};
 return {dir,contentDir,add,options,resolve:()=>resolveUpdates(origin,options)};
}
test('one bilingual identity drives stable pages/feed order, metadata without a separate language switch',t=>{
 const f=fixture(t); f.add('zeta');f.add('alpha');f.add('newer',{publishedAt:'2026-10-26T08:00:00Z',updatedAt:'2026-10-26T09:00:00Z'});f.add('secret',{status:'draft',translations:null});
 const u=f.resolve();assert.deepEqual(u.items.map(i=>i.id),['newer','alpha','zeta']);assert.equal(u.pages.length,8);assert.ok(!JSON.stringify(u).includes('secret'));
 const context={...resolveContext(readConfig(new URL('../project.conf',import.meta.url)),{updatesOptions:f.options}),updates:u};
 for(const page of u.pages) {const html=renderUpdate(page,context);assert.match(html,new RegExp(`<html lang="${page.locale}">`));assert.ok(html.includes(`rel="canonical" href="${page.canonical}"`));assert.equal((html.match(/<h1[ >]/g)||[]).length,1);assert.ok(html.includes('hreflang="cs"'));assert.ok(html.includes('hreflang="en"'));assert.ok(!html.includes('class="language"'));assert.ok(!/<a[^>]*hreflang=/.test(html));if(page.updateId){const item=u.feed.items.find(i=>i.id===page.updateId);assert.equal(item.translations[page.locale].url,page.canonical);assert.ok(html.includes(item.translations[page.locale==='cs'?'en':'cs'].url));}}
 assert.ok(!JSON.stringify(u.feed).includes('html'));assert.ok(!JSON.stringify(u.feed).includes('Content'));
});
test('published contracts fail with field/file evidence; drafts may remain incomplete',t=>{
 const f=fixture(t);f.add('item',{translations:{cs:{title:'T',summary:'S'}}});assert.throws(f.resolve,/meta.json:.*translations.en.title/);
 f.add('item',{publishedAt:'2099-01-01T00:00:00Z'});assert.throws(f.resolve,/publishedAt/);
 f.add('item',{publishedAt:'2026-02-30T00:00:00Z'});assert.throws(f.resolve,/publishedAt/);
 f.add('item',{id:'different'});assert.throws(f.resolve,/id/);
 f.add('item',{status:'draft',translations:null,publishedAt:null});assert.equal(f.resolve().items.length,0);
});
test('safe Markdown, alt text and repository assets are validated before rendering',t=>{
 const f=fixture(t);f.add('item');const body=path.join(f.contentDir,'item/cs.md');
 for(const input of ['<script>alert(1)</script>','[bad](javascript:alert(1))','[bad](file:///etc/passwd)','![Alt](/platform-updates-media/missing.png)','![](/platform-updates-media/a.png)']) {fs.writeFileSync(body,input);assert.throws(f.resolve,/cs.md:/,input);}
 fs.mkdirSync(path.join(f.dir,'platform-updates-media'));fs.writeFileSync(path.join(f.dir,'platform-updates-media/a.png'),'image');fs.writeFileSync(body,'# Heading\n\n![An image](/platform-updates-media/a.png)\n\n[Link](https://example.org/?a=1&b=2)');
 const u=f.resolve();assert.deepEqual(u.assets,['/platform-updates-media/a.png']);assert.match(u.items[0].translations.cs.html,/<h2>Heading/);assert.match(u.items[0].translations.cs.html,/alt="An image"/);
});
test('single resolved registry excludes updates on profiles without explicit capability',t=>{
 const f=fixture(t);f.add('item');const config=readConfig(new URL('../project.conf',import.meta.url));const context=resolveContext(config,{updatesOptions:f.options});
 for(const page of context.updates.pages) assert.ok(publicManifest(context).pages.some(p=>p.path===page.path));
 assert.deepEqual(publicManifest(context).feeds,['/platform-updates.json']);
 assert.deepEqual(resolveContext({...config,WEB_ORGANIZER_LANDING_ENABLED:'false'}).pages,[]);
});
test('incremental renderer removes published -> draft HTML/feed/sitemap entries and tenant-off outputs',t=>{
 const f=fixture(t);f.add('item');
 const root=path.join(f.dir,'repo');fs.mkdirSync(path.join(root,'automation/release'),{recursive:true});
 for(const dir of ['organizers','platform_updates']) fs.cpSync(new URL('../release/'+dir,import.meta.url),path.join(root,'automation/release',dir),{recursive:true,filter:source=>!source.includes('node_modules')});
 fs.symlinkSync(path.resolve('automation/release/platform_updates/node_modules'),path.join(root,'automation/release/platform_updates/node_modules'),'dir');
 fs.cpSync(new URL('../release/render_organizer_page.mjs',import.meta.url),path.join(root,'automation/release/render_organizer_page.mjs'));
 fs.cpSync(new URL('../../web/organizers-media',import.meta.url),path.join(root,'web/organizers-media'),{recursive:true});
 fs.cpSync(f.contentDir,path.join(root,'content/platform-updates'),{recursive:true});
 const config=path.join(root,'project.conf');fs.copyFileSync(new URL('../project.conf',import.meta.url),config);
 const render=(extra=[])=>{const r=spawnSync(process.execPath,[path.join(root,'automation/release/render_organizer_page.mjs'),'--config',config,...extra],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);};
 render();assert.ok(fs.existsSync(path.join(root,'web/organizers/updates/en/item')));
 const built=path.join(root,'bundle');
 fs.cpSync(path.join(root,'web/organizers-media'),path.join(built,'organizers-media'),{recursive:true});
 for (const base of [path.join(root,'web'),built]) {fs.mkdirSync(path.join(base,'platform-updates-media'));fs.writeFileSync(path.join(base,'platform-updates-media/a.png'),'image bytes');}
 fs.writeFileSync(path.join(root,'content/platform-updates/item/cs.md'),'![Alt](/platform-updates-media/a.png)');
 const index=path.join(root,'built-index/index.html');fs.mkdirSync(path.dirname(index),{recursive:true});fs.mkdirSync(path.join(path.dirname(index),'.vite'));
 fs.writeFileSync(index,'<link rel="stylesheet" href="/web-assets/theme.css">');fs.writeFileSync(path.join(path.dirname(index),'.vite/manifest.json'),JSON.stringify({'src/marketing/landing.js':{file:'web-assets/landing.js'}}));
 const buildArgs=['--built-index',index,'--output',path.join(built,'organizers-page')];render(buildArgs);
 assert.ok(fs.existsSync(path.join(built,'platform-updates-media/a.png')));
 const meta=path.join(root,'content/platform-updates/item/meta.json');const m=JSON.parse(fs.readFileSync(meta));m.status='draft';fs.writeFileSync(meta,JSON.stringify(m));render();render(buildArgs);
 assert.ok(!fs.existsSync(path.join(built,'platform-updates-media/a.png')),'draft image must leave the deployable/offline bundle');
 assert.ok(!fs.existsSync(path.join(root,'web/organizers/updates/en/item')));assert.equal(JSON.parse(fs.readFileSync(path.join(root,'web/platform-updates.json'))).items.length,0);assert.ok(!fs.readFileSync(path.join(root,'web/organizer-pages.json'),'utf8').includes('/item'));
 fs.writeFileSync(config,'WEB_LINK=https://other.invalid\n');render();assert.ok(!fs.existsSync(path.join(root,'web/platform-updates.json')));assert.ok(!fs.existsSync(path.join(root,'web/organizers/updates')));
});
