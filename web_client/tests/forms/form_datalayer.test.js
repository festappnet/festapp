import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {FormDataLayer, analyticsPayload, publicFormLocation, shouldLoadFormIntegrations, loadFormIntegrations as loadIntegrations, installFormIntegrationGuard} from '../../src/components/forms/form_datalayer.js';
import {FORM_MEASUREMENT_SCRIPT_LIMIT} from '../../src/components/forms/form_measurement_limits.js';
import {AppConfig} from '../../src/app_config.js';

const loadFormIntegrations = options => loadIntegrations({auth:{onAuthStateChange() {}},...options});

const symbol = '1A2C3E4F5G';
const paid = {item_id:'product_11', item_name:'Concert ticket', price:100, quantity:2, currency:'CZK'};
const purchase = {event:'purchase', ecommerce:{transaction_id:symbol, currency:'CZK', payment_type:'bank_transfer', items:[paid]}};
const model = {id:7, visibleFields:[{id:4,type:'product_type',options:[{id:11,title:'Concert ticket',price:100,currency:'CZK'},{id:12,title:'Free registration',price:0,currency:'CZK'}]}, {id:5,type:'text',options:[{id:99,price:5,currency:'CZK'}]}, {id:6,type:'ticket',subFields:[{id:8,type:'product_type',options:[{id:13,title:'Evening ticket',price:200,currency:'EUR'}]}]}]};
const payload = {fields:[{4:'11',5:'private name',email:'private'}],ticket:[{spot:123,spotName:'private seat',fields:[{product_type:11},{email:'private'},{product_type:999},{product_type:13}]}]};
function fixture(url='https://tickets.test/form/summer') {
    const dom = new JSDOM('<html lang="cs"><head></head><body></body></html>', {url});
    return {dom, layer:new FormDataLayer({win:dom.window,model,session:()=>false})};
}
const events = win => (win.dataLayer || []).filter(item => item.event);

test('base, page_view and catalog ecommerce precede standard GTM, without answers and with final buyer prices', () => {
    const {dom,layer}=fixture(); const win=dom.window;
    layer.view();
    assert.deepEqual(win.dataLayer.slice(0,2),[{page_type:'product',user_type:'b2c',language:'cs'},{event:'page_view'}]);
    assert.deepEqual(events(win).map(item=>item.event),['page_view','view_item','view_item']);
    assert.deepEqual(events(win)[1].ecommerce,{currency:'CZK',items:[{item_id:'product_11',item_name:'Concert ticket',price:100,quantity:1},{item_id:'product_12',item_name:'Free registration',price:0,quantity:1}],value:100});
    assert.equal(loadFormIntegrations({win,settings:{gtm_container:'GTM-AB12'}}),true);
    assert.equal(win.dataLayer.at(-1).event,'gtm.js');
    assert.equal(win.document.querySelector('script').src,'https://www.googletagmanager.com/gtm.js?id=GTM-AB12');
    assert.equal(loadFormIntegrations({win,settings:{gtm_container:'GTM-OTHER'}}),false);
    assert.equal(JSON.stringify(win.dataLayer).includes('product_99'),false);
    dom.window.close();
});

test('cart changes use quantity deltas, including equal-price swaps and currency changes', () => {
    const {dom,layer}=fixture(); const win=dom.window;
    layer.update(payload); layer.update(payload);
    assert.deepEqual(events(win).map(item=>item.event),['add_to_cart','add_to_cart']);
    assert.deepEqual(events(win)[0].ecommerce.items,[{item_id:'product_11',item_name:'Concert ticket',price:100,quantity:2}]);
    layer.update({fields:[{4:'12'}]});
    assert.deepEqual(events(win).slice(2).map(item=>item.event),['add_to_cart','remove_from_cart','remove_from_cart']);
    assert.deepEqual(events(win)[2].ecommerce,{currency:'CZK',items:[{item_id:'product_12',item_name:'Free registration',price:0,quantity:1}],value:0});
    for (let i=0;i<win.dataLayer.length;i++) if(win.dataLayer[i].ecommerce) assert.deepEqual(win.dataLayer[i-1],{ecommerce:null,user_data:null});
    assert.equal(JSON.stringify(win.dataLayer).includes('private'),false);
    dom.window.close();
});

test('review sends a checkout page and begin_checkout; payment carries the method', () => {
    const {dom,layer}=fixture(); const win=dom.window;
    layer.review({fields:[{4:11}]}); layer.payment({fields:[{4:11}]},'stripe');
    assert.deepEqual(events(win).map(item=>item.event),['page_view','begin_checkout','add_payment_info']);
    assert.deepEqual(win.dataLayer[0],{page_type:'checkout',user_type:'b2c',language:'cs'});
    assert.equal(events(win).at(-1).ecommerce.payment_type,'card');
    layer.payment({fields:[{4:11}]},'bank');
    assert.equal(events(win).at(-1).ecommerce.payment_type,'bank_transfer');
    dom.window.close();
});

test('purchase requires a server projection and a public symbol, once across callbacks and reloads', () => {
    const {dom,layer}=fixture(); const win=dom.window;
    layer.confirmed({ticketOrder:{order:{payment_info:{amount:200}}}});
    assert.equal(events(win).some(item=>item.event==='purchase'),false);
    const data={ticketOrder:{analytics:purchase,order:{payment_info:{amount:200}}}};
    layer.confirmed(data); layer.confirmed(data);
    new FormDataLayer({win,model,session:()=>false}).confirmed(data);
    assert.equal(events(win).filter(item=>item.event==='purchase').length,1);
    assert.deepEqual(events(win).find(item=>item.event==='purchase'),analyticsPayload(purchase));
    assert.equal(win.localStorage.getItem(`festapp-purchase:${symbol}`),'1');
    assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,transaction_id:'a'.repeat(64)}}),null);
    dom.window.close();
});

test('free registration and waitlist are zero-value leads, errors contain no backend text', () => {
    const {dom,layer}=fixture();const win=dom.window;
    layer.confirmed({ticketOrder:{order:{payment_info:{amount:0,currency_code:'EUR'}}}});
    layer.confirmed({},true);layer.emit({event:'form_submit_error',message:'private',errorCode:'private'});
    assert.deepEqual(events(win).filter(item=>item.event!=='page_view'),[
        {event:'generate_lead',currency:'EUR',value:0,lead_source:'free_registration'},
        {event:'generate_lead',currency:'CZK',value:0,lead_source:'waitlist'},
        {event:'form_submit_error'}]);
    dom.window.close();
});

test('whitelist discards every unapproved field, bounds items and recomputes value from final prices', () => {
    const dirty={...purchase,email:'secret',user_data:{email:'secret'},page_location:'secret',ecommerce:{...purchase.ecommerce,value:999,token:'secret',items:[{...paid,price:100,item_name:'Concert ticket',seat:'secret',email:'secret'}]}};
    assert.deepEqual(analyticsPayload(dirty),analyticsPayload(purchase));
    for(const event of ['gtag','form_start','form_view','form_submit_success']) assert.equal(analyticsPayload({event}),null);
    for(const invalid of [[],new Array(201).fill(paid),[{...paid,quantity:0}],[{...paid,item_id:'seat_1'}]]) assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,items:invalid}}),null);
    assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,currency:''}}),null);
    assert.equal(analyticsPayload({...purchase,ecommerce:{...purchase.ecommerce,payment_type:'private'}}),null);
    assert.deepEqual(analyticsPayload({event:'view_item',ecommerce:{currency:'CZK',value:44,items:[{...paid,price:0,quantity:3}]}}).ecommerce.value,0);
});

const privatePaths=['/admin','/scanner','/order?token=private','/pay?token=private','/form/x?preview=true','/form/x?admin=1','/form/x?sale_opening=private','/form/x?pay=private','/form/x?handoff=private','/form/x?return_handle=private','/form/x?order_id=1','/form/x?offer_id=private','/form/x?token=private','/form/x?waitlist=private','/form/x#order?token=private','/form/x#waitlist?token=private','/form/x#access_token=private','/form/x?unknown=private'];
for(const path of privatePaths) test(`private context cannot emit or load: ${path}`,()=>{
    const {dom,layer}=fixture(`https://tickets.test${path}`);const win=dom.window;
    layer.view();
    assert.equal(publicFormLocation(win.location,{entry:true}),false);
    assert.equal(shouldLoadFormIntegrations(win),false);
    assert.equal(loadFormIntegrations({win,settings:{gtm_container:'GTM-AB12',scripts:'<script>1</script>'}}),false);
    assert.equal(win.document.querySelector('script'),null);assert.equal(win.dataLayer,undefined);
    dom.window.close();
});

test('session blocks loading and dataLayer; inaccessible storage fails closed',()=>{
    const {dom}=fixture();const win=dom.window;
    for(const storage of [win.localStorage,win.sessionStorage]){
        storage.setItem(AppConfig.Keys.auth,'present');
        assert.equal(shouldLoadFormIntegrations(win),false);
        assert.equal(loadFormIntegrations({win,settings:{gtm_container:'GTM-AB12'}}),false);
        new FormDataLayer({win,model}).view();assert.equal(win.dataLayer,undefined);
        storage.clear();
    }
    Object.defineProperty(win,'localStorage',{get(){throw new Error('unavailable');}});
    assert.equal(shouldLoadFormIntegrations(win),false);
    dom.window.close();
});

test('embed sends the same minimal objects only to the bridge and cannot load scripts',()=>{
    const {dom}=fixture('https://tickets.test/form/summer?embed=1');const win=dom.window;
    const sent=[];new FormDataLayer({win,model,bridge:{track:payload=>sent.push(payload)},session:()=>false}).view();
    assert.equal(sent[0].page_type,'product');assert.equal(sent[1].event,'page_view');
    assert.equal(win.dataLayer,undefined);
    assert.equal(loadFormIntegrations({win,settings:{gtm_container:'GTM-AB12'}}),false);
    dom.window.close();
});

test('custom snippet creates only scripts, preserves inline code and safe attributes, rejects unsafe sources',()=>{
    const {dom}=fixture();const win=dom.window;
    const code='<img src="https://evil.test/pixel"><div>ignored</div><script>window.measurement=1</script><script async src="https://metrics.test/a.js" onload="bad()"></script><script src="http://metrics.test/b.js"></script><script src="javascript:bad()"></script>';
    assert.equal(loadFormIntegrations({win,settings:{scripts:code}}),true);
    const scripts=[...win.document.head.children];assert.equal(scripts.length,2);
    assert.ok(scripts.every(node=>node.tagName==='SCRIPT'));
    assert.equal(scripts[0].textContent,'window.measurement=1');
    assert.equal(scripts[1].src,'https://metrics.test/a.js');assert.equal(scripts[1].hasAttribute('onload'),false);
    dom.window.close();
});

test('one generated limit counts Unicode code points, and oversized snippets never load',()=>{
    const {dom}=fixture();const win=dom.window;
    assert.equal(FORM_MEASUREMENT_SCRIPT_LIMIT,JSON.parse(readFileSync(new URL('../../../automation/form_measurement_limits.json',import.meta.url))).scriptMaxLength);
    assert.equal(loadFormIntegrations({win,settings:{scripts:'x'.repeat(FORM_MEASUREMENT_SCRIPT_LIMIT+1)}}),false);
    assert.equal(win.document.querySelector('script'),null);
    dom.window.close();
});

for(const destination of ['/admin','/order?token=private','/form/other','/form/summer?preview=true']) test(`loaded code forces a document navigation before ${destination}`,()=>{
    const {dom}=fixture();const win=dom.window;const navigations=[];
    installFormIntegrationGuard(win,null,{navigate:(...args)=>navigations.push(args)});
    win.history.pushState({},'','#order-preview');assert.equal(win.location.hash,'#order-preview');
    win.history.pushState({},'',destination);
    assert.deepEqual(navigations,[[`https://tickets.test${destination}`,false]]);
    assert.equal(win.location.pathname,'/form/summer');dom.window.close();
});

test('SDK sign-in, cross-tab session and history traversal force reloads',()=>{
    for(const trigger of ['sdk','storage','popstate','hashchange','pageshow']){
        const {dom}=fixture();const win=dom.window;let callback;let reloads=0;
        installFormIntegrationGuard(win,{onAuthStateChange:fn=>{callback=fn;}},{reload:()=>reloads++});
        if(trigger==='sdk') callback('SIGNED_IN',{user:{id:'private'}});
        else if(trigger==='storage'){win.localStorage.setItem(AppConfig.Keys.auth,'present');win.dispatchEvent(new win.Event('storage'));}
        else if(trigger==='popstate'||trigger==='hashchange'){win.location.hash='order?token=private';win.dispatchEvent(new win.Event(trigger));}
        else {win.localStorage.setItem(AppConfig.Keys.auth,'present');win.dispatchEvent(new win.Event('pageshow'));}
        assert.equal(reloads,1,trigger);dom.window.close();
    }
});

test('seat reservations contribute only their public product after server confirmation',async()=>{
    const {dom,layer}=fixture();const win=dom.window;
    let settle;
    const reservation=new Promise(resolve=>{settle=resolve;});
    const session={payload:{ticket:[{spot:23,fields:[]}]},spotModels:new Map([['23',{title:'private seat',productModel:{id:14,title:'Balcony ticket',price:50,currencyCode:'CZK'}}]]),awaitPendingReservations:()=>reservation};
    layer.observe(session);await Promise.resolve();assert.equal(win.dataLayer,undefined);
    settle();await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(events(win)[0],{event:'add_to_cart',ecommerce:{currency:'CZK',items:[{item_id:'product_14',item_name:'Balcony ticket',price:50,quantity:1}],value:50}});
    assert.equal(JSON.stringify(win.dataLayer).includes('private'),false);
    assert.equal(JSON.stringify(win.dataLayer).includes('23'),false);
    dom.window.close();
});

test('failed reservations and disposed pages cannot emit late cart updates',async()=>{
    const {dom,layer}=fixture();const win=dom.window;
    layer.observe({payload,awaitPendingReservations:async()=>{throw new Error('failed');}});
    await new Promise(resolve=>setImmediate(resolve));assert.equal(win.dataLayer,undefined);
    layer.observe({payload,awaitPendingReservations:async()=>{}});layer.dispose();
    await new Promise(resolve=>setImmediate(resolve));assert.equal(win.dataLayer,undefined);
    dom.window.close();
});

test('executing a snippet runs fresh inline scripts but inserts none of its other markup',()=>{
    const dom=new JSDOM('<head></head><body></body>',{url:'https://tickets.test/form/summer',runScripts:'dangerously'});
    loadFormIntegrations({win:dom.window,settings:{scripts:'<h1>Ignore</h1><script>window.measured = 42</script>'}});
    assert.equal(dom.window.measured,42);assert.equal(dom.window.document.querySelector('h1'),null);dom.window.close();
});

 test('missing SDK auth observer fails closed',()=>{
   const {dom}=fixture();assert.equal(loadIntegrations({win:dom.window,settings:{gtm_container:'GTM-AB12'}}),false);dom.window.close();
 });
 test('a session created by an earlier snippet blocks all subsequent script insertion',()=>{
   const dom=new JSDOM('<head></head><body></body>',{url:'https://tickets.test/form/summer',runScripts:'dangerously'});
   loadFormIntegrations({win:dom.window,settings:{scripts:`<script>localStorage.setItem('${AppConfig.Keys.auth}', 'present')</script><script>window.unexpected=1</script>`}});
   assert.equal(dom.window.unexpected,undefined);assert.equal(dom.window.document.querySelectorAll('script').length,1);dom.window.close();
 });

for(const original of ['https://tickets.test/form/summer?handoff=private','https://tickets.test/form/summer#pay=private','https://tickets.test/form/summer?sale_opening=private']) test(`router cleanup cannot authorize a sensitive document: ${original}`,async()=>{
    const dom=new JSDOM('<head></head>',{url:original});const previous=globalThis.window;
    globalThis.window=dom.window;
    try{
        const module=await import(`../../src/components/forms/form_datalayer.js?entry=${encodeURIComponent(original)}`);
        dom.window.history.replaceState({},'','/form/summer');
        assert.equal(module.shouldLoadFormIntegrations(dom.window),false);
        assert.equal(module.loadFormIntegrations({win:dom.window,settings:{gtm_container:'GTM-AB12'},auth:{onAuthStateChange(){}}}),false);
        new module.FormDataLayer({win:dom.window,model,session:()=>false}).view();assert.equal(dom.window.dataLayer,undefined);
    }finally{globalThis.window=previous;dom.window.close();}
});

test('the HTML shell sale-opening marker survives early URL cleanup for the loading decision',async()=>{
    const dom=new JSDOM('<head></head>',{url:'https://tickets.test/form/summer'});const previous=globalThis.window;
    globalThis.window=dom.window;dom.window.__festappSaleOpeningLink='captured';
    try{
        const module=await import('../../src/components/forms/form_datalayer.js?sale-opening-entry');
        delete dom.window.__festappSaleOpeningLink;
        assert.equal(module.shouldLoadFormIntegrations(dom.window),false);
    }finally{globalThis.window=previous;dom.window.close();}
});

test('standing-area product metadata is counted once and observation never starts recovery',async()=>{
    const {dom,layer}=fixture();let options;
    const session={payload:{ticket:[{fields:[{product_type:14}]}]},state:{tickets:[{_blueprintProduct:{id:14,title:'Standing ticket',price:30,currency_code:'CZK'}}]},awaitPendingReservations:async value=>{options=value;}};
    layer.observe(session);await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(options,{recover:false});
    assert.deepEqual(events(dom.window)[0].ecommerce.items,[{item_id:'product_14',item_name:'Standing ticket',price:30,quantity:1}]);dom.window.close();
});

test('broken third-party dataLayer consumers cannot turn a confirmed order into a checkout exception',()=>{
    const {dom,layer}=fixture();const win=dom.window;
    for(const dataLayer of [{},Object.assign([],{push(){throw new Error('consumer failed');}})]){
        win.dataLayer=dataLayer;
        assert.doesNotThrow(()=>layer.confirmed({ticketOrder:{analytics:purchase,order:{payment_info:{amount:200}}}}));
        assert.equal(layer.emit({event:'form_submit_error'}),false);
    }
    dom.window.close();
});
