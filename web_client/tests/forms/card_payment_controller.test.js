import test from 'node:test';
import assert from 'node:assert/strict';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';
const token='a'.repeat(64);
const payment={method:'stripe',status:'open',allowedActions:['pay','refresh']};
const result={payment,payment_access:{token,url:`https://tickets.example/stripe/pay#pay=${token}`}};
test('A08 read projection and return handle cannot manufacture a payment owner',()=>{
  assert.equal(CardPaymentController.fromResult({payment}),null);
  assert.equal(CardPaymentController.fromResult({...result,payment_access:{token,url:'https://foreign.example/stripe/pay?pay='+token}}),null);
});
test('A09 simultaneous clicks continue the original attempt once and retain private Back context',async()=>{
  let finish,calls=0;const navigation=[],remembered=[];
  const owner=CardPaymentController.fromResult(result,{invoke:async body=>{calls++;assert.equal(body.token,token);assert.equal(body.action,'prepare');return new Promise(resolve=>{finish=resolve;});},
    navigate:url=>navigation.push(url),remember:(value,url)=>remembered.push([value,url.pathname])});
  const first=owner.continue();await owner.continue();assert.equal(calls,1);
  finish({payment,checkoutUrl:'https://checkout.stripe.com/c/pay/cs_test_fixture'});await first;
  assert.deepEqual(remembered,[[token,'/stripe/pay']]);assert.equal(navigation.length,1);assert(!navigation[0].includes(token));owner.dispose();
});
test('A10/A11 resume refresh is read only and a completed payment never redirects again',async()=>{
  const calls=[];const owner=CardPaymentController.fromResult(result,{invoke:async body=>{calls.push(body);return {payment:{...payment,status:'paid'}};},navigate:()=>assert.fail('paid redirect'),remember:()=>{}});
  await owner.refresh();assert.deepEqual(calls,[{token,action:'status'}]);assert.equal(owner.payment.status,'paid');owner.dispose();
});
test('A09 uncertain response keeps the same capability and stops unsafe redirect',async()=>{
  const states=[];const owner=CardPaymentController.fromResult(result,{invoke:async()=>{throw new Error('private backend detail');},onPayment:p=>states.push(p),navigate:()=>assert.fail('uncertain redirect')});
  await assert.rejects(()=>owner.continue());assert.equal(owner.token,token);assert.equal(states[0].status,'unknown');assert.deepEqual(states[0].allowedActions,['refresh']);owner.dispose();
});
test('A11 disposed result ignores late transport response',async()=>{
  let finish;const owner=CardPaymentController.fromResult(result,{invoke:()=>new Promise(resolve=>{finish=resolve;}),onPayment:()=>assert.fail('disposed update'),navigate:()=>assert.fail('disposed redirect')});
  const request=owner.continue();owner.dispose();finish({payment,checkoutUrl:'https://checkout.stripe.com/c/pay/cs_test_fixture'});await request;assert.equal(owner.token,null);
});
