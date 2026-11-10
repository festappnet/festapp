import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';

const bundle = await build({stdin:{contents:`
import {startMeasurementConsent} from './src/components/forms/form_measurement_cmp.js';
import {LocalizationService} from './src/services/localization_service.js';
window.startFixture = (translations, transport, privacy_url = 'https://organizer.example/privacy', consent_notice, approved_hosts, measurement_consent_bridge = true) => {
 LocalizationService.translations = translations;
 return startMeasurementConsent({model:{data:{analytics:{organization:1,unit:2,processing_revision:"a",privacy_url,consent_notice,approved_hosts,measurement_consent_bridge}}},setConsent:value=>transport.setConsent(value),host:document.querySelector('main')});
};`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
const settle=()=>new Promise(resolve=>setTimeout(resolve,30));
const none={analytics:false,marketing:false},both={analytics:true,marketing:true};
// Klaro runs in the JSDOM realm; compare plain values here.
const plain=value=>value && typeof value==='object'?{...value}:value;
for (const lang of ['cs','sk','en','de','pl','uk']) test(`actual Klaro first choice and saved settings in ${lang}`,async()=>{
 const translations=JSON.parse(readFileSync(new URL(`../../../assets/translations/${lang}.json`,import.meta.url)));
 const strings=translations.FeatureFormSettings;
 const dom=new JSDOM(`<html lang="${lang}"><head></head><body style="overflow:auto"><main></main></body></html>`,{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window, grants=[];
 try {
  win.eval(bundle.outputFiles[0].text);
  const cleanup=win.startFixture(translations,{setConsent:granted=>grants.push(plain(granted))});
  await settle();
  const root=win.document.querySelector('#festapp-measurement-consent');
  assert.deepEqual([...root.querySelectorAll('button')].map(b=>b.textContent),[strings.measurementConsentDecline,strings.measurementConsentAccept,strings.measurementConsentSettings]);
  const buttons=[...root.querySelectorAll('.cn-buttons button')];
  for(const property of ['backgroundColor','color','fontWeight','padding','minWidth'])
   assert.equal(win.getComputedStyle(buttons[0])[property],win.getComputedStyle(buttons[1])[property]);
  assert.equal(root.querySelectorAll('input').length,0);
  assert.equal(root.querySelectorAll('.hide').length,0);
  assert.equal(root.querySelector('a').textContent,strings.measurementConsentPrivacy);
  assert.equal(win.document.body.style.overflow,'hidden');
  const visibleText=[...root.querySelectorAll('p,h1,h2,button')].map(n=>n.textContent).join(' ');
  assert(!/<tr-|počítače/.test(visibleText));
  assert.deepEqual(grants.at(-1),none,'nothing is granted before a choice');
  root.querySelector('.cm-btn-success').click();await settle();
  assert.deepEqual(grants.at(-1),both);assert.equal(win.document.body.style.overflow,'auto');
  const fab=win.document.querySelector('.festapp-consent-fab');
  assert.equal(fab.parentNode,win.document.body,'floating button is anchored to the viewport');
  assert.equal(fab.getAttribute('aria-label'),strings.measurementConsentChoices);
  fab.click();await settle();
  assert(!/<tr-|počítače|missing/.test(root.textContent));
  const toggle=name=>root.querySelector(`#service-item-${name}`);
  assert.equal(root.querySelectorAll('input[type=checkbox]:not(:disabled)').length,2,'one toggle per purpose, no toggle-all row');
  for(const text of [strings.measurementConsentService,strings.measurementConsentAnalyticsDescription,strings.measurementConsentMarketing,strings.measurementConsentMarketingDescription]) assert(root.textContent.includes(text),text);
  assertNecessary(root,strings);
  assert.equal(toggle('analytics').checked,true);assert.equal(toggle('marketing').checked,true);
  toggle('marketing').click();await settle();assert.deepEqual(grants.at(-1),{analytics:true,marketing:false},'unsaved denial fails closed');
  root.querySelector('.cm-btn-accept').click();await settle();assert.deepEqual(grants.at(-1),{analytics:true,marketing:false});
  win.document.querySelector('.festapp-consent-fab').click();await settle();
  assert.equal(toggle('marketing').checked,false);
  toggle('analytics').click();await settle();assert.deepEqual(grants.at(-1),none);
  toggle('marketing').click();await settle();assert.deepEqual(grants.at(-1),none,'draft grant is not saved consent');
  root.querySelector('.cm-btn-accept').click();await settle();assert.deepEqual(grants.at(-1),{analytics:false,marketing:true});
  cleanup();assert.equal(win.document.body.style.overflow,'auto');assert.equal(grants.at(-1),false);
  assert.equal(win.document.querySelector('.festapp-consent-fab'),null,'cleanup removes the floating button');
 } finally { win.close(); }
});
test('a choice saved before the marketing purpose existed is asked again and grants nothing',async()=>{
 const dom=new JSDOM('<html lang="cs"><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window,grants=[];
 try {
  win.document.cookie=`festapp-measurement-1-2=${encodeURIComponent(JSON.stringify({analytics:true}))}; path=/`;
  win.eval(bundle.outputFiles[0].text);
  const cleanup=win.startFixture(JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url))),{setConsent:value=>grants.push(plain(value))});
  await settle();
  assert.deepEqual(grants.at(-1),none);assert.ok(win.document.querySelector('.cookie-modal-notice'));assert.equal(win.document.body.style.overflow,'hidden');
  win.document.querySelector('.cm-btn-success').click();await settle();assert.deepEqual(grants.at(-1),both);
  cleanup();
 } finally {win.close();}
});
const cs=()=>JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
async function notice(consent_notice,body=''){
 const dom=new JSDOM(`<html lang="cs"><head></head><body style="${body}"><main></main></body></html>`,{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window,grants=[];win.eval(bundle.outputFiles[0].text);
 const cleanup=win.startFixture(cs(),{setConsent:value=>grants.push(plain(value))},'https://organizer.example/privacy',consent_notice);
 await settle();
 return {win,grants,cleanup,root:win.document.querySelector('#festapp-measurement-consent'),css:win.document.head.querySelector('style:last-of-type').textContent};
}

test('CMP reports only choices and never starts a transport, even on failure',async()=>{
 const dom=new JSDOM('<html lang="cs"><head></head><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window,log=[];win.eval(bundle.outputFiles[0].text);
 const cleanup=win.startFixture(cs(),{setConsent:value=>log.push(plain(value)),start:()=>log.push('start')});await settle();
 assert.deepEqual(log,[none],'only the saved choice is reported');
 win.document.querySelector('.cn-decline').click();await settle();assert.equal(log.filter(x=>x==='start').length,0);assert.deepEqual(log.at(-1),none);
 cleanup();win.close();
 const broken=new JSDOM('<html lang="cs"><head></head><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 broken.window.eval(bundle.outputFiles[0].text);Object.defineProperty(broken.window.document,'cookie',{get(){throw Error('storage blocked');}});
 let started=0;broken.window.startFixture(cs(),{setConsent(){},start:()=>started++});await settle();assert.equal(started,0,'a broken CMP cannot start measurement');broken.window.close();
});

test('both layouts are the same mandatory notice; bar is the default and only docks it',async()=>{
 for(const [consent_notice,docked] of [[undefined,true],[{layout:'bar'},true],[{layout:'unknown'},true],[{layout:'modal'},false]]) {
  const {win,root,css,grants,cleanup}=await notice(consent_notice);
  assert.equal(css.includes('bottom:0'),docked,JSON.stringify(consent_notice));
  assert.ok(root.querySelector('.cookie-modal-notice'));assert.ok(root.querySelector('.cm-bg'));assert.equal(root.querySelectorAll('.hide').length,0);
  assert.equal(win.document.body.style.overflow,'hidden');assert.deepEqual(grants.at(-1),none);
  root.querySelector('.cm-bg').click();await settle();assert.ok(root.querySelector('.cookie-modal-notice'),'the backdrop does not dismiss it');
  assert.deepEqual([...root.querySelectorAll('.cookie-modal-notice button')].map(b=>b.textContent),['Odmítnout','Přijmout','Nastavení']);
  cleanup();win.close();
 }
});

test('custom text retains fixed withdrawal information, purposes and policy link',async()=>{
 const strings=cs().FeatureFormSettings;
 const {win,root,cleanup}=await notice({layout:'bar',title:'Vlastní nadpis',text:'Vlastní {neznámé} {privacyPolicy} text'});
 assert.equal(root.querySelector('#id-cookie-title').textContent,'Vlastní nadpis');
 const text=root.querySelector('#id-cookie-notice').textContent;assert.match(text,/^Vlastní neznámé privacyPolicy text/);assert.ok(!text.includes(strings.measurementConsentDescription));
 assert.equal(root.querySelector('.cookie-modal-notice a').getAttribute('href'),'https://organizer.example/privacy');
 assert.equal(root.querySelector('.cookie-modal-notice a').textContent,strings.measurementConsentPrivacy);
 assert.equal(root.querySelector('.cookie-modal-notice a').target,'_blank','the standalone form keeps the visitor on the form');
 assert.ok(root.querySelector('.cookie-modal-notice a').relList.contains('noopener'));
 win.document.querySelector('.festapp-consent-fab').click();await settle();
 for (const link of root.querySelectorAll('a[href]')) assert.equal(link.target,'_blank','dialog links open in a new tab too');
 // The settings dialog keeps its own fixed heading; the custom title belongs to the notice.
 assert.ok(root.textContent.includes(strings.measurementConsentModalTitle));
 assert.ok(root.querySelector('.cm-header').textContent.includes('Vlastní neznámé'),'organizer text stays in the settings dialog');
 assert.ok(root.querySelector('.cm-header').textContent.includes(strings.measurementConsentModalDescription));
 assert.ok(text.includes(strings.measurementConsentChangeChoice));
 assert.ok(root.querySelector('.cm-header').textContent.includes(strings.measurementConsentChangeChoice));for(const key of ['measurementConsentService','measurementConsentMarketing','measurementConsentMarketingDescription'])assert.ok(root.textContent.includes(strings[key]),key);
 cleanup();win.close();
 for(const blank of [{title:'',text:'  '},{title:null,text:null},{title:1,text:{}}]) {
  const value=await notice(blank);assert.equal(value.root.querySelector('#id-cookie-title').textContent,strings.measurementConsentTitle);assert.ok(value.root.textContent.includes(strings.measurementConsentDescription));value.cleanup();value.win.close();
 }
});

test('custom text is inert plain text in the notice and the settings',async()=>{
 const attack='<img src=x onerror="window.pwned=true"><script>window.pwned=true</script>';
 const {win,root,cleanup}=await notice({title:attack.slice(0,80),text:attack});
 await settle();
 const check=()=>{assert.equal(root.querySelector('img'),null);assert.equal(root.querySelector('script'),null);assert.equal(win.pwned,undefined);};
 check();assert.ok(root.querySelector('#id-cookie-notice').textContent.includes('<img src=x'));
 win.document.querySelector('.festapp-consent-fab').click();await settle();check();cleanup();win.close();
});

test('form design is used only while text and buttons stay readable',async()=>{
 const design='--card-bg:#102030;--text-color:#ffffff;--primary-color:#ffcc00;--btn-text-color:#000000;--font-family-base:Lato';
 const branded=await notice({},design);
 for(const value of ['--notice-surface:#102030','--notice-text:#ffffff','--notice-primary:#ffcc00','--notice-button:#000000'])assert.ok(branded.css.includes(value),value);
 assert.ok(branded.css.includes('font-family:var(--font-family-base,inherit)'));branded.cleanup();branded.win.close();
 for(const unreadable of ['--card-bg:#ffffff;--text-color:#eeeeee;--primary-color:#ffcc00;--btn-text-color:#000000','--card-bg:#ffffff;--text-color:#000000;--primary-color:#ffcc00;--btn-text-color:#ffffff','--card-bg:#fff;--text-color:#000;--primary-color:rgb(0,0,0)}body{display:none;--btn-text-color:#fff','']) {
  const value=await notice({},unreadable);
  assert.ok(value.css.includes('--notice-primary:#4465a6'),unreadable);assert.ok(value.css.includes('--notice-button:#fff'));value.cleanup();value.win.close();
 }
});

test('CMP cleanup before choosing restores scroll, and storage failure fails closed',async()=>{
 for (const broken of [false,true]) {
  const dom=new JSDOM('<html lang="cs"><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
  const win=dom.window, grants=[];
  try {
   win.eval(bundle.outputFiles[0].text);
   if(broken)Object.defineProperty(win.document,'cookie',{get(){throw Error('storage blocked');}});
   const cleanup=win.startFixture(JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url))),{setConsent:value=>grants.push(plain(value))});
   await settle();
   if(broken)assert.equal(grants.at(-1),null,'unavailable CMP is reported for session recovery');
   if(!broken){win.document.querySelector('.cn-decline').click();await settle();assert.deepEqual(grants.at(-1),none);assert.equal(win.document.body.style.overflow,'');}
   cleanup();assert.equal(win.document.body.style.overflow,'');assert.equal(grants.at(-1),false);
   assert.equal(win.document.querySelector('#festapp-measurement-consent'),null);
  } finally {win.close();}
 }
});

for (const value of ['https://organizer.example/privacy?lang=cs', '', null,
 'javascript:alert(1)', 'data:text/plain,x', 'http://example.com', '/privacy',
 'https://user:pass@example.com', 'https://@example.com', 'https://example.com:99999',
 'https://example.com/' + 'x'.repeat(2048)]) test(`CMP privacy link: ${value?.slice(0,60)}`, async () => {
 const dom = new JSDOM('<html lang="en"><body><main></main></body></html>', {
  url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 try {
  dom.window.eval(bundle.outputFiles[0].text);
  const grants=[];let started=0;
  const cleanup = dom.window.startFixture(JSON.parse(readFileSync(new URL('../../../assets/translations/en.json', import.meta.url))), {setConsent(value){grants.push(value);},start(){started++;}}, value);
  await settle();
  if (value === 'https://organizer.example/privacy?lang=cs') {
   assert.equal(dom.window.document.querySelector('#festapp-measurement-consent a').getAttribute('href'),value);
  } else {
   assert.equal(dom.window.document.querySelector('#festapp-measurement-consent'),null);
   assert.equal(dom.window.document.querySelector('main').children.length,0);
   assert.equal(dom.window.document.querySelector('.festapp-consent-fab'),null);
   assert.equal(dom.window.document.querySelector('iframe'),null);
   assert.equal(dom.window.document.body.style.overflow,'');
   assert.equal(dom.window.document.documentElement.style.overflow,'');
   assert.deepEqual(grants,[]);assert.equal(started,0,'without a valid policy link nothing starts');
  }
  cleanup();
 } finally { dom.window.close(); }
});

function assertNecessary(root, strings) {
 const row=root.querySelector('.festapp-necessary');
 assert.ok(row.textContent.includes(strings.measurementConsentNecessary));
 assert.ok(row.textContent.includes(strings.measurementConsentNecessaryDescription));
 // Informational row: always active, no control that could look like a choice.
 assert.equal(row.querySelector('input'),null);
 assert.equal(row.querySelector('.festapp-always').textContent,strings.measurementConsentAlwaysActive);
 assert.equal(row.parentNode.firstElementChild,row,'necessary row is listed first');
}
for (const layout of ['bar','modal']) test(`notice settings opens choices without granting; ${layout}`,async()=>{
 const {win,root,grants,cleanup}=await notice({layout});
 try {
  const settings=root.querySelector('.cm-btn-lern-more');
  assert.equal(settings.textContent,'Nastavení');assert.equal(settings.type,'button');
  settings.focus();assert.equal(win.document.activeElement,settings);
  settings.click();await settle();
  assertNecessary(root,cs().FeatureFormSettings);
  assert.equal(root.querySelector('#service-item-analytics').checked,false);
  assert.equal(root.querySelector('#service-item-marketing').checked,false);
  assert.deepEqual(grants.at(-1),none);
  assert.equal(win.document.body.style.overflow,'hidden');
  root.querySelector('#service-item-marketing').click();await settle();
  assert.deepEqual(grants.at(-1),none);
  root.querySelector('.cm-btn-accept').click();await settle();
  assert.deepEqual(grants.at(-1),{analytics:false,marketing:true});
  assert.equal(win.document.body.style.overflow,'');
  assert.deepEqual(savedCookie(win),{analytics:false,marketing:true});
 } finally {cleanup();win.close();}
});
function savedCookie(win) {
 const value=win.document.cookie.split('; ').find(c=>c.startsWith('festapp-measurement-1-2-a='));
 return JSON.parse(decodeURIComponent(value.slice(value.indexOf('=')+1)));
}
for(const action of ['decline','accept','save']) test(`necessary row preserves stored ${action} choice`,async()=>{
 const {win,root,grants,cleanup}=await notice();
 try {
  if(action==='save') {root.querySelector('.cm-btn-lern-more').click();await settle();assertNecessary(root,cs().FeatureFormSettings);root.querySelector('.cm-btn-accept').click();}
  else root.querySelector(action==='decline'?'.cn-decline':'.cm-btn-success').click();
  await settle();const expected=action==='accept'?both:none;
  assert.deepEqual(grants.at(-1),expected);assert.deepEqual(savedCookie(win),expected);
  cleanup();
  const again=win.startFixture(cs(),{setConsent:value=>grants.push(plain(value))});await settle();
  assert.equal(win.document.querySelector('.cookie-modal-notice'),null);
  assert.deepEqual(grants.at(-1),expected);again();
 } finally {cleanup();win.close();}
});
for(const lang of ['cs','en','de','pl','sk','uk']) test(`measurement defaults mirrored in ${lang}`,()=>{
 const canonical=JSON.parse(readFileSync(new URL(`../../../assets/translations/${lang}.json`,import.meta.url))).FeatureFormSettings;
 const published=JSON.parse(readFileSync(new URL(`../../public/assets/translations/${lang}.json`,import.meta.url))).FeatureFormSettings;
 for(const key of Object.keys(canonical).filter(k=>k.startsWith('measurementConsent')))assert.equal(published[key],canonical[key],key);
});

function key(win, target, value, shiftKey=false) {
 target.dispatchEvent(new win.KeyboardEvent('keydown',{key:value,shiftKey,bubbles:true,cancelable:true}));
}
function assertDialog(win, layer) {
 assert.equal(layer.getAttribute('role'),'dialog');
 assert.equal(layer.getAttribute('aria-modal'),'true');
 assert.ok(win.document.getElementById(layer.getAttribute('aria-labelledby'))?.textContent);
}
test('both layers isolate the page, hide the floating button and contain Tab focus',async()=>{
 const {win,root,cleanup}=await notice();
 try {
  const main=win.document.querySelector('main'),fab=win.document.querySelector('.festapp-consent-fab');
  const preserved=win.document.createElement('aside');preserved.setAttribute('inert','original');win.document.body.append(preserved);
  const added=win.document.createElement('section');win.document.body.append(added);await settle();
  const layer=root.querySelector('.cookie-modal-notice');assertDialog(win,layer);
  assert.equal(layer.tabIndex,-1);assert.equal(layer.hasAttribute('autofocus'),false);
  assert.equal(win.document.activeElement,layer,'the notice itself takes focus without a ring on the link');
  key(win,layer,'Tab');assert.equal(win.document.activeElement,root.querySelector('a'));
  assert.equal(main.hasAttribute('inert'),true);assert.equal(added.hasAttribute('inert'),true);assert.equal(fab.hidden,true);
  const settings=root.querySelector('.cm-btn-lern-more');settings.focus();key(win,settings,'Tab');
  assert.equal(win.document.activeElement,root.querySelector('a'));
  key(win,win.document.activeElement,'Tab',true);assert.equal(win.document.activeElement,settings);
  settings.click();await settle();
  const modal=root.querySelector('.cm-modal');assertDialog(win,modal);
  const save=modal.querySelector('.cm-btn-accept');save.focus();key(win,save,'Tab');assert.equal(win.document.activeElement,modal.querySelector('.hide'));
  key(win,win.document.activeElement,'Tab',true);assert.equal(win.document.activeElement,save);
  assert.equal(main.hasAttribute('inert'),true);assert.equal(fab.hidden,true);
  save.click();await settle();assert.equal(main.hasAttribute('inert'),false);assert.equal(added.hasAttribute('inert'),false);
  assert.equal(preserved.getAttribute('inert'),'original');assert.equal(fab.hidden,false);
  fab.click();await settle();assert.equal(main.hasAttribute('inert'),true);assert.equal(fab.hidden,true);
  cleanup();assert.equal(main.hasAttribute('inert'),false);assert.equal(preserved.getAttribute('inert'),'original');
 } finally {cleanup();win.close();}
});
test('purpose switches remain keyboard operable after changes and Klaro re-renders',async()=>{
 const {win,root,cleanup,css}=await notice();
 try {
  root.querySelector('.cm-btn-lern-more').click();await settle();
  for(const name of ['analytics','marketing']) {
   const input=root.querySelector(`#service-item-${name}`);assert.equal(input.tabIndex,0);
   input.focus();key(win,input,' ');await settle();assert.equal(input.checked,true);assert.equal(input.tabIndex,0);
   key(win,input,' ');await settle();assert.equal(input.checked,false);
   input.tabIndex=-1;await settle();assert.equal(input.tabIndex,0,'repairs Klaro tabindex on re-render');
  }
  assert.match(css,/:focus-visible \+ \.cm-list-label \.slider \{outline:2px/);
  assert.match(css,/\.cm-switch \.slider \{[^}]*background:color-mix\(in srgb,var\(--notice-text\) 55%,var\(--notice-surface\)\)/,'off track stays readable but distinct from the on state');
 } finally {cleanup();win.close();}
});
for(const confirmed of [false,true]) test(`Escape cancels draft and returns focus, confirmed=${confirmed}`,async()=>{
 const {win,root,cleanup,grants}=await notice();
 try {
  if(confirmed){root.querySelector('.cm-btn-success').click();await settle();}
  let opener=confirmed?win.document.querySelector('.festapp-consent-fab'):root.querySelector('.cm-btn-lern-more');
  opener.focus();opener.click();await settle();
  root.querySelector('#service-item-analytics').click();await settle();
  const cookie=win.document.cookie;
  key(win,win.document.activeElement,'Escape');await settle();
  assert.equal(root.querySelector('.cm-modal'),null);
  assert.equal(!!root.querySelector('.cookie-modal-notice'),!confirmed);
  assert.equal(win.document.cookie,cookie,'Escape never persists the draft');
  if(!confirmed)assert.equal(win.document.cookie,'');
  opener=confirmed?opener:root.querySelector('.cm-btn-lern-more');assert.equal(win.document.activeElement,opener);
  assert.deepEqual(grants.at(-1),confirmed?both:none,'cancel restores the saved consent');
  opener.click();await settle();assert.equal(root.querySelector('#service-item-analytics').checked,confirmed,'cancel restores switch state');
  root.querySelector('.hide').click();await settle();assert.equal(win.document.activeElement,confirmed?opener:root.querySelector('.cm-btn-lern-more'));
 } finally {cleanup();win.close();}
});
test('light primary retains filled buttons and uses readable text for outlines, links and switches',async()=>{
 const {win,css,cleanup}=await notice({},'--card-bg:#ffffff;--text-color:#222222;--primary-color:#ffd400;--btn-text-color:#000000');
 try {
  for(const value of ['--notice-primary:#ffd400','--notice-button:#000000','--notice-accent:#222222'])assert.ok(css.includes(value),value);
  assert.match(css,/a \{color:var\(--notice-accent\);text-decoration:underline;text-underline-offset:2px/);
  assert.match(css,/\.cm-btn-lern-more \{[^}]*color:var\(--notice-accent\)/);
  assert.match(css,/\.cm-btn-accept \{[^}]*color:var\(--notice-accent\)/);
  assert.match(css,/:checked \+ \.cm-list-label \.slider \{background:var\(--notice-accent\)/);
  assert.match(css,/\.cm-header \.hide \{[^}]*width:44px;height:44px/);
 } finally {cleanup();win.close();}
});
for(const [lang,label,phrase] of [
 ['cs','Přijmout vše','k měření a personalizované reklamě'],['en','Accept all','for analytics and personalised advertising'],
 ['de','Alle akzeptieren','für Analysen und personalisierte Werbung'],['pl','Akceptuj wszystkie','do analityki i reklamy spersonalizowanej'],
 ['sk','Prijať všetko','na meranie a personalizovanú reklamu'],['uk','Прийняти все','для аналітики та персоналізованої реклами'],
]) test(`dialog footer follows visual order and distinguishes accept all in ${lang}`,async()=>{
 const translations=JSON.parse(readFileSync(new URL(`../../../assets/translations/${lang}.json`,import.meta.url)));
 const strings=translations.FeatureFormSettings;
 const dom=new JSDOM(`<html lang="${lang}"><head></head><body><main></main></body></html>`,{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window;let cleanup;
 try {
  win.eval(bundle.outputFiles[0].text);cleanup=win.startFixture(translations,{setConsent(){}});await settle();
  const root=win.document.querySelector('#festapp-measurement-consent');
  assert.ok(root.textContent.includes(phrase));assert.equal(root.querySelector('.cm-btn-success').textContent,strings.measurementConsentAccept);
  root.querySelector('.cm-btn-lern-more').click();await settle();
  const footer=root.querySelector('.cm-footer-buttons');
  assert.deepEqual([...footer.querySelectorAll('button')].map(b=>b.textContent),[strings.measurementConsentDecline,label,strings.measurementConsentSave]);
  root.querySelector('#service-item-analytics').click();await settle();
  assert.deepEqual([...footer.querySelectorAll('button')].map(b=>b.textContent),[strings.measurementConsentDecline,label,strings.measurementConsentSave]);
 } finally {cleanup?.();win.close();}
});


test('first settings save focuses the floating button and reopened Decline saves denial',async()=>{
 const {win,root,grants,cleanup}=await notice({layout:'modal'});
 try {
  root.querySelector('.cm-btn-lern-more').click();await settle();
  root.querySelector('#service-item-analytics').click();
  root.querySelector('#service-item-marketing').click();
  root.querySelector('.cm-btn-accept').click();await settle();
  assert.deepEqual(grants.at(-1),both);
  const fab=win.document.querySelector('.festapp-consent-fab');
  assert.equal(fab.hidden,false);assert.equal(win.document.activeElement,fab);
  fab.click();await settle();
  const decline=root.querySelector('.cm-modal .cn-decline');
  assert.ok(decline);decline.click();await settle();
  assert.deepEqual(grants.at(-1),none);assert.equal(win.document.activeElement,fab);
  assert.equal(root.querySelector('.cm-modal'),null);
 } finally {cleanup();win.close();}
});

for (const layout of ['bar','modal']) test(`Decline during confirmation persists across a page reload; ${layout}`,async()=>{
 const {win,root,grants,cleanup}=await notice({layout});
 let reloaded;
 try {
  root.querySelector('.cm-btn-lern-more').click();await settle();
  root.querySelector('.cm-btn-accept-all').click();await settle();
  assert.equal(root.querySelector('.cm-btn-accept').disabled,true);
  assert.deepEqual(savedCookie(win),both);
  root.querySelector('.cm-modal .cn-decline').click();await settle();
  assert.deepEqual(grants.at(-1),none);
  assert.deepEqual(savedCookie(win),none);
  assert.equal(root.querySelector('.cm-modal'),null);
  const fab=win.document.querySelector('.festapp-consent-fab');
  assert.equal(win.document.activeElement,fab);
  assert.equal(win.document.body.style.overflow,'');
  assert.equal(win.document.querySelector('main').hasAttribute('inert'),false);
  await new Promise(resolve=>setTimeout(resolve,850));
  assert.deepEqual(savedCookie(win),none,'the pending confirmation cannot restore the earlier choice');
  reloaded=new JSDOM('<html lang="cs"><body><main></main></body></html>',{
   url:win.location.href,runScripts:'outside-only',pretendToBeVisual:true,
  });
  // Transfer the browser cookie into a fresh realm with a new Klaro manager.
  reloaded.window.document.cookie=win.document.cookie;
  reloaded.window.eval(bundle.outputFiles[0].text);
  const restored=[];
  const stop=reloaded.window.startFixture(cs(),{setConsent:value=>restored.push(plain(value))});
  await settle();
  assert.deepEqual(restored.at(-1),none);
  assert.equal(reloaded.window.document.querySelector('.cookie-modal-notice'),null);
  stop();
 } finally {cleanup();win.close();reloaded?.window.close();}
});

test('central notice Escape keeps choice pending and focuses the notice',async()=>{
 const {win,root,grants,cleanup}=await notice({layout:'modal'});
 try {
  root.querySelector('a').focus();
  const event=new win.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true});
  win.document.activeElement.dispatchEvent(event);await settle();
  assert.equal(event.defaultPrevented,true);
  assert.equal(win.document.activeElement,root.querySelector('.cookie-modal-notice'));
  assert.equal(win.document.body.style.overflow,'hidden');
  assert.deepEqual(grants.at(-1),none);assert.equal(win.document.cookie,'');
 } finally {cleanup();win.close();}
});

test('description and header text keep full opacity at the minimum contrast palette',async()=>{
 const {win,root,cleanup}=await notice({},'--card-bg:#ffffff;--text-color:#767676;--primary-color:#000000;--btn-text-color:#ffffff');
 try {
  root.querySelector('.cm-btn-lern-more').click();await settle();
  for(const node of root.querySelectorAll('.cm-list-description,.cm-header p')) {
   const opacity=win.getComputedStyle(node).opacity;
   assert.ok(opacity==='' || Number(opacity)===1,opacity);
  }
 } finally {cleanup();win.close();}
});

test('floating settings reserve clearance for focused form controls and clean up',async()=>{
 const {win,cleanup}=await notice({});
 const css=readFileSync(new URL('../../src/components/forms/form_component.css',import.meta.url),'utf8');
 assert.match(css,/body\.festapp-consent-space\s*\{[^}]*padding-bottom:76px/);
 assert.match(css,/scroll-padding-bottom:76px/);assert.match(css,/scroll-margin-bottom:76px/);
 assert.ok(win.document.body.classList.contains('festapp-consent-space'));
 cleanup();assert.equal(win.document.body.classList.contains('festapp-consent-space'),false);win.close();
});

test('linked choice uses real Klaro persistence, floating settings and local revocation',async()=>{
 const dom=new JSDOM('<html lang="cs"><body><main></main></body></html>',{url:'https://tickets.example/form/test',referrer:'https://organizer.example/event',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window, grants=[],requests=[];
 win.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';win.opener={postMessage:(data,origin)=>requests.push({data,origin})};
 const translations=JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
 try {
  const peer=win.opener;
  win.eval(bundle.outputFiles[0].text);
  let cleanup=win.startFixture(translations,{setConsent:g=>grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://organizer.example']);
  assert.equal(requests.length,1);
  win.dispatchEvent(new win.MessageEvent('message',{source:peer,origin:'https://organizer.example',data:{namespace:'festapp-consent-link',protocol:1,type:'response',nonce:requests[0].data.nonce,analytics:true,marketing:true}}));
  await settle();assert.deepEqual(grants.at(-1),both);assert.equal(win.document.body.style.overflow,'');
  assert(win.document.cookie.includes('festapp-measurement-1-2-a='));assert(win.document.cookie.includes('-source='));
  assert.equal(win.document.querySelector('[data-festapp-consent-imported]'),null);
  const fab=win.document.querySelector('.festapp-consent-fab');assert.equal(fab.hidden,false);
  assert.equal(win.document.querySelector('.cookie-modal-notice'),null);
  fab.click();await settle();
  const root=win.document.querySelector('#festapp-measurement-consent');root.querySelector('#service-item-analytics').click();root.querySelector('#service-item-marketing').click();root.querySelector('.cm-btn-accept').click();await settle();
  assert.deepEqual(grants.at(-1),none);assert.equal(win.document.querySelector('[data-festapp-consent-imported]'),null);assert(!win.document.cookie.includes('-source='));
  cleanup();cleanup=win.startFixture(translations,{setConsent:g=>grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://organizer.example']);
  await settle();assert.equal(requests.length,1,'saved local choice prevents a new import');assert.deepEqual(grants.at(-1),none);cleanup();
 } finally {win.close();}
});

// Each realm creates its own real Klaro manager; the cookie jar is shared just
// like two tabs on the same product origin.
function linkedTab(cookieJar) {
 const dom=new JSDOM('<html lang="cs"><body style="overflow:auto"><main></main></body></html>',{url:'https://tickets.example/form/test',referrer:'https://organizer.example/event',cookieJar,runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window,requests=[],grants=[];
 const peer={postMessage:data=>requests.push(data)};win.name='festapp-consent-link-00000000-0000-0000-0000-000000000000';win.opener=peer;
 win.eval(bundle.outputFiles[0].text);
 return {win,requests,grants,unknown:()=>win.dispatchEvent(new win.MessageEvent('message',{source:peer,origin:'https://organizer.example',data:{namespace:'festapp-consent-link',protocol:1,type:'response',nonce:requests.at(-1)?.nonce,choice:null}})),start:()=>win.startFixture(cs(),{setConsent:g=>grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://organizer.example']),reply:(analytics=true,marketing=false)=>win.dispatchEvent(new win.MessageEvent('message',{source:peer,origin:'https://organizer.example',data:{namespace:'festapp-consent-link',protocol:1,type:'response',nonce:requests.at(-1)?.nonce,analytics,marketing}})),close:()=>win.close()};
}
test('pending exchange has no blocking notice or scroll lock, timeout restores notice',async()=>{
 const f=linkedTab();let expire;
 const original=f.win.setTimeout.bind(f.win);
 f.win.setTimeout=(fn,ms,...args)=>ms===1500?(expire=fn,123):original(fn,ms,...args);
 try{
  const cleanup=f.start();await settle();assert.equal(f.win.document.querySelector('.cookie-modal-notice'),null);assert.equal(f.win.document.body.style.overflow,'auto');
  expire();await settle();assert.ok(f.win.document.querySelector('.cookie-modal-notice'));assert.equal(f.win.document.body.style.overflow,'hidden');assert.equal(f.win.opener,null);cleanup();
 }finally{f.close();}
});
test('new local choice in another Klaro instance takes precedence over pending import',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar();
 const a=linkedTab(jar),b=linkedTab(jar);
 try{
  const cleanA=a.start();b.win.opener=null;const cleanB=b.start();await settle();
  b.win.document.querySelector('.cn-decline').click();await settle();
  a.reply(true,true);await settle();assert.deepEqual(a.grants.at(-1),none);assert.equal(a.win.opener,null);
  assert.equal(a.win.document.querySelector('[data-festapp-consent-imported]'),null);
  cleanA();cleanB();
 }finally{a.close();b.close();}
});
test('import cookies are session-only, refresh from host, and disappear after session ends',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar();
 const a=linkedTab(jar);
 try{
  const cleanup=a.start();a.reply();await settle();
  const cookies=jar.getCookiesSync('https://tickets.example');assert.equal(cookies.length,2);
  for(const cookie of cookies)assert.equal(cookie.expires,'Infinity',cookie.key);
  assert.deepEqual(a.grants.at(-1),{analytics:true,marketing:false});
  assert.equal(a.win.document.querySelector('.festapp-consent-fab').hidden,false);
  assert.equal(a.win.document.querySelector('[data-festapp-consent-imported]'),null);
  cleanup();
  const b=linkedTab(jar);try{const clean=b.start();assert.equal(b.requests.length,1);b.reply(false,false);await settle();assert.deepEqual(b.grants.at(-1),none);clean();}finally{b.close();}
  // Ending the browser cookie session discards all session cookies.
  jar.removeAllCookiesSync();const c=linkedTab(jar);c.win.opener=null;
  try{const clean=c.start();await settle();assert.deepEqual(c.grants.at(-1),none);assert.ok(c.win.document.querySelector('.cookie-modal-notice'));clean();}finally{c.close();}
 }finally{a.close();}
});
test('legacy persistent import is discarded while a local choice remains persistent',async()=>{
 const f=linkedTab();
 try{
  f.win.opener=null;
  f.win.document.cookie='festapp-measurement-1-2-a='+encodeURIComponent(JSON.stringify(both))+'; Path=/; Max-Age=15552000';
  f.win.document.cookie='festapp-measurement-1-2-a-source='+encodeURIComponent(JSON.stringify({origin:'https://organizer.example',importedAt:Date.now()}))+'; Path=/; Max-Age=15552000';
  const clean=f.start();await settle();assert.deepEqual(f.grants.at(-1),none);assert.ok(f.win.document.querySelector('.cookie-modal-notice'));
  f.win.document.querySelector('.cm-btn-success').click();await settle();assert.deepEqual(f.grants.at(-1),both);assert(!f.win.document.cookie.includes('-source='));clean();
 }finally{f.close();}
});
test('saving locally replaces session expiry with 180 days and survives session end',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{
  const clean=a.start();a.reply();await settle();
  a.win.document.querySelector('.festapp-consent-fab').click();await settle();
  a.win.document.querySelector('.cm-btn-accept').click();await settle();
  const cookies=jar.getCookiesSync('https://tickets.example');assert.equal(cookies.length,1);assert.notEqual(cookies[0].expires,'Infinity');
  assert.ok(cookies[0].expires.getTime()>Date.now()+179*86400000);clean();
  const b=linkedTab(jar);b.win.opener=null;
  try{const cleanB=b.start();await settle();assert.deepEqual(b.grants.at(-1),{analytics:true,marketing:false});assert.equal(b.win.document.querySelector('.cookie-modal-notice'),null);cleanB();}finally{b.close();}
 }finally{a.close();}
});

for (const response of ['timeout','unknown','refusal']) test(`old imported grant stays denied during refresh and after ${response}`,async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{
  const cleanA=a.start();a.reply(true,true);await settle();assert.deepEqual(a.grants.at(-1),both);cleanA();
  const b=linkedTab(jar);let expire;const timer=b.win.setTimeout.bind(b.win);
  b.win.setTimeout=(fn,ms,...args)=>ms===1500?(expire=fn,123):timer(fn,ms,...args);
  try{
   const cleanB=b.start();await settle();assert.ok(b.grants.length);assert.ok(b.grants.every(g=>!g || (!g.analytics && !g.marketing)));
   assert.equal(b.win.document.querySelector('[data-festapp-consent-imported]'),null);
   if(response==='timeout')expire();
   else if(response==='refusal')b.reply(false,false);
   else b.unknown();
   await settle();assert.deepEqual(b.grants.at(-1),none);
   if(response!=='refusal'){assert.ok(b.win.document.querySelector('.cookie-modal-notice'));assert.ok(!b.win.document.cookie.includes('-source='));}
   cleanB();
  }finally{b.close();}
 }finally{a.close();}
});
test('24 hour imported choice expires even when browser session cookies survive',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{
  const cleanA=a.start();a.reply(true,true);await settle();cleanA();
  const b=linkedTab(jar);b.win.opener=null;
  b.win.document.cookie='festapp-measurement-1-2-a-source='+encodeURIComponent(JSON.stringify({origin:'https://organizer.example',session:true,importedAt:Date.now()-86400001}))+'; Path=/';
  try{const cleanB=b.start();await settle();assert.ok(b.grants.every(g=>!g || !g.analytics && !g.marketing));assert.ok(b.win.document.querySelector('.cookie-modal-notice'));assert.ok(!b.win.document.cookie.includes('-source='));cleanB();}finally{b.close();}
 }finally{a.close();}
});
for(const enabled of [false,undefined])test(`organizer switch ${enabled} keeps normal CMP`,async()=>{
 const f=linkedTab();try{const clean=f.win.startFixture(cs(),{setConsent:g=>f.grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://organizer.example'],enabled===undefined?null:enabled);await settle();assert.equal(f.requests.length,0);assert.ok(f.win.document.querySelector('.cookie-modal-notice'));assert.equal(f.win.opener,null);clean();}finally{f.close();}
});

test('direct reload without a new peer retains an unexpired import',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{const cleanA=a.start();a.reply(true,true);await settle();cleanA();const b=linkedTab(jar);b.win.opener=null;
  try{const cleanB=b.start();await settle();assert.equal(b.requests.length,0);assert.deepEqual(b.grants.at(-1),both);assert.equal(b.win.document.querySelector('.festapp-consent-fab').hidden,false);assert.equal(b.win.document.querySelector('[data-festapp-consent-imported]'),null);cleanB();}finally{b.close();}
 }finally{a.close();}
});
test('an import from a website no longer approved is revoked on the next load',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{const cleanA=a.start();a.reply(true,true);await settle();assert.equal(a.win.document.querySelector('.festapp-consent-fab').hidden,false);
  const change=a.win.document.querySelector('.festapp-consent-fab');assert.ok(change.getAttribute('aria-label'),'Change has an accessible name');cleanA();
  const b=linkedTab(jar);b.win.opener=null;
  try{const cleanB=b.win.startFixture(cs(),{setConsent:g=>b.grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://other.example']);await settle();
   assert.equal(b.win.document.querySelector('[data-festapp-consent-imported]'),null);
   assert.ok(b.win.document.querySelector('.cookie-modal-notice'),'the normal notice asks again');
   assert.notDeepEqual(b.grants.at(-1),{analytics:true,marketing:true});cleanB();}finally{b.close();}
 }finally{a.close();}
});
test('an import from a removed website never reaches the transport on the next load',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);
 try{const cleanA=a.start();a.reply(true,true);await settle();cleanA();
  const b=linkedTab(jar);b.win.opener=null;
  try{const cleanB=b.win.startFixture(cs(),{setConsent:g=>b.grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://other.example']);await settle();
   assert.ok(!b.grants.some(g=>g&&g.analytics&&g.marketing),'no intermediate grant from the stale import');cleanB();}finally{b.close();}
 }finally{a.close();}
});
test('an expiry timer of an old import keeps a newer local choice from another tab',async()=>{
 const {CookieJar}=await import('jsdom');const jar=new CookieJar(),a=linkedTab(jar);let expire;
 const original=a.win.setTimeout.bind(a.win);a.win.setTimeout=(fn,ms,...args)=>ms>3600000?(expire=fn,999):original(fn,ms,...args);
 try{const cleanA=a.start();a.reply(true,true);await settle();assert.equal(typeof expire,'function');
  const b=linkedTab(jar);b.win.opener=null;
  try{const cleanB=b.win.startFixture(cs(),{setConsent:g=>b.grants.push(plain(g))},'https://organizer.example/privacy',undefined,['https://organizer.example']);await settle();
   b.win.document.querySelector('.festapp-consent-fab').click();await settle();
   b.win.document.querySelector('.cn-decline, .cm-btn-decline').click();await settle();
   const saved=()=>b.win.document.cookie.split('; ').find(c=>c.startsWith('festapp-measurement-1-2-a='));
   const before=saved();assert.ok(before,'local decline saved');
   expire();await settle();
   assert.equal(saved(),before,'the old timer must not reset the newer local choice');cleanB();}finally{b.close();}
  cleanA();
 }finally{a.close();}
});
test('floating settings after import gets focus back after Escape',async()=>{
 const f=linkedTab();try{const clean=f.start();f.reply(true,false);await settle();
  const change=f.win.document.querySelector('.festapp-consent-fab');change.focus();change.click();await settle();
  assert.ok(f.win.document.querySelector('.cm-modal'));
  const metadata=f.win.document.cookie.split('; ').find(c=>c.includes('-source='));
  f.win.document.querySelector('#service-item-analytics').click();
  f.win.document.dispatchEvent(new f.win.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));await settle();
  assert.equal(f.win.document.activeElement,change,'focus returns to the floating settings button');
  assert.equal(change.hidden,false);assert.equal(f.win.document.querySelector('.cookie-modal-notice'),null);
  assert.equal(f.win.document.cookie.split('; ').find(c=>c.includes('-source=')),metadata,'Escape preserves import metadata');
  assert.deepEqual(f.grants.at(-1),{analytics:true,marketing:false},'Escape discards the draft');clean();
 }finally{f.close();}
});
