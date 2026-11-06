import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {JSDOM} from 'jsdom';

const bundle = await build({stdin:{contents:`
import {startMeasurementConsent} from './src/components/forms/form_measurement_cmp.js';
import {LocalizationService} from './src/services/localization_service.js';
window.startFixture = (translations, transport, privacy_url = 'https://organizer.example/privacy') => {
 LocalizationService.translations = translations;
 return startMeasurementConsent({model:{data:{analytics:{organization:1,unit:2,privacy_url}}},transport,host:document.querySelector('main')});
};`,resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
const settle=()=>new Promise(resolve=>setTimeout(resolve,30));
for (const lang of ['cs','sk','en','de','pl','uk']) test(`actual Klaro first choice and saved settings in ${lang}`,async()=>{
 const translations=JSON.parse(readFileSync(new URL(`../../../assets/translations/${lang}.json`,import.meta.url)));
 const strings=translations.FeatureFormSettings;
 const dom=new JSDOM(`<html lang="${lang}"><head></head><body style="overflow:auto"><main></main></body></html>`,{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
 const win=dom.window, grants=[];
 try {
  win.eval(bundle.outputFiles[0].text);
  const cleanup=win.startFixture(translations,{setConsent:granted=>grants.push(granted)});
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
  root.querySelector('.cm-btn-success').click();await settle();
  assert.equal(grants.at(-1),true);assert.equal(win.document.body.style.overflow,'auto');
  win.document.querySelector('main button').click();await settle();
  assert(!/<tr-|počítače/.test(root.textContent));
  let checkbox=root.querySelector('input[type=checkbox]');assert.equal(checkbox.checked,true);
  checkbox.click();await settle();assert.equal(grants.at(-1),false,'unsaved denial fails closed');
  root.querySelector('.cm-btn-accept').click();await settle();assert.equal(grants.at(-1),false);
  win.document.querySelector('main button').click();await settle();
  checkbox=root.querySelector('input[type=checkbox]');assert.equal(checkbox.checked,false);
  checkbox.click();await settle();assert.equal(grants.at(-1),false,'draft grant is not saved consent');
  root.querySelector('.cm-btn-accept').click();await settle();assert.equal(grants.at(-1),true);
  cleanup();assert.equal(win.document.body.style.overflow,'auto');assert.equal(grants.at(-1),false);
 } finally { win.close(); }
});
test('CMP cleanup before choosing restores scroll, and storage failure fails closed',async()=>{
 for (const broken of [false,true]) {
  const dom=new JSDOM('<html lang="cs"><body><main></main></body></html>',{url:'https://tickets.example/form/summer',runScripts:'outside-only',pretendToBeVisual:true});
  const win=dom.window, grants=[];
  try {
   win.eval(bundle.outputFiles[0].text);
   if(broken)Object.defineProperty(win.document,'cookie',{get(){throw Error('storage blocked');}});
   const cleanup=win.startFixture(JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url))),{setConsent:value=>grants.push(value)});
   await settle();
   if(!broken){win.document.querySelector('.cn-decline').click();await settle();assert.equal(grants.at(-1),false);assert.equal(win.document.body.style.overflow,'');}
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
  const grants=[];
  const cleanup = dom.window.startFixture(JSON.parse(readFileSync(new URL('../../../assets/translations/en.json', import.meta.url))), {setConsent(value){grants.push(value);}}, value);
  await settle();
  if (value === 'https://organizer.example/privacy?lang=cs') {
   assert.equal(dom.window.document.querySelector('#festapp-measurement-consent a').getAttribute('href'),value);
  } else {
   assert.equal(dom.window.document.querySelector('#festapp-measurement-consent'),null);
   assert.equal(dom.window.document.querySelector('main').children.length,0);
   assert.equal(dom.window.document.querySelector('iframe'),null);
   assert.equal(dom.window.document.body.style.overflow,'');
   assert.equal(dom.window.document.documentElement.style.overflow,'');
   assert.deepEqual(grants,[false]);
  }
  cleanup();
 } finally { dom.window.close(); }
});
