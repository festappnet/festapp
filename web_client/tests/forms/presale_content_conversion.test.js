import test from 'node:test';
import assert from 'node:assert/strict';
import {convertLegacyPresale, timerSlot, emailSlot} from '../../scripts/presale_content_converter.mjs';
for (const primary of [null, '', '<p><br></p>', '<p>Intro</p>']) {
 for (const timer of [false,true]) for (const shown of [false,true]) {
  test(`legacy boundary ${JSON.stringify(primary)} timer=${timer} shown=${shown}`,()=>{
   const data = {schedule:{countdown_title:primary,enable_countdown:timer,show_before_start_message:shown,before_start_message:`<p>Secondary</p><img src="https://example.test/a.png">${emailSlot}${timerSlot}`}};
   const frozen = JSON.stringify(data);
   const result=convertLegacyPresale(data,{registrationStart:'Přihlašování začíná'});
   const included=shown && (timer || Boolean(primary));
   assert.equal(result.includedSecondary,included);
   assert.equal(result.html.includes('Secondary'),included);
   if(timer && included) assert.ok(result.html.indexOf('form-countdown')<result.html.indexOf('Secondary'));
   if(included) assert.equal((result.html.match(/html-editor-block/gu)??[]).length,timer?1:0);
   assert.equal(JSON.stringify(data),frozen);
   assert.ok(!('before_start_message' in result.metadata.schedule));
   assert.equal(result.metadata.design.presale_header,timer?'date':'none');
   assert.equal(result.html.includes('form-presale-system-title'),primary===null && timer);
  });
 }
}
test('only the old reachable branch may publish secondary content',()=>{
 const base={schedule:{show_before_start_message:true,before_start_message:'private'}};
 assert.equal(convertLegacyPresale(base).html,'');
 assert.equal(convertLegacyPresale({...base,sale_opening_notifications:{enabled:true}}).includedSecondary,true);
});
test('oversized candidates retain all text for the SQL preflight instead of truncating',()=>{
 for(const text of ['x'.repeat(65537),'ž'.repeat(30000)]) {
  const result=convertLegacyPresale({schedule:{countdown_title:text}});
  assert.equal(result.html,text);
 }
 const result=convertLegacyPresale({schedule:{countdown_title:'x'.repeat(40000),before_start_message:'y'.repeat(40000),show_before_start_message:true}});
 assert.ok(result.html.includes('x'.repeat(40000))); assert.ok(result.html.includes('y'.repeat(40000)));
});

test('historical null/object metadata arrays preserve both documents',()=>{
 const result=convertLegacyPresale([null,{schedule:{enable_countdown:true,before_start_message:'Secondary',show_before_start_message:true}}]);
 assert.ok(result.html.includes('form-countdown'));
 assert.ok(result.html.includes('Secondary'));
 assert.equal(result.metadata.design.presale_header,'date');
});
