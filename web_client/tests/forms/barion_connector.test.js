import test from 'node:test';
import assert from 'node:assert/strict';
import {paymentConnectors} from '../../src/components/forms/payment_connector_registry.js';
const connector=paymentConnectors.get('barion');
test('registered Barion allows only sandbox GUID checkout',()=>{
    assert.equal(connector.validateCheckoutUrl('https://secure.test.barion.com/Pay?Id='+'a'.repeat(32)), 'https://secure.test.barion.com/Pay?Id='+'a'.repeat(32));
    for(const value of ['https://secure.barion.com/Pay?Id='+'a'.repeat(32),'https://secure.test.barion.com/other?Id='+'a'.repeat(32),'https://secure.test.barion.com/Pay?Id='+'a'.repeat(32)+'&id='+'b'.repeat(32)]) assert.throws(()=>connector.validateCheckoutUrl(value));
    assert.equal(paymentConnectors.get('stripe').validateCheckoutUrl('https://checkout.stripe.com/c/pay/cs_fixture'),'https://checkout.stripe.com/c/pay/cs_fixture');
});
test('Barion registration does not activate sales or inherit Stripe connection fields',()=>{
    assert.equal(connector.availability({providers:{barion:{configured:true,available:true}}}).available,false);
    const q=connector.quote({}, {connectionId:'fixture',amountMinor:100,currency:'CZK',surface:'web'});
    assert.equal(q.payment_connection_id,'fixture');assert.equal(q.payment_method,'barion');assert.equal(q.stripe_connection_id,undefined);
});
