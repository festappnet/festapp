import assert from 'node:assert/strict';
import {renderSaleOpeningEmail} from './saleOpeningEmail.ts';
import {saleOpeningCopy, saleOpeningUrl, saleOpeningSubstitutions} from './saleOpeningPresentation.ts';
import {emailPayloadHash} from './emailPayload.ts';
import {renderEmail} from './emailDelivery.ts';
import {emailRegistry} from './emailRegistry.ts';
const token='a'.repeat(64);
for(const lang of Object.keys(saleOpeningCopy)) for(const kind of ['sale_opening_opened']) {
 Deno.test(`${kind} ${lang} uses inherited wrapper, one CTA, unsubscribe, no order details or tracking`,async()=>{
  const cap={hash:await emailPayloadHash(token),envelope:{v:'1',iv:'fixture',ciphertext:'fixture'}};
  const row={message_id:'fixture',message_kind:kind,recipient:'jana@example.invalid',organization:1,occasion:2,unit:3};
  const result=await renderSaleOpeningEmail(row,{
   context:async()=>({organization:1,occasion:2,unit:3,recipient:row.recipient,occasionTitle:'Ples & tanec',formLink:'ples',webLink:'https://example.invalid',lang,capabilities:{unsubscribe:cap}}),
   open:async()=>({token}),
   render:input=>renderEmail({...input,from:'test@example.invalid'},async()=>({template:{id:1,subject:'{{sale_opening_subject}} - {{occasionTitle}}',html:'<p>{{occasionTitle}}</p><h2>{{sale_opening_heading}}</h2><p>{{sale_opening_action}}</p><p>{{sale_opening_unsubscribe}}</p>'},wrapper:{html:'<article data-inherited="yes">{{content}}</article>'}})),
  });
  assert.equal(result.postAction.tracking_policy,'disabled');assert.equal(emailRegistry[kind as keyof typeof emailRegistry].sensitive,true);
  assert.match(result.prepared.html,/data-inherited="yes"/);assert.match(result.prepared.html,/Ples/);assert.match(result.prepared.subject,/Ples & tanec/);
  assert.equal((result.prepared.html.match(/display:inline-block/g)||[]).length,1);
  assert.match(result.prepared.html,/#sale_opening=unsubscribe/);
  assert.doesNotMatch(result.prepared.html,/order_symbol|paymentDetails|variable_symbol|qr-code/);
  assert.match(result.prepared.html,/href="https:\/\/example.invalid\/form\/ples"/);
 });
}
Deno.test('capability origin and scope are checked; sources stay encrypted until rendering',async()=>{
 assert.throws(()=>saleOpeningUrl('http://unsafe.example','ples','confirm',token));
 assert.throws(()=>saleOpeningUrl('https://example.invalid?token=secret','ples'));
 const row={message_id:'fixture',message_kind:'sale_opening_opened',recipient:'jana@example.invalid',organization:1,occasion:2,unit:3};
 await assert.rejects(()=>renderSaleOpeningEmail(row,{context:async()=>({organization:9,occasion:2,unit:3,recipient:row.recipient,occasionTitle:'Ples',formLink:'ples',webLink:'https://example.invalid',lang:'cs',capabilities:{}})}),/scope_invalid/);
 const substitutions=saleOpeningSubstitutions('cs','<script>','https://test.invalid','https://test.invalid');
 assert.equal(substitutions.occasionTitle,'<script>');
 const prepared=await renderEmail({to:row.recipient,templateCode:row.message_kind,context:{organization:1},substitutions},
  async()=>({template:{id:1,subject:'{{occasionTitle}}',html:'<p>{{occasionTitle}}</p>'}}));
 assert.equal(prepared.subject,'<script>');
 assert.equal(prepared.html,'<p>&lt;script&gt;</p>');
});
