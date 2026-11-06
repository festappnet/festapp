import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

test('submitting the real preview never restores its old scroll over the confirmation', async () => {
  const dom = new JSDOM('<body><div id="form-page-container"><form></form></div></body>', {
    url: 'https://example.test/form/test?embed=1',
  });
  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.CustomEvent = dom.window.CustomEvent;
  window.scrollTo = () => {};
  const events = [];
  window.addEventListener('festapp-embed-scroll-state', event => events.push(event.detail.type));
  const [{ FormPage }, { FormNetwork }, { RouterService }, { OrderPreview }] = await Promise.all([
    import('../../src/components/forms/form_page.js'),
    import('../../src/components/forms/form_network.js'),
    import('../../src/services/router_service.js'),
    import('../../src/components/forms/order_preview.js'),
  ]);
  const originals = [FormNetwork.submitOrder, RouterService.goBackProgrammatically, RouterService.pushOverlayState];
  try {
    FormNetwork.submitOrder = async () => ({success: true, data: {code: 200}});
    RouterService.goBackProgrammatically = () => setTimeout(() => window.dispatchEvent(new window.PopStateEvent('popstate')), 0);
    RouterService.pushOverlayState = () => {};
    const page = new FormPage('form-page-container');
    page.currentSession = {payload: {form: 'test'}, awaitPendingReservations:async()=>{}, captureReservationCapability:()=>null, completeReservation:()=>{}};
    page.cleanup = () => {};
    page.renderForm = () => {};
    const form = document.querySelector('form');
    const model = {visibleFields: [], relatedFields: [], communicationTone: 'formal'};
    OrderPreview.show(form, model, {totalPrice: 0, currency: 'CZK'}, overlay => page.submitOrder(form, model, overlay),
      () => assert.equal(document.querySelector('.fullscreen-result-overlay'), null, 'preview cleanup must finish before the result'),
      {fields: [], ticket: []});
    document.querySelector('.btn-submit-order').click();
    await new Promise(resolve => setTimeout(resolve, 350));
    assert.ok(document.querySelector('.fullscreen-result-overlay .result-title'));
    assert.equal(events.includes('scroll-restore'), false, 'stale preview restoration scrolls the receipt past its icon');
    assert.deepEqual(events, ['scroll-save', 'scroll-discard']);
  } finally {
    [FormNetwork.submitOrder, RouterService.goBackProgrammatically, RouterService.pushOverlayState] = originals;
    dom.window.close();
  }
});

test('a successful fast submission keeps its confirmation visible after closing the preview', async () => {
  const dom = new JSDOM(`<!doctype html><html><body>
    <div id="form-page-container"></div>
    <div id="order-preview-overlay"></div>
  </body></html>`, { url: 'https://example.test/form/test' });

  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.CustomEvent = dom.window.CustomEvent;
  window.scrollTo = () => {};

  const [{ FormPage }, { FormNetwork }, { RouterService }] = await Promise.all([
    import('../../src/components/forms/form_page.js'),
    import('../../src/components/forms/form_network.js'),
    import('../../src/services/router_service.js'),
  ]);

  const originalSubmitOrder = FormNetwork.submitOrder;
  const originalGoBack = RouterService.goBackProgrammatically;
  const originalPushOverlayState = RouterService.pushOverlayState;

  try {
    FormNetwork.submitOrder = async () => ({ success: true, data: { code: 200 } });
    RouterService.goBackProgrammatically = () => {
      setTimeout(() => window.dispatchEvent(new window.PopStateEvent('popstate')), 0);
    };
    RouterService.pushOverlayState = () => {};

    const page = new FormPage('form-page-container');
    page.currentSession = { payload: { form: 'test' }, awaitPendingReservations:async()=>{}, captureReservationCapability:()=>null, completeReservation:()=>{} };
    page.cleanup = () => {};
    page.renderForm = () => {};

    page.submitOrder(document.createElement('form'), {
      communicationTone: 'formal',
      visibleFields: [],
    });

    await new Promise(resolve => setTimeout(resolve, 25));

    assert.ok(
      document.querySelector('.fullscreen-result-overlay .result-title'),
      'the confirmation disappeared when the delayed preview popstate arrived',
    );
  } finally {
    FormNetwork.submitOrder = originalSubmitOrder;
    RouterService.goBackProgrammatically = originalGoBack;
    RouterService.pushOverlayState = originalPushOverlayState;
    dom.window.close();
  }
});

for (const scenario of ['success', 'server-error', 'transport-error', 'demo', 'render-error']) {
  test(`analytics outcome follows the server response: ${scenario}`, async () => {
    const dom = new JSDOM('<body><div id="form-page-container"></div></body>', {url:'https://example.test/form/test?embed=1'});
    global.window=dom.window; global.document=dom.window.document;
    global.HTMLElement=dom.window.HTMLElement; global.CustomEvent=dom.window.CustomEvent;
    window.scrollTo=()=>{};
    const [{FormPage},{FormNetwork}] = await Promise.all([
      import('../../src/components/forms/form_page.js'), import('../../src/components/forms/form_network.js')]);
    const original=FormNetwork.submitOrder;
    try {
      let resolveRequest, rejectRequest;
      FormNetwork.submitOrder=()=>new Promise((resolve,reject)=>{resolveRequest=resolve;rejectRequest=reject;});
      const page=new FormPage('form-page-container');
      const events=[];
      page.analytics={confirmed:()=>events.push('confirmed'),emit:payload=>events.push(payload.event)};
      page.currentSession={payload:{form:'test'}, awaitPendingReservations:async()=>{}, captureReservationCapability:()=>null, completeReservation:()=>{}};
      page.cleanup=()=>{};
      page.closePreview=()=>{};
      let finish;
      const finished=new Promise(resolve=>{finish=resolve;});
      let renders=0;
      page.showFullScreenResult=()=>{
        if(scenario==='render-error' && renders++===0) throw new Error('Rendering failed after commit');
        finish();
      };
      page.submitOrder(document.createElement('form'), {demoSimulation:scenario==='demo'});
      await new Promise(resolve=>setImmediate(resolve));
      assert.deepEqual(events,[], 'no success on click or while request is pending');
      if(scenario==='transport-error') rejectRequest(new Error('Unknown outcome'));
      else if(scenario!=='demo') resolveRequest({success:scenario!=='server-error',data:{code:scenario==='server-error'?400:200}});
      await Promise.race([finished,new Promise((_,reject)=>setTimeout(()=>reject(new Error('Result timeout')),1500))]);
      assert.deepEqual(events, scenario==='demo'?[]:[['server-error','transport-error'].includes(scenario)?'form_submit_error':'confirmed']);
    } finally {
      FormNetwork.submitOrder=original;
      dom.window.close();
    }
  });
}

test('real dataLayer emits purchase only after backend confirmation and survives a result-render failure', async () => {
  const dom=new JSDOM('<body><div id="form-page-container"></div></body>',{url:'https://example.test/form/summer'});
  global.window=dom.window;global.document=dom.window.document;global.HTMLElement=dom.window.HTMLElement;global.CustomEvent=dom.window.CustomEvent;
  window.scrollTo=()=>{};
  const [{FormPage},{FormNetwork},{FormDataLayer}]=await Promise.all([
    import('../../src/components/forms/form_page.js'),import('../../src/components/forms/form_network.js'),import('../../src/components/forms/form_datalayer.js')]);
  const original=FormNetwork.submitOrder;
  try{
    let confirm;
    FormNetwork.submitOrder=()=>new Promise(resolve=>{confirm=resolve;});
    const page=new FormPage('form-page-container');
    page.currentSession={payload:{form:'private',email:'private@example.test'},awaitPendingReservations:async()=>{},captureReservationCapability:()=>null,completeReservation:()=>{}};
    const sent=[];
    page.analytics=new FormDataLayer({win:window,model:{id:1,visibleFields:[],data:{analytics:{enabled:true,organization_allowed:true,runtime_supported:true,eligible:true,valid_for_seconds:60}}},bridge:{measurementEpoch:()=> 'fixture-lease',measurementAllowed:()=>true,track:p=>{sent.push(p);return true;}},session:()=>false});
    page.closePreview=()=>{};page.cleanup=()=>{};
    let finish;const finished=new Promise(resolve=>{finish=resolve;});let renders=0;
    page.showFullScreenResult=()=>{if(renders++===0)throw new Error('render failed');finish();};
    page.submitOrder(document.createElement('form'),{});
    await new Promise(resolve=>setImmediate(resolve));assert.equal(window.dataLayer,undefined);
    confirm({success:true,data:{ticketOrder:{order:{payment_info:{amount:200}},analytics:{event:'purchase',ecommerce:{transaction_id:'c5c624bd-01b6-4dcf-9bf9-00dcb73a7b44',currency:'CZK',payment_type:'bank_transfer',items:[{item_id:'product_12',item_name:'Concert ticket',price:100,quantity:2}]}}}}});
    await finished;
    assert.deepEqual(sent.filter(item=>item.event).map(item=>item.event),['page_view','purchase']);
    assert.equal(JSON.stringify(sent).includes('private'),false);
  }finally{FormNetwork.submitOrder=original;dom.window.close();}
});
