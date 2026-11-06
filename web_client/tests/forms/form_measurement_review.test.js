import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {analyticsPayload} from '../../src/components/forms/form_measurement_contract.js';
import {publicFormAttributionSearch} from '../../src/utils/public_form_location.js';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';
import {AppConfig} from '../../src/app_config.js';
const item={item_id:'product_7',item_name:'Letní koncert',price:123.45,quantity:2};
const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',payment_type:'bank_transfer',items:[item]}};
function dom(url='https://tickets.test/form/summer',options={}) {return new JSDOM('<html><body></body></html>',{url,...options});}
test('Stripe departure retains payment history, navigates only once, and Back resumes the same capability',()=>{
    const page=dom();const win=page.window;const previous={window:globalThis.window,document:globalThis.document};
    Object.assign(globalThis,{window:win,document:win.document});
    try{
        const navigation=[];let preparations=0;const token='a'.repeat(64);
        const controller=CardPaymentController.fromResult({payment:{method:'stripe',status:'open'},payment_access:{token,url:`${win.location.origin}/stripe/pay#pay=${token}`}},
            {navigate:url=>navigation.push(['stripe',url]),invoke:async()=>{preparations++;return {};}});
        controller.openPrepared('https://checkout.stripe.com/c/pay/cs_test_same_order');
        assert.deepEqual(navigation,[['stripe','https://checkout.stripe.com/c/pay/cs_test_same_order']]);
        assert.equal(win.location.pathname,'/stripe/pay');assert.equal(win.location.hash,'');
        assert.deepEqual(win.history.state.festappPayment,{provider:'stripe',kind:'pay',token});assert.equal(preparations,0);
        const restored=dom(win.location.href,{runScripts:'outside-only'});
        restored.window.history.replaceState(win.history.state,'',win.location.href);
        const shell=readFileSync(new URL('../../../web/index.html',import.meta.url),'utf8');
        const capture=[...shell.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].find(match=>match[1].includes('festappPaymentLink'))[1];
        restored.window.eval(capture);
        assert.deepEqual(JSON.parse(restored.window.__festappPaymentLink),{provider:'stripe',kind:'pay',token});
        restored.window.close();controller.dispose();
    }finally{Object.assign(globalThis,previous);page.window.close();}
});

test('attribution survives form startup and other parameters are removed before mount',async t=>{
    const page=dom('https://tickets.test/form/summer?utm_source=search&utm_campaign=summer&gclid=click&lang=cs&token=private#pay=private');
    const previous={window:globalThis.window,document:globalThis.document};Object.assign(globalThis,{window:page.window,document:page.window.document});
    const {RouterService}=await import('../../src/services/router_service.js');
    const oldSupported=AppConfig.isAppSupported;AppConfig.isAppSupported=false;
    try{
        let observed;
        t.mock.method(RouterService,'mountForm',async()=>{observed=page.window.location.href;});
        await RouterService.handleInitialLoad();
        assert.equal(observed,'https://tickets.test/form/summer?utm_source=search&utm_campaign=summer&gclid=click&lang=cs');
        assert.equal(publicFormAttributionSearch(new URL('https://tickets.test/events?utm_source=search')),'');
        assert.equal(page.window.location.hash,'');
    }finally{AppConfig.isAppSupported=oldSupported;Object.assign(globalThis,previous);page.window.close();}
});

test('all approved ecommerce events carry the final price, offer name and recomputed value',()=>{
    for(const event of ['view_item','add_to_cart','remove_from_cart','begin_checkout','add_payment_info','purchase']){
        const result=analyticsPayload({...purchase,event});assert.ok(result,event);
        assert.deepEqual(result.ecommerce.items,[item]);assert.equal(result.ecommerce.value,246.9);assert.equal(result.ecommerce.currency,'CZK');assert.equal(result.ecommerce.tax,undefined);
    }
    assert.equal(analyticsPayload({...purchase,event:'view_item',ecommerce:{currency:'EUR',items:[{...item,price:0.1,quantity:3}]}}).ecommerce.value,0.3);
});


test('measurement owner has no script insertion, history interception, Auth subscription or contact export',()=>{
 const source=readFileSync(new URL('../../src/components/forms/form_datalayer.js',import.meta.url),'utf8');
 for(const retired of ['loadFormIntegrations','installFormIntegrationGuard','integrationDocuments','navigateWithFormReturnContext',"createElement('script')",'onAuthStateChange','history.replaceState','user_data']) assert(!source.includes(retired),retired);
});
