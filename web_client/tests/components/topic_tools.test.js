import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {initTopicTools} from '../../src/marketing/topic_tools.js';

test('the published guide has working chapter destinations and a local, printable checklist',t=>{
  const dom=new JSDOM(readFileSync(new URL('../../../web/organizers/ball-ticket-sales',import.meta.url),'utf8'));
  t.after(()=>dom.window.close());
  const doc=dom.window.document;
  for(const anchor of doc.querySelectorAll('.article-toc a')) assert.ok(doc.getElementById(anchor.hash.slice(1)),anchor.hash);
  assert.ok(doc.querySelector('article'));
  const checklist=doc.querySelector('[data-guide-checklist]');
  const fields=[...checklist.querySelectorAll('input[type=checkbox]')];
  assert.ok(fields.length>0);
  assert.ok([...doc.querySelectorAll('[id]')].length===new Set([...doc.querySelectorAll('[id]')].map(node=>node.id)).size,'document IDs are unique');
  let printed=false;dom.window.print=()=>{printed=true;};
  const cleanup=initTopicTools(doc);t.after(cleanup);
  fields[0].click();
  const progress=checklist.querySelector('[data-guide-progress]');
  assert.equal(progress.hidden,false);
  assert.equal(progress.textContent,checklist.dataset.progressTemplate.replace('{done}','1').replace('{total}',fields.length));
  const reset=checklist.querySelector('[data-guide-reset]');
  assert.equal(reset.disabled,false);
  checklist.querySelector('[data-guide-print]').click();assert.equal(printed,true);
  reset.click();assert.ok(fields.every(input=>!input.checked));assert.equal(reset.disabled,true);
});

test('the published seating examples progressively enhance native radio selection',t=>{
  const dom=new JSDOM(readFileSync(new URL('../../../web/organizers/seating-reservations',import.meta.url),'utf8'));
  t.after(()=>dom.window.close());
  const doc=dom.window.document;
  const figures=[...doc.querySelectorAll('[data-layout-example]')];
  assert.ok(figures.length>1);
  assert.ok(figures.every(figure=>!figure.hidden),'all examples remain readable without JavaScript');
  assert.equal(doc.querySelector('[data-layout-choices]').hidden,true);
  const cleanup=initTopicTools(doc);t.after(cleanup);
  const choices=[...doc.querySelectorAll('[data-layout-choices] input')];
  choices.at(-1).click();
  assert.equal(figures.filter(figure=>!figure.hidden).length,1);
  assert.equal(figures.at(-1).hidden,false);
  assert.equal(doc.querySelector('[data-layout-choices]').hidden,false);
});
