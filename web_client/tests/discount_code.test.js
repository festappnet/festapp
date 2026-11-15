import test from 'node:test';
import assert from 'node:assert/strict';
import {DiscountCode} from '../src/components/forms/discount_code.js';
import {analyticsPayload} from '../src/components/forms/form_measurement_contract.js';

test('discount transports server money and removes a stale quote after selection changes', async()=> {
 const session={payload:{form:'form-key',ticket:[{fields:[{product_type:1}]}]}};
 let request;
 const discount=new DiscountCode(session,async input=> {request=input;return {data:{code:200,quote:{code:'SAVE10',base:100,discount:10,net:90,currency:'CZK',fingerprint:'a'.repeat(64)}}};});
 discount.code='save10';assert.equal(await discount.apply(),true);
 assert.equal(request.discount.code,'save10');
 assert.deepEqual(session.payload.discount,{code:'SAVE10',fingerprint:'a'.repeat(64)});
 assert.equal(discount.priceData({totalPrice:100}).totalPrice,90);
 session.payload.ticket.push({fields:[{product_type:2}]});
 assert.equal(discount.valid,false);assert.equal(discount.priceData({totalPrice:200}).totalPrice,200);
 discount.clear();assert.equal(session.payload.discount,undefined);
});
test('a late quote cannot overwrite a removed code or changed selection',async()=> {
 let resolve;const session={payload:{ticket:[]}};
 const discount=new DiscountCode(session,()=>new Promise(r=>resolve=r));discount.code='SAVE10';
 const pending=discount.apply();discount.clear();resolve({data:{code:200,quote:{code:'SAVE10'}}});
 assert.equal(await pending,false);assert.equal(session.payload.discount,undefined);
});
test('invalid discount does not retain an old quote or leak a raw code through analytics',async()=> {
 const session={payload:{ticket:[]}};
 const discount=new DiscountCode(session,async()=>({data:{code:400,errorCode:'DISCOUNT_INVALID'}}));discount.code='PRIVATE-CODE';
 await assert.rejects(discount.apply());assert.equal(discount.quote,null);
 const result=analyticsPayload({event:'purchase',discount:{code:'PRIVATE-CODE'},ecommerce:{transaction_id:'order_1',currency:'CZK',value:90,items:[{item_id:'product_1',item_name:'Admission',price:90,quantity:1}]}});
 assert.equal(JSON.stringify(result).includes('PRIVATE-CODE'),false);
});

test('checkout measurement projects SQL net lines and never the raw code',async()=>{
 const {FormDataLayer}=await import('../src/components/forms/form_datalayer.js');
 const sent=[];
 const layer=new FormDataLayer({win:{document:{documentElement:{lang:'en'}}},model:{occasionTitle:'Dance',visibleFields:[{id:1,type:'product_type',options:[{id:1,title:'Admission',price:100,currency_code:'CZK'}]}]},sink:{record:p=>{sent.push(p);return true;}}});
 const payload={ticket:[{fields:[{product_type:1}]}],discount:{code:'PRIVATE-CODE'}};
 const session={discountCode:{valid:true,quote:{lines:[{productId:1,net:80.25,currency:'CZK'}]}}};
 layer.review(payload,session);layer.payment(payload,'bank',session);
 for(const event of sent.filter(p=>p.ecommerce)) {assert.equal(event.ecommerce.items[0].price,80.25);assert.equal(analyticsPayload(event).ecommerce.value,80.25);}
 assert.equal(JSON.stringify(sent).includes('PRIVATE-CODE'),false);
});

test('waitlist discount recovery reuses its committed request and cannot create a fresh acceptance',async()=>{
 const {WaitlistCommands}=await import('../src/components/forms/waitlist_commands.js');
 const sent=[];const commands=new WaitlistCommands({functions:{invoke:async(_name,{body})=>{sent.push(structuredClone(body));return {data:sent.length===1 ? {code:503} : {code:200,order:{id:42}},error:null};}}});
 const scope={offerId:'offer',token:'token'};const payload={form:'f',ticket:[],discount:{code:'LAST',fingerprint:'a'.repeat(64)}};
 await assert.rejects(commands.accept(scope,[1],payload));
 await assert.rejects(commands.accept(scope,[2],payload,{reusePendingOnly:true}),/RECOVERY_REQUIRED/);assert.equal(sent.length,1);
 assert.equal((await commands.accept(scope,[1],payload,{reusePendingOnly:true})).order.id,42);
 assert.deepEqual(sent[1],sent[0]);
 await assert.rejects(commands.accept(scope,[1],payload,{reusePendingOnly:true}),/RECOVERY_REQUIRED/);assert.equal(sent.length,2);
});
