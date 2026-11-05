import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {FormDataLayer, normalizeUserData, analyticsPayload, publicFormLocation, publicFormAttributionSearch, installFormIntegrationGuard, loadFormIntegrations} from '../../src/components/forms/form_datalayer.js';
import {CardPaymentController} from '../../src/components/forms/card_payment_controller.js';
import {normalizeE164Phone} from '../../src/utils/phone_formatter.js';
import {TextFieldBuilder} from '../../src/components/forms/fields/text_field_builder.js';
import {AppConfig} from '../../src/app_config.js';

const item={item_id:'product_7',item_name:'Letní koncert',price:123.45,quantity:2};
const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:'1A2C3E4F5G',payment_type:'bank_transfer',items:[item],value:0}};
const contact={email:'  JAN.NOVAK@EXAMPLE.TEST ',phone_number:'+421 (905) 123-456',address:{first_name:'Ing. Jan',last_name:'NOVÁK, Ph.D.',postal_code:'602 00',country:'cz',street:'never-transfer'},token:'never-transfer'};
const normalized={email:'jan.novak@example.test',phone_number:'+421905123456',address:{first_name:'jan',last_name:'novák',postal_code:'602 00',country:'CZ'}};
const settings={enhanced_conversions:true};
const model={id:1,data:{analytics:settings},visibleFields:[{id:1,type:'email'},{id:2,type:'phone'},{id:3,type:'name'},{id:4,type:'surname'},{id:5,type:'address'},{id:6,type:'note'},{id:7,type:'ticket',subFields:[{id:8,type:'email'}]}]};
const submitted={fields:[{1:contact.email},{2:contact.phone_number},{3:'Ing. Jan'},{4:'NOVÁK, Ph.D.'},{5:{postal_code:'602 00',country:'cz',street:'never-transfer'}},{6:'never-transfer'}],ticket:[{fields:[{email:'attendee@example.test'}],spot:'never-transfer'}]};
function dom(url='https://tickets.test/form/summer', options={}) { return new JSDOM('<html lang="cs"><head></head><body></body></html>',{url,...options}); }
const auth={onAuthStateChange(){}};

for(const hash of ['#seat-selection','#order-preview','#order-result']) test(`form overlay ${hash} keeps the guard active`,()=>{
    const page=dom();const win=page.window;const navigations=[];let reloads=0;let signedIn;
    const guard=installFormIntegrationGuard(win,{onAuthStateChange:callback=>{signedIn=callback;}},{navigate:(...args)=>navigations.push(args),reload:()=>reloads++});
    win.history.pushState({blueprintOverlay:'selection'},'',hash);
    assert.equal(win.location.hash,hash);assert.equal(publicFormLocation(win.location),true);assert.equal(guard.leaving,false);assert.deepEqual(navigations,[]);
    signedIn('SIGNED_IN',{user:{id:'test'}});assert.equal(reloads,1);
    win.history.replaceState({},'','/admin');assert.deepEqual(navigations,[[win.location.origin+'/admin',true]]);page.window.close();
});

test('unsafe fragment navigation forces a document reload without disabling future checks',()=>{
    const page=dom();const win=page.window;let reloads=0;const navigation=[];
    const guard=installFormIntegrationGuard(win,auth,{navigate:(...args)=>navigation.push(args),reload:()=>reloads++});
    win.history.pushState({},'','#pay=private');assert.equal(reloads,1);assert.equal(guard.leaving,false);
    win.history.pushState({},'','/admin');assert.equal(navigation.length,2);
    win.dispatchEvent(new win.Event('pagehide'));assert.equal(guard.leaving,true);
    win.dispatchEvent(new win.Event('pageshow'));assert.equal(guard.leaving,false);page.window.close();
});

test('Stripe departure retains payment history, navigates only once, and Back resumes the same capability',()=>{
    const page=dom();const win=page.window;const previous={window:globalThis.window,document:globalThis.document};
    Object.assign(globalThis,{window:win,document:win.document});
    try{
        const navigation=[];let preparations=0;const token='a'.repeat(64);
        installFormIntegrationGuard(win,auth,{navigate:url=>navigation.push(['guard',url]),reload:()=>navigation.push(['reload'])});
        const controller=CardPaymentController.fromResult({payment:{method:'stripe',status:'open'},payment_access:{token,url:`${win.location.origin}/stripe/pay#pay=${token}`}},
            {navigate:url=>navigation.push(['stripe',url]),invoke:async()=>{preparations++;return {};}});
        controller.openPrepared('https://checkout.stripe.com/c/pay/cs_test_same_order');
        assert.deepEqual(navigation,[['stripe','https://checkout.stripe.com/c/pay/cs_test_same_order']]);
        assert.equal(win.location.pathname,'/stripe/pay');assert.equal(win.location.hash,'');
        assert.deepEqual(win.history.state.festappStripePayment,{kind:'pay',token});assert.equal(preparations,0);
        const restored=dom(win.location.href,{runScripts:'outside-only'});
        restored.window.history.replaceState(win.history.state,'',win.location.href);
        const shell=readFileSync(new URL('../../../web/index.html',import.meta.url),'utf8');
        const capture=[...shell.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].find(match=>match[1].includes('festappStripePaymentLink'))[1];
        restored.window.eval(capture);
        assert.deepEqual(JSON.parse(restored.window.__festappStripePaymentLink),{kind:'pay',token});
        restored.window.close();controller.dispose();
    }finally{Object.assign(globalThis,previous);page.window.close();}
});

test('custom external scripts finish before the following inline scripts and errors release the queue',()=>{
    const page=dom(undefined,{runScripts:'dangerously'});const win=page.window;
    loadFormIntegrations({win,auth,settings:{scripts:'<script src="https://metrics.test/first.js"></script><script>window.sequence=(window.sequence||[]).concat("inline")</script><script src="https://metrics.test/second.js"></script><script>window.sequence.push("last")</script>'}});
    assert.equal(win.sequence,undefined);assert.equal(win.document.scripts.length,1);
    win.sequence=['external'];win.document.scripts[0].dispatchEvent(new win.Event('load'));
    assert.deepEqual([...win.sequence],['external','inline']);assert.equal(win.document.scripts.length,3);
    win.document.scripts[2].dispatchEvent(new win.Event('error'));
    assert.deepEqual([...win.sequence],['external','inline','last']);page.window.close();
});

test('pending scripts are not inserted after sign-in while waiting for an external script',()=>{
    const page=dom(undefined,{runScripts:'dangerously'});const win=page.window;
    loadFormIntegrations({win,auth,guardOptions:{reload(){}},settings:{scripts:'<script src="https://metrics.test/first.js"></script><script>window.unexpected=true</script>'}});
    win.localStorage.setItem(AppConfig.Keys.auth,'session');win.document.scripts[0].dispatchEvent(new win.Event('load'));
    assert.equal(win.unexpected,undefined);assert.equal(win.document.scripts.length,1);page.window.close();
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

test('enhanced conversion normalization removes titles, uses the actual dial prefix and whitelists address fields',()=>{
    assert.deepEqual(normalizeUserData(contact),normalized);
    assert.deepEqual(normalizeUserData({email:' ',phone_number:'905 123 456',address:{country:'Czech Republic',street:'private'}}),null);
    assert.deepEqual(normalizeUserData({phone_number:'0044 207 946 0000'}),{phone_number:'+442079460000'});
    const page=dom();const layer=new FormDataLayer({win:page.window,model,session:()=>false});
    assert.deepEqual(layer.contact(submitted),normalized);page.window.close();
});

test('enhanced conversions are off by default and only conversion events can carry contact fields',()=>{
    const page=dom();const layer=new FormDataLayer({win:page.window,model:{...model,data:{}},session:()=>false});
    assert.equal(layer.contact(submitted),null);
    layer.emit({...purchase,user_data:contact});
    assert.equal(page.window.dataLayer.find(value=>value.event==='purchase').user_data,undefined);
    assert.equal(JSON.stringify(page.window.dataLayer).includes('example.test'),false);
    for(const event of ['view_item','begin_checkout','form_submit_error','page_view']) assert.equal(analyticsPayload({...purchase,event,user_data:contact},{allowUserData:true}).user_data,undefined);
    page.window.close();
});

for(const event of ['purchase','generate_lead']) test(`${event} publishes contact next to ecommerce and clears it immediately`,()=>{
    const page=dom();const layer=new FormDataLayer({win:page.window,model,session:()=>false});
    layer.emit(event==='purchase'?{...purchase,user_data:contact}:{event,currency:'CZK',value:0,lead_source:'free_registration',user_data:contact});
    assert.deepEqual(page.window.dataLayer[0],{ecommerce:null,user_data:null});
    assert.deepEqual(page.window.dataLayer[1].user_data,normalized);
    assert.equal(page.window.dataLayer[1].ecommerce?.user_data,undefined);
    assert.deepEqual(page.window.dataLayer.at(-1),{user_data:null});page.window.close();
});

for(const enabled of [false,true]) for(const hostOptIn of [false,true]) test(`embedded contact requires both opt-ins: form=${enabled}, host=${hostOptIn}`,()=>{
    const page=dom('https://tickets.test/form/summer?embed=1');const sent=[];
    const bridge={dataLayer:true,dataLayerUserData:hostOptIn,track:value=>sent.push(value)};
    const layer=new FormDataLayer({win:page.window,model:{...model,data:{analytics:{enhanced_conversions:enabled}}},bridge,session:()=>false});
    layer.emit({...purchase,user_data:contact});
    assert.equal(Boolean(sent[0].user_data),enabled&&hostOptIn);assert.equal(page.window.dataLayer,undefined);page.window.close();
});

const emailCases = [
    [' Jan.Novak@Seznam.CZ ', 'jan.novak@seznam.cz'],
    ['\u200B\uFEFF Jan.Novak@Seznam.CZ \u2060', 'jan.novak@seznam.cz'],
    ['jan@firma.co.uk', 'jan@firma.co.uk'],
    ['jan.novak@gmail.com', 'jan.novak@gmail.com'],
    ['neni-email', null], ['jan@@firma.cz', null], ['jan@firma', null],
    ['jan@-firma.cz', null], ['jan@firma.123', null], ['jan novak@firma.cz', null],
    ['jan\u200B@firma.cz', null], ['', null],
];
for (const [input, output] of emailCases) test(`contact email normalizes and uses the form validator: ${JSON.stringify(input)}`, () => {
    assert.equal(normalizeUserData({email:input})?.email ?? null, output);
});
const phoneCases = [
    ['+420 777 123 456', '+420777123456'], ['777123456', '+420777123456'],
    ['00420777123456', '+420777123456'], ['420777123456', '+420777123456'],
    ['+421 900 123 456', '+421900123456'], ['+1 (415) 555-2671', '+14155552671'],
    ['+44 20 7946 0958', '+442079460958'], ['0044 20 7946 0958', '+442079460958'],
    ['123', null], ['', null], ['+012345678', null], ['+1234567', null], ['+1234567890123456', null],
];
for (const [input, output] of phoneCases) test(`contact phone with a known field prefix: ${JSON.stringify(input)}`, () => {
    assert.equal(normalizeE164Phone(input, {defaultPrefix:'+420'}), output);
    assert.equal(normalizeUserData({phone_number:input}, {phonePrefix:'+420'})?.phone_number ?? null, output);
});

test('national phone fallback requires the actual field prefix or a single unambiguous default',()=>{
    assert.equal(normalizeE164Phone('777123456'),null);
    assert.equal(normalizeE164Phone('4155552671',{defaultPrefix:'+1'}),'+14155552671');
    const page=dom();const field=page.window.document.createElement('input');field.name='2';field.dataset.phonePrefix='+421';page.window.document.body.append(field);
    const layer=new FormDataLayer({win:page.window,model,session:()=>false});
    assert.equal(layer.contact({fields:[{2:'900123456'}]},page.window.document.body).phone_number,'+421900123456');
    assert.equal(layer.contact({fields:[{2:'900123456'}]})?.phone_number,undefined);
    const onePrefix=new FormDataLayer({win:page.window,model:{...model,data:{analytics:settings,phone_prefixes:['+420']}},session:()=>false});
    assert.equal(onePrefix.contact({fields:[{2:'777123456'}]}).phone_number,'+420777123456');page.window.close();
});

test('phone chips expose the visitor-selected prefix without changing order fields',()=>{
    const page=dom();const previous={window:globalThis.window,document:globalThis.document};Object.assign(globalThis,{window:page.window,document:page.window.document});
    try{
        const field=TextFieldBuilder.create({id:2,type:'phone',isRequired:true,title:'Telefon'},{data:{phone_prefixes:['+420','+421','+1']}});
        const input=field.querySelector('input');assert.equal(input.dataset.phonePrefix,'+420');
        const chip=[...field.querySelectorAll('.phone-badge-chip')].find(value=>value.textContent.includes('+421'));
        chip.click();assert.equal(input.dataset.phonePrefix,'+421');
    }finally{Object.assign(globalThis,previous);page.window.close();}
});
