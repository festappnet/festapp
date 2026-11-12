import {bankPaymentConnector} from '../../src/components/forms/connectors/builtin.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaymentConnectorRegistry} from '../../src/components/forms/payment_connector_registry.js';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';
import {formPaymentOptions} from '../../src/components/forms/form_payment_options.js';
const connector={id:'another_gateway',payPath:'/payments/another_gateway/pay',historyKey:'festappPayment',
    quote:(order,quote)=>({...order,payment_method:'another_gateway',payment_connection_id:quote.connectionId}),
    availability:value=>value.providers?.another_gateway??{configured:false,available:false},
    validateCheckoutUrl:value=>{const url=new URL(value);if(url.origin!=='https://pay.example'||url.username||url.password)throw new Error('unsafe_checkout');return url.toString();}};
const token='a'.repeat(64),payment={method:connector.id,status:'open',allowedActions:['pay','refresh']};
test('another registered connector uses the same controller, capability and redirect policy',async()=>{
    const registry=new PaymentConnectorRegistry([connector]),navigations=[];
    const owner=CardPaymentController.fromResult({payment,payment_access:{token,url:`https://tickets.example${connector.payPath}#pay=${token}`}},
        {registry,remember:()=>{},navigate:url=>navigations.push(url),invoke:async()=>({payment,checkoutUrl:'https://pay.example/order/42'})});
    assert(owner);await owner.continue();assert.deepEqual(navigations,['https://pay.example/order/42']);
    assert.throws(()=>owner.openPrepared('https://checkout.stripe.com/c/pay/anything'),/unsafe_checkout/);owner.dispose();
});
test('unknown providers cannot create a payment owner and duplicate registrations are rejected',()=>{
    const registry=new PaymentConnectorRegistry([connector]);
    assert.throws(()=>new PaymentConnectorRegistry([connector,connector]),/registration_invalid/);
    assert.equal(CardPaymentController.fromResult({payment:{...payment,method:'unknown'},payment_access:{token,url:`https://tickets.example${connector.payPath}#pay=${token}`}},{registry}),null);
});
test('availability uses each connector recipient and never invents an available method',()=>{
    const registry=new PaymentConnectorRegistry([bankPaymentConnector,connector]);
    const result=formPaymentOptions({available:['bank','another_gateway','uninstalled'],bank:{available:true},providers:{another_gateway:{configured:true,available:true,recipient:{connectionId:'merchant-42'}}}},'web',registry);
    assert.deepEqual(result.available,['bank','another_gateway']);assert.equal(result.providers.another_gateway.recipient.connectionId,'merchant-42');
    assert.deepEqual(formPaymentOptions({available:[],providers:{another_gateway:{configured:true,available:true}}},'web',registry).available,[]);
});

test('builtin identity shares registration without exposing checkout or inventing capabilities',()=>{
    const registry=new PaymentConnectorRegistry([bankPaymentConnector]);
    assert.equal(registry.get('bank').hostedCheckout,null);
    assert.equal(registry.get('bank').confirmation,'bank_event');
    assert.deepEqual(formPaymentOptions({available:['bank'],bank:{available:false}},'web',registry).available,[]);
    assert.deepEqual(formPaymentOptions({available:['bank']},'web',new PaymentConnectorRegistry([])).available,[]);
});
