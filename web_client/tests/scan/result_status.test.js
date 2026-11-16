import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {LocalizationService} from '../../src/services/localization_service.js';
import {scanResult} from '../../src/components/scan/scan_result.js';
import {scannerUsedText,refreshScannerUsedTimes,scannerSearchPreview} from '../../src/components/scan/scanner_presentation.js';
const now=Date.parse('2026-11-13T18:00:00Z');
const timestamp=seconds=>new Date(now-seconds*1000).toISOString();
const ticket={state:'used',updated_at:timestamp(300),symbol:'TEST',products:[],fields:[],admission_allowed:false};
LocalizationService.currentLocale='cs';
LocalizationService.translations=JSON.parse(readFileSync(new URL('../../../assets/translations/cs.json',import.meta.url)));
test('used tickets show natural Czech elapsed time and handle invalid dates',()=>{
 for(const [seconds,text] of [[0,'nyní'],[45,'před 45 sekundami'],[60,'před 1 minutou'],[300,'před 5 minutami'],[7200,'před 2 hodinami'],[172800,'předevčírem']])assert.equal(scannerUsedText(timestamp(seconds),now),`Vstupenka už byla použita (${text})`);
 for(const value of [null,undefined,'','invalid'])assert.equal(scannerUsedText(value,now),'Vstupenka už byla použita');
 assert.equal(scannerUsedText(timestamp(-60),now),'Vstupenka už byla použita (nyní)');
});
test('used, unpaid, valid and invalid results preserve distinct status and confirmation behavior',t=>{
 t.mock.timers.enable({apis:['Date'],now});
 const used=scanResult({state:'result',ticket},true);
 assert.match(used,/scan-result used/);assert.match(used,/Vstupenka už byla použita \(před 5 minutami\)/);assert.doesNotMatch(used,/Invalid Date|data-confirm/);
 for(const [value,tone] of [[{state:'sent',admission_allowed:true},'allowed'],[{state:'ordered',requires_unpaid_confirmation:true,admission_allowed:true},'pending'],[{state:'storno'},'blocked']]){
  const html=scanResult({state:'result',ticket:{...ticket,...value}},true);
  assert.match(html,new RegExp(`scan-result ${tone}`));
  if(tone==='pending'){assert.match(html,/Vstupenka není zaplacená/);assert.match(html,/data-confirm disabled/);}
 }
 const missing=scanResult({state:'error',error:'not_found'},true);
 assert.match(missing,/scan-result blocked/);assert.match(missing,/Vstupenka nebyla v této akci nalezena/);
});
test('simultaneous admission conflict does not use receipt time as first use time',()=>{
 const html=scanResult({state:'conflict',ticket:{...ticket,state:'sent'},operation:{receipt:{reason:'already_used',committed_at:timestamp(10)}}},true);
 assert.match(html,/scan-result used/);assert.match(html,/Vstupenka už byla použita/);assert.doesNotMatch(html,/před|data-scan-used-at|data-confirm/);
});
test('elapsed time refreshes in result and search without replacing controls',t=>{
 t.mock.timers.enable({apis:['Date'],now});
 const dom=new JSDOM(scanResult({state:'result',ticket},true)+scannerSearchPreview(ticket));
 try{
  const next=dom.window.document.querySelector('[data-next]');
  refreshScannerUsedTimes(dom.window.document,now+60000);
  const labels=[...dom.window.document.querySelectorAll('[data-scan-used-at]')];
  assert.equal(labels.length,2);
  for(const label of labels)assert.equal(label.textContent,'Vstupenka už byla použita (před 6 minutami)');
  assert.equal(dom.window.document.querySelector('[data-next]'),next);
 }finally{dom.window.close();}
});

test('server rejection for unpaid confirmation keeps the unpaid warning explicit',()=>{
 const html=scanResult({state:'rejected',ticket:{...ticket,state:'ordered'},operation:{receipt:{reason:'unpaid_confirmation_required'}}},true);
 assert.match(html,/scan-result pending/);assert.match(html,/Vstupenka není zaplacená/);assert.doesNotMatch(html,/data-confirm/);
});
