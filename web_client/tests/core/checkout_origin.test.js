import test from 'node:test';
import assert from 'node:assert/strict';
import {withCheckoutOrigin} from '../../src/services/checkout_origin.js';
const token='cHJvdmVuYW5jZQ.'+'a'.repeat(64);
test('Wix embed and direct fallback forward the same provenance without changing actor/order fields',()=>{
  const order={form:'fixture-form',email:'buyer@example.invalid'};
  for(const search of [`?embed=1&checkout_origin=${token}`,`?checkout_origin=${token}`]) {
    assert.deepEqual(withCheckoutOrigin(order,{pathname:'/form/ples',search}),{...order,checkoutOrigin:token});
  }
  assert.equal('checkoutOrigin' in order,false);
});
test('ordinary checkout is unchanged and arbitrary instance IDs establish no provenance',()=>{
  const order={form:'fixture-form'};
  assert.equal(withCheckoutOrigin(order,{pathname:'/form/ples',search:'?instanceId=forged'}),order);
  assert.equal(withCheckoutOrigin(order,{pathname:'/admin',search:`?checkout_origin=${token}`}),order);
});
test('malformed and ambiguous contexts fail before order submission',()=>{
  const order={form:'fixture-form'};
  for(const search of ['?checkout_origin=not-a-proof',`?checkout_origin=${token}&checkout_origin=${token}`]) {
    assert.throws(()=>withCheckoutOrigin(order,{pathname:'/form/ples',search}),/INVALID_CHECKOUT_ORIGIN/);
  }
});
