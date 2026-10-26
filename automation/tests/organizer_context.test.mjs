import { helpActionWorkerSource } from '../lib/help_action_worker_source.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, cpSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { readConfig, resolveContext, publicManifest } from '../release/organizers/context.mjs';
import { collectPwaShellManifest } from '../lib/pwa_shell_manifest.mjs';
import { verifyMarketingBundle } from '../release/organizers/verify.mjs';
const source = new URL('../release/organizers/', import.meta.url);
const csConfig = readConfig(new URL('../project.conf', import.meta.url));
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(),'organizer-context-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  mkdirSync(join(root,'automation/release'),{recursive:true});
  cpSync(source,join(root,'automation/release/organizers'),{recursive:true});
  cpSync(new URL('../release/render_organizer_page.mjs',import.meta.url),join(root,'automation/release/render_organizer_page.mjs'));
  cpSync(new URL('../../web/organizers-media/',import.meta.url),join(root,'web/organizers-media'),{recursive:true});
  const configPath = join(root,'project.conf');
  const setConfig = config => writeFileSync(configPath,Object.entries(config).map(([k,v])=>`${k}=${v}`).join('\n')+'\n');
  const render = () => spawnSync(process.execPath,[join(root,'automation/release/render_organizer_page.mjs'),'--config',configPath],{encoding:'utf8'});
  return {root, configPath, setConfig, render, profilesDir:join(root,'automation/release/organizers')};
}
test('one registry drives CS HTML, offline topics, sitemap and deterministic generation',async t=>{
  const f=fixture(t); f.setConfig(csConfig);
  mkdirSync(join(f.root,'web/organizers'),{recursive:true});
  writeFileSync(join(f.root,'web/organizers/ball-ticket-sales'),'retired article');
  const result=f.render(); assert.equal(result.status,0,result.stderr);
  const context=await verifyMarketingBundle(join(f.root,'web'),f.configPath);
  assert.equal(context.pages.length,2);
  assert.equal(existsSync(join(f.root,'web/organizers/ball-ticket-sales')),false);
  assert.deepEqual(context.redirects,[{from:'/prodej-vstupenek-na-ples',to:'/'}]);
  const manifest=JSON.parse(readFileSync(join(f.root,'web/organizer-pages.json')));
  assert.deepEqual(manifest,publicManifest(context));
  for (const name of ['flutter','webclient']) writeFileSync(join(f.root,'web',name),name);
  const pwa=await collectPwaShellManifest(join(f.root,'web'));
  for (const page of context.pages) {
    assert.equal(pwa.marketingRoutes[page.path],page.asset);
    assert.ok(!pwa.coreResources.includes(pwa.marketingRoutes[page.path]));
  }
  assert.ok(!pwa.knownResources.some(url=>/\.(mp4|webm)$/.test(url)));
  const before=context.pages.map(page=>readFileSync(join(f.root,'web',page.asset),'utf8'));
  assert.equal(f.render().status,0);
  assert.deepEqual(context.pages.map(page=>readFileSync(join(f.root,'web',page.asset),'utf8')),before);
});
test('synthetic EN uses same renderer, empty references, own media and optional topic without CS fallback',async t=>{
  const f=fixture(t);
  const content=JSON.parse(readFileSync(join(f.profilesDir,'content.json')));
  const p=content.publicProjection;
  p.locale='en';p.languageTag='en-GB';p.ogLocale='en_GB';p.contact='support@example.invalid';
  p.seo={siteName:'Example Tickets',title:'Ticket sales | Example Tickets',description:'Plan your event and sell tickets.',image:'/organizers-media/fixture-en.svg',imageAlt:'Example ticket',catalogTitle:'Events | Example Tickets',catalogDescription:'Find an event.'};
  p.references=[];p.referencesHeading='Events using Example Tickets';p.catalogLabel='Find an event';
  p.bookingUrl='mailto:support@example.invalid';p.serviceName='Ticket sales';p.serviceType='Event management';
  p.provider={name:'Example Operator',identifier:'123456',identifierLabel:'Business ID'};
  p.cta={href:'/events?create=1',label:'Create event',note:'Sign in to prepare your event.'};
  p.templateTexts=Object.fromEntries(Object.keys(p.page ?? p.templateTexts).map(key=>[key,'Example event information']));
  p.helpLink=null;p.redirects=[];
  p.templateTexts.TEXT_5='Tickets';p.templateTexts.TEXT_6='for your event.';
  p.page=p.templateTexts;
  p.templateTexts.TEXT_35='Payments';p.templateTexts.TEXT_36='Contact us to discuss payment options.';
  p.ui=Object.fromEntries(Object.keys(p.ui).map(key=>[key,'Example information']));
  Object.assign(p.ui,{home:'Home',play:'Play',pause:'Pause',retry:'Retry',replay:'Replay',position:'{first}-{last} of {count} events',total:'{count} events'});
  p.footerLinks=[{href:'/events',label:'Events'},{href:'/privacy/',label:'Privacy'},{href:'/terms/',label:'Terms'},{href:'/support/',label:'Support'}];
  p.pages=[{id:'home',path:'/',title:p.seo.title,description:p.seo.description},{id:'seating-reservations',path:'/reserved-seats',title:'Reserved seats | Example Tickets',description:'Choose a seat.',heading:'Choose your seat',intro:'Plan tables and seats for your guests.',sections:['example'],stepsHeading:'Prepare your hall',steps:['Arrange tables.','Publish your form.'],faqHeading:'Questions',faq:[{question:'Can guests choose seats?',answer:'Yes, with a seating plan.'}]}];
  writeFileSync(join(f.profilesDir,'en.json'),JSON.stringify(content));
  writeFileSync(join(f.profilesDir,'en-clips.json'),JSON.stringify({clips:[{id:'example',label:'Example',description:'English example',src:'/organizers-media/fixture-en.mp4',poster:'/organizers-media/fixture-en.svg',width:640,height:360}],sections:[{id:'example',title:'Seating plan',description:'Arrange tables and seats.',eyebrow:'Your hall',detail:'Example fixture',clips:['example']}]}));
  writeFileSync(join(f.root,'web/organizers-media/fixture-en.svg'),'<svg xmlns="http://www.w3.org/2000/svg"/>');
  writeFileSync(join(f.root,'web/organizers-media/fixture-en.mp4'),'synthetic fixture, not production footage');
  writeFileSync(join(f.profilesDir,'profiles.json'),JSON.stringify({'example-en':{locale:'en',content:'en.json',clips:'en-clips.json'}}));
  const config={...csConfig,DOMAIN:'tickets.example.invalid',WEB_LINK:'https://tickets.example.invalid',WEB_SUPPORTED_LANGUAGES:'en,cs',WEB_ORGANIZER_CONTENT_PROFILE:'example-en',APP_NAME:'Example Tickets',PRIVACY_URL:'https://tickets.example.invalid/privacy/',TERMS_URL:'https://tickets.example.invalid/terms/',SUPPORT_URL:'https://tickets.example.invalid/support/'};
  f.setConfig(config);const result=f.render();assert.equal(result.status,0,result.stderr);
  for(const asset of ['organizers-page','organizers/seating-reservations']) {
    const html=readFileSync(join(f.root,'web',asset),'utf8');
    assert.ok(html.includes('lang="en"'));assert.ok(html.includes('en-GB'));
    assert.ok(html.includes('"play":"Play"'));assert.ok(html.includes('aria-label="Play: English example"'));
    assert.doesNotMatch(html,/vstupenky\.online|Country bál|Přehrát|transakční|data-reference-carousel|data-reference-controls|\/prodej-vstupenek-na-ples/);
  }
  const manifest=JSON.parse(readFileSync(join(f.root,'web/organizer-pages.json')));
  assert.deepEqual(manifest.sitemapPaths,['/','/reserved-seats','/events']);
  assert.equal(existsSync(join(f.root,'web/organizers/ball-ticket-sales')),false);
  // Resolver identity and missing locales fail closed.
  assert.throws(()=>resolveContext({...config,WEB_SUPPORTED_LANGUAGES:'cs'},{profilesDir:f.profilesDir}),/profile\/locale/);
  for(const name of ['flutter','webclient']) writeFileSync(join(f.root,'web',name),name);
  const pwa=await collectPwaShellManifest(join(f.root,'web'));
  assert.equal(pwa.marketingRoutes['/reserved-seats'],'/organizers/seating-reservations');
  assert.equal(pwa.marketingRoutes['/prodej-vstupenek-na-ples'],undefined);
  const script=readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
  const scanner=readFileSync(new URL('../../web_client/src/services/scanner_routes.js',import.meta.url),'utf8').replaceAll('export function','function');
  const workerSource=scanner+'\n'+script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource)
    .replace('const MARKETING = {enabled:false,pages:[],sitemapPaths:["/"]};',`const MARKETING = ${JSON.stringify(manifest)};`)
    .replace('const CANONICAL_ORIGIN = null;',`const CANONICAL_ORIGIN = "${config.WEB_LINK}";`);
  const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(workerSource).toString('base64'));
  const env={ASSETS:{fetch:async request=>{const asset=new URL(request.url).pathname;return existsSync(join(f.root,'web',asset))?new Response(readFileSync(join(f.root,'web',asset))):new Response('missing',{status:404});}}};
  const response=await worker.fetch(new Request(config.WEB_LINK+'/reserved-seats?utm_source=test'),env);
  assert.equal(response.status,200);assert.ok((await response.text()).includes('Choose your seat'));
  t.mock.method(console,'error',()=>{});
  const xml=await (await worker.fetch(new Request(config.WEB_LINK+'/sitemap.xml'),env)).text();
  assert.ok(xml.includes(config.WEB_LINK+'/reserved-seats'));assert.doesNotMatch(xml,/vstupenky|prodej-vstupenek/);
  f.setConfig({...config,WEB_ORGANIZER_LANDING_ENABLED:'false'});assert.equal(f.render().status,0);
  for(const asset of manifest.pages.map(page=>page.asset)) assert.equal(existsSync(join(f.root,'web',asset)),false);
});
test('invalid paths, duplicate identities and missing media never replace accepted outputs',t=>{
  const f=fixture(t);f.setConfig(csConfig);assert.equal(f.render().status,0);
  const target=join(f.root,'web/organizers-page'),before=readFileSync(target,'utf8');
  const contentPath=join(f.profilesDir,'content.json'),original=readFileSync(contentPath,'utf8');
  for(const path of ['/events','/login','/settings','/map-editor','/google-auth','/check/1','/unit/event','/../escape','https://foreign.invalid/','//foreign.invalid','/privacy/choices','/with?query','/']) {
    const content=JSON.parse(original);content.publicProjection.pages[1].path=path;
    writeFileSync(contentPath,JSON.stringify(content));assert.notEqual(f.render().status,0,path);
    assert.equal(readFileSync(target,'utf8'),before);
  }
  for(const redirects of [[{from:'/login',to:'/'}],[{from:'/old-page',to:'https://foreign.invalid/'}]]) {
    const changed=JSON.parse(original);changed.publicProjection.redirects=redirects;
    writeFileSync(contentPath,JSON.stringify(changed));assert.notEqual(f.render().status,0);
    assert.equal(readFileSync(target,'utf8'),before);
  }
  const content=JSON.parse(original);content.publicProjection.pages[1].id='home';
  writeFileSync(contentPath,JSON.stringify(content));assert.notEqual(f.render().status,0);
  writeFileSync(contentPath,original);rmSync(join(f.root,'web/organizers-media/organizers-social.png'));
  assert.notEqual(f.render().status,0);assert.equal(readFileSync(target,'utf8'),before);
  for(const override of [{WEB_LINK:'https://vstupenky.online/prefix'},{DOMAIN:'wrong.invalid'},{WEB_ORGANIZER_CONTENT_PROFILE:'missing'}]) assert.throws(()=>resolveContext({...csConfig,...override}));
});
