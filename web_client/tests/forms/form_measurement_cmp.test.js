import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';

const bundle = await build({stdin:{contents:`
import {startMeasurementConsent} from './src/components/forms/form_measurement_cmp.js';
import {LocalizationService} from './src/services/localization_service.js';
window.startFixture = (translations, transport, privacy_url = 'https://organizer.example/privacy', consent_notice) => {
 LocalizationService.translations = translations;
 return startMeasurementConsent({model:{data:{analytics:{organization:1,unit:2,privacy_url,consent_notice}}},transport,host:document.querySelector('main')});
};`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
const settle=()=>new Promise(resolve=>setTimeout(resolve,30));
const none={analytics:false,marketing:false},both={analytics:true,marketing:true};
// Klaro runs in the JSDOM realm; compare plain values here.
const plain=value=>typeof value==='object'?{...value}:value;
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
  assert.deepEqual([...root.querySelectorAll('button')].map(b=>b.textContent),[strings.measurementConsentDecline,strings.measurementConsentAccept]);
  const buttons=[...root.querySelectorAll('button')];
  for(const property of ['backgroundColor','color','fontWeight','padding','minWidth'])
   assert.equal(win.getComputedStyle(buttons[0])[property],win.getComputedStyle(buttons[1])[property]);
  assert.equal(root.querySelectorAll('input').length,0);
  assert.equal(root.querySelectorAll('.hide').length,0);
  assert.equal(root.querySelector('a').textContent,strings.measurementConsentPrivacy);
  assert.equal(win.document.body.style.overflow,'hidden');
  const visibleText=[...root.querySelectorAll('p,h1,h2,button')].map(n=>n.textContent).join(' ');
  assert(!/<tr-|počítače/.test(visibleText));
  console.log(JSON.stringify({lang,text:visibleText,buttons:[...root.querySelectorAll('button')].map(b=>b.textContent)}));
  assert.deepEqual(grants.at(-1),none,'nothing is granted before a choice');
  root.querySelector('.cm-btn-success').click();await settle();
  assert.deepEqual(grants.at(-1),both);assert.equal(win.document.body.style.overflow,'auto');
  win.document.querySelector('main button').click();await settle();
  assert(!/<tr-|počítače|missing/.test(root.textContent));
  const toggle=name=>root.querySelector(`#service-item-${name}`);
  assert.equal(root.querySelectorAll('input[type=checkbox]').length,2,'one toggle per purpose, no toggle-all row');
  for(const text of [strings.measurementConsentService,strings.measurementConsentAnalyticsDescription,strings.measurementConsentMarketing,strings.measurementConsentMarketingDescription]) assert(root.textContent.includes(text),text);
  assert.equal(toggle('analytics').checked,true);assert.equal(toggle('marketing').checked,true);
  toggle('marketing').click();await settle();assert.deepEqual(grants.at(-1),{analytics:true,marketing:false},'unsaved denial fails closed');
  root.querySelector('.cm-btn-accept').click();await settle();assert.deepEqual(grants.at(-1),{analytics:true,marketing:false});
  win.document.querySelector('main button').click();await settle();
  assert.equal(toggle('marketing').checked,false);
  toggle('analytics').click();await settle();assert.deepEqual(grants.at(-1),none);
  toggle('marketing').click();await settle();assert.deepEqual(grants.at(-1),none,'draft grant is not saved consent');
  root.querySelector('.cm-btn-accept').click();await settle();assert.deepEqual(grants.at(-1),{analytics:false,marketing:true});
  cleanup();assert.equal(win.document.body.style.overflow,'auto');assert.equal(grants.at(-1),false);
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

test('the frame starts once, after the saved choice is known, and a choice stops nothing',async()=>{
 const dom=new JSDOM('<html lang="cs"><head></head><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window,log=[];win.eval(bundle.outputFiles[0].text);
 const cleanup=win.startFixture(cs(),{setConsent:value=>log.push(plain(value)),start:()=>log.push('start')});await settle();
 assert.deepEqual(log,[none,'start'],'denied state before the frame starts, without waiting for a choice');
 win.document.querySelector('.cn-decline').click();await settle();assert.equal(log.filter(x=>x==='start').length,1);assert.deepEqual(log.at(-1),none);
 cleanup();win.close();
 const broken=new JSDOM('<html lang="cs"><head></head><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 broken.window.eval(bundle.outputFiles[0].text);Object.defineProperty(broken.window.document,'cookie',{get(){throw Error('storage blocked');}});
 let started=0;broken.window.startFixture(cs(),{setConsent(){},start:()=>started++});await settle();assert.equal(started,1,'a broken CMP leaves denied state and measurement runs');broken.window.close();
});

test('both layouts are the same mandatory notice; bar is the default and only docks it',async()=>{
 for(const [consent_notice,docked] of [[undefined,true],[{layout:'bar'},true],[{layout:'unknown'},true],[{layout:'modal'},false]]) {
  const {win,root,css,grants,cleanup}=await notice(consent_notice);
  assert.equal(css.includes('bottom:0'),docked,JSON.stringify(consent_notice));
  assert.ok(root.querySelector('.cookie-modal-notice'));assert.ok(root.querySelector('.cm-bg'));assert.equal(root.querySelectorAll('.hide').length,0);
  assert.equal(win.document.body.style.overflow,'hidden');assert.deepEqual(grants.at(-1),none);
  root.querySelector('.cm-bg').click();await settle();assert.ok(root.querySelector('.cookie-modal-notice'),'the backdrop does not dismiss it');
  assert.deepEqual([...root.querySelectorAll('.cookie-modal-notice button')].map(b=>b.textContent),['Odmítnout','Přijmout']);
  cleanup();win.close();
 }
});

test('custom title and text replace the defaults; buttons, purposes and policy link stay fixed',async()=>{
 const strings=cs().FeatureFormSettings;
 const {win,root,cleanup}=await notice({layout:'bar',title:'Vlastní nadpis',text:'Vlastní {neznámé} {privacyPolicy} text'});
 assert.equal(root.querySelector('#id-cookie-title').textContent,'Vlastní nadpis');
 const text=root.querySelector('#id-cookie-notice').textContent;assert.match(text,/^Vlastní neznámé privacyPolicy text/);assert.ok(!text.includes(strings.measurementConsentDescription));
 assert.equal(root.querySelector('.cookie-modal-notice a').getAttribute('href'),'https://organizer.example/privacy');
 assert.equal(root.querySelector('.cookie-modal-notice a').textContent,strings.measurementConsentPrivacy);
 win.document.querySelector('main button').click();await settle();
 assert.ok(root.textContent.includes('Vlastní nadpis'));for(const key of ['measurementConsentService','measurementConsentMarketing','measurementConsentMarketingDescription'])assert.ok(root.textContent.includes(strings[key]),key);
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
 win.document.querySelector('main button').click();await settle();check();cleanup();win.close();
});

test('form design is used only while text and buttons stay readable',async()=>{
 const design='--card-bg:#102030;--text-color:#ffffff;--primary-color:#ffcc00;--btn-text-color:#000000;--font-family-base:Lato';
 const branded=await notice({},design);
 for(const value of ['--notice-surface:#102030','--notice-text:#ffffff','--notice-primary:#ffcc00','--notice-button:#000000'])assert.ok(branded.css.includes(value),value);
 assert.ok(branded.css.includes('font-family:var(--font-family-base,inherit)'));branded.cleanup();branded.win.close();
 for(const unreadable of ['--card-bg:#ffffff;--text-color:#eeeeee;--primary-color:#ffcc00;--btn-text-color:#000000','--card-bg:#ffffff;--text-color:#000000;--primary-color:#ffcc00;--btn-text-color:#ffffff','--card-bg:#fff;--text-color:#000;--primary-color:rgb(0,0,0)}body{display:none;--btn-text-color:#fff','']) {
  const value=await notice({},unreadable);
  assert.ok(value.css.includes('--notice-primary:var(--primary-color,#4465a6)'),unreadable);assert.ok(value.css.includes('--notice-button:#fff'));value.cleanup();value.win.close();
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
   assert.equal(dom.window.document.querySelector('iframe'),null);
   assert.equal(dom.window.document.body.style.overflow,'');
   assert.equal(dom.window.document.documentElement.style.overflow,'');
   assert.deepEqual(grants,[]);assert.equal(started,0,'without a valid policy link nothing starts');
  }
  cleanup();
 } finally { dom.window.close(); }
});
