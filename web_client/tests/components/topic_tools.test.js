import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {initTopicTools} from '../../src/marketing/topic_tools.js';

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
