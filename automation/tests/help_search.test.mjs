import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {articleSections} from '../release/help/search_index.mjs';
const directory = new URL('../release/help/', import.meta.url);
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(new URL('search_engine.js',directory),'utf8'),context);
const engine = context.FestappHelpSearchEngine;
const aliases = JSON.parse(fs.readFileSync(new URL('search_terms.json',directory)));
for (const locale of ['cs','en']) {
 const pages=JSON.parse(fs.readFileSync(new URL(locale==='cs'?'pages.json':'pages.en.json',directory)));
 const index=engine.prepare(pages.filter(p=>p.category).map(p=>({...p,url:'/napoveda/'+p.slug+'/',aliases:aliases[locale][p.id],sections:articleSections(fs.readFileSync(new URL((locale==='en'?'en/':'')+p.slug+'.html',directory),'utf8'))})));
 test(`${locale}: search ranks real article contents, spelling variants and category filters`,()=>{
  const cases=locale==='cs'?{'zmena ceny':'ticket-pricing','neprisly vstupenky':'orders','variabilni symbol':'unmatched-payment','spatny VS':'unmatched-payment','nesparovana platba':'unmatched-payment','splatnost':'payments','mistenky':'seating','Worpress':'wordpress','nastaveni banky':'bank-accounts','Fio API token':'fio-token','wizard':'getting-started','nastaveni skeneru':'scanner-settings'}:{'incorrect payment reference':'unmatched-payment','unmatched bank payment':'unmatched-payment','missing tickets':'orders','bank account':'bank-accounts','seating':'seating','Wordpres':'wordpress','Fio API token':'fio-token','setup wizard':'getting-started','scanner display settings':'scanner-settings'};
  for(const [query,id] of Object.entries(cases)) assert.equal(engine.search(index,query).results[0]?.id,id,query);
  assert.equal(engine.search(index,'q').results.length,0);
  assert.equal(engine.search(index,'zzqxxxqqzz').results.length,0);
  assert.ok(engine.search(index,'','tickets').results.every(p=>p.category==='tickets'));
  const deep=engine.search(index,locale==='cs'?'splatnost':'bank account').results[0];
  assert.match(deep.href,/#/,'content matches link to a relevant article section');
 });
}
test('index ignores code, interactive forms and media captions',()=>{
 const sections=articleSections('<p>Intro &amp; text</p><h2 id="step">Step</h2><p>Actual action</p><figure><p>Excluded caption</p></figure><script>secret()</script>');
 assert.equal(sections[0].text,'Intro & text');assert.equal(sections[1].text,'Actual action');assert.equal(sections[1].anchor,'step');
});
