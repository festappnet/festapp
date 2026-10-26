import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { FormModel } from '../../src/components/forms/form_models.js';
import { FormSession } from '../../src/components/forms/form_session.js';
import { FormRenderer } from '../../src/components/forms/form_renderer.js';
import { renderWaitlistControls, prepareOfferSession, ticketLabel } from '../../src/components/forms/waitlist_form.js';
import { waitlistRegistrationPayload } from '../../src/components/forms/waitlist_commands.js';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';
register('../css_loader.mjs', import.meta.url);
LocalizationService.translations = JSON.parse(readFileSync(new URL('../../public/assets/translations/cs.json', import.meta.url)));
LocalizationService.currentLocale = 'cs';
if (!globalThis.CustomEvent) globalThis.CustomEvent = class extends Event { constructor(type, options) { super(type); this.detail = options?.detail; } };
const fields = [
    { id: 1, type: 'ticket', data: { max_tickets: 3 } },
    { id: 2, type: 'name', title: 'Jméno', is_ticket_field: true, is_required: true },
    { id: 3, type: 'product_type', title: 'Ubytování', is_ticket_field: true, is_required: true, data: { default_value: '9' }, product_type_data: { products: [{ id: 9, title: 'Pokoj', price: 200, currency_code: 'CZK' }] } },
    { id: 4, type: 'email', title: 'E-mail', is_required: true },
];
function dom() {
    const d = new JSDOM('<main id="host"></main>', { url: 'https://example.test/form/test', pretendToBeVisual: true });
    globalThis.document = d.window.document; globalThis.window = d.window; globalThis.HTMLElement = d.window.HTMLElement;
    window.scrollTo = () => {};
    globalThis.requestAnimationFrame = d.window.requestAnimationFrame.bind(d.window);
    return d;
}
const initialDom = dom();
const { OrderPreview } = await import('../../src/components/forms/order_preview.js');
initialDom.window.close();

test('regular occupancy includes waiting registrations; waitlist mode hides occupancy', () => {
    const d = dom();
    for (const registrationMode of ['regular', 'waitlist']) {
        const model = new FormModel({ registrationMode, fields, capacity: { showRemaining: true, limit: 12, occupiedPeople: 11, offeredPlaces: 0, waitingPeople: 3, remainingPublic: registrationMode === 'regular' ? 1 : 0 } });
        const current = new FormSession(model);
        const host = document.querySelector('main');
        FormRenderer.render(host, current, model, false, {});
        renderWaitlistControls({ host, currentSession: current }, model);
        if (registrationMode === 'waitlist') assert.equal(host.querySelector('.form-occupancy'), null);
        else assert.equal(host.querySelector('.form-occupancy').textContent, 'Obsazenost: 14 z 12');
        assert.ok(host.querySelector('form').firstElementChild.classList.contains('form-registration-status'));
        if (registrationMode === 'waitlist') assert.match(host.querySelector('.waitlist-intro').textContent, /e-mailem nabídku/);
    }
    d.window.close();
});
test('occupancy includes active offer holds and reflects release without changing server mode', () => {
    const d = dom(); const host = document.querySelector('main');
    for (const offeredPlaces of [1, 0]) {
        const model = new FormModel({ registrationMode: 'regular', fields, capacity: {
            showRemaining: true, limit: 11, occupiedPeople: 10, offeredPlaces, remainingPublic: 1,
        } });
        const current = new FormSession(model);
        FormRenderer.render(host, current, model, false, {});
        renderWaitlistControls({ host, currentSession: current }, model);
        assert.equal(host.querySelector('.form-occupancy').textContent, `Obsazenost: ${10 + offeredPlaces} z 11`);
        assert.equal(model.registrationMode, 'regular');
        assert.equal(model.capacity.remainingPublic, 1);
        assert.equal(model.capacity.occupiedPeople, 10);
        assert.equal(host.querySelector('.form-registration-status.is-waitlist'), null);
    }
    d.window.close();
});
test('waiting products keep labeled disabled choices, no default, no required validation or payload', () => {
    const d = dom();
    const model = new FormModel({ registrationMode: 'waitlist', fields });
    const current = new FormSession(model);
    const host = document.querySelector('main');
    FormRenderer.render(host, current, model, false, {});
    const product = host.querySelector('.waitlist-product-options');
    assert.ok(product); assert.match(product.textContent, /Ubytování/); assert.match(product.textContent, /Pokoj/);
    renderWaitlistControls({host, currentSession: current}, model);
    assert.match(host.querySelector('.waitlist-product-notice').textContent, /Podrobnosti přihlášky a produkty doplníte/);
    assert.equal(product.querySelector('.waitlist-product-notice'), null);
    const input = product.querySelector('input');
    assert.ok(input.disabled); assert.equal(input.checked, false); assert.equal(input.required, false);
    assert.equal(product.disabled, true);
    assert.equal(product.querySelector('.btn-clear-selection'), null);
    current.state.tickets = [{ fields: [{ name: 'Alex', _subFieldId: 2 }] }, { fields: [{ name: 'Robin', _subFieldId: 2 }] }];
    current._syncPayloadFromState();
    const payload = waitlistRegistrationPayload(current);
    assert.deepEqual(payload.tickets, [{ fields: [{ 2: 'Alex' }] }, { fields: [{ 2: 'Robin' }] }]);
    assert.equal(payload.payment_type, undefined); assert.equal(payload.currency_code, undefined);
    const prepared = OrderPreview._prepareData(null, model, current.state, current.payload);
    host.innerHTML = OrderPreview._render(prepared);
    assert.match(host.textContent, /Alex/); assert.match(host.textContent, /Robin/);
    assert.equal(host.querySelector('.preview-total-price'), null);
    assert.equal(host.querySelector('input[name="payment_type"]'), null);
    assert.equal(host.querySelector('.btn-submit-order').textContent.trim(), 'Přihlásit mezi náhradníky');
    assert.doesNotMatch(host.textContent, /Pokoj/);
    d.window.close();
});
test('classic preview and result retain finance while waitlist shares result with accurate wording', () => {
    const d = dom(); const host = document.querySelector('main');
    const model = new FormModel({ registrationMode: 'regular', fields });
    const current = new FormSession(model);
    host.innerHTML = OrderPreview._render(OrderPreview._prepareData(null, model, { totalPrice: 200, currency: 'CZK' }, current.payload));
    assert.ok(host.querySelector('.preview-total-price'));
    const result = { ticketOrder: { order: { order_symbol: 'ABC123', data: { email: 'test@example.invalid' } } }, payment_qr: { amount: 200, currency_code: 'CZK', account_number: '123' } };
    OrderResult.render(host, true, result, model, () => {});
    assert.ok(host.querySelector('.result-payment-card'));
    model.registrationMode = 'waitlist';
    OrderResult.render(host, true, result, model, () => {});
    assert.equal(host.querySelector('.result-title').textContent, 'Jste v pořadníku náhradníků');
    assert.match(host.querySelector('.result-subtitle').textContent, /místo ještě není potvrzené/);
    assert.match(host.querySelector('.result-order-symbol').textContent, /ABC123/);
    assert.equal(host.querySelector('.result-payment-card'), null);
    OrderResult.render(host, false, { errorCode: 'WAITLIST_NOT_AVAILABLE' }, model, () => {});
    assert.match(host.querySelector('.result-subtitle').textContent, /nyní není dostupné/);
    d.window.close();
});
test('single management entry needs no checkbox, multi-entry selects IDs and never displays internal IDs', async () => {
    const d = dom(); const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('host'); page.waitlistScope = { orderId: 20, token: 'secret' };
    const calls = []; page.resolveWaitlist = (...args) => calls.push(args);
    const first = { id: 8837, lifecycle: 'waiting', answers: { fields: [] } };
    page.renderWaitlistManagement({ tickets: [first] });
    assert.equal(page.host.querySelector('input'), null);
    assert.doesNotMatch(page.host.textContent, /8837/);
    assert.match(page.host.textContent, /Vaše přihláška/);
    page.host.querySelector('button').click();
    assert.deepEqual(calls.pop(), ['withdraw', [8837]]);
    page.renderWaitlistManagement({ tickets: [first, { id: 9000, lifecycle: 'waiting', answers: { fields: [{2: 'Robin'}] } }] });
    assert.ok(page.host.querySelector('button').disabled);
    assert.match(page.host.textContent, /Vyberte přihlášky/);
    page.host.querySelectorAll('input')[1].click(); page.host.querySelector('button').click();
    assert.deepEqual(calls.pop(), ['withdraw', [9000]]);
    page.renderWaitlistManagement({ tickets: [{ ...first, lifecycle: 'withdrawn' }] });
    assert.equal(page.host.querySelector('.result-title').textContent, 'Vyřazeno z náhradníků');
    assert.match(page.host.querySelector('.result-subtitle').textContent, /Vyřazené přihlášky/);
    assert.equal(page.host.querySelector('button'), null);
    assert.equal(ticketLabel({ id: 7777 }), 'Vaše přihláška');
    d.window.close();
});
test('withdraw and decline use shared preview and only execute after its confirmation', async () => {
    const d = dom(); const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('host'); page.waitlistScope = { orderId: 20, token: 'secret' };
    page.waitlistBundle = { form: { fields }, tickets: [{ id: 8837, lifecycle: 'waiting', answers: { fields: [{2: '<Alex>'}] } }] };
    page.init = async () => {};
    const calls = []; page.waitlistCommands = { command: async (...args) => calls.push(args) };
    const show = OrderPreview.show;
    let confirm;
    try {
        OrderPreview.show = (form, model, prices, callback, close, payload, presentation) => {
            confirm = callback;
            assert.equal(model.registrationMode, 'waitlist');
            assert.deepEqual(presentation.people, ['<Alex>']);
            assert.ok(presentation.explanation);
        };
        for (const operation of ['withdraw', 'decline']) {
            const before = calls.length;
            await page.resolveWaitlist(operation, [8837]);
            assert.equal(calls.length, before);
            const overlay = document.createElement('div'); overlay.innerHTML = '<button class="btn-submit-order"></button>';
            await confirm(overlay);
            assert.deepEqual(calls.at(-1), [operation, { ...page.waitlistScope, ticketIds: [8837] }]);
        }
    } finally { OrderPreview.show = show; d.window.close(); }
});

test('waitlist validates into the classic preview and submits personal payload through the shared result lifecycle', async () => {
    const d = dom();
    const [{ FormPage }, { RouterService }, { FormValidator }, { FormNetwork }] = await Promise.all([
        import('../../src/components/forms/form_page.js'), import('../../src/services/router_service.js'),
        import('../../src/components/forms/form_validator.js'), import('../../src/components/forms/form_network.js'),
    ]);
    const model = new FormModel({ key: 'test-key', registrationMode: 'waitlist', fields });
    const current = new FormSession(model);
    current.state.fields.set('4', 'alex@example.invalid');
    current.state.tickets = [{ fields: [{name: 'Alex', _subFieldId: 2}] }]; current._syncPayloadFromState();
    const page = new FormPage('host'); page.currentSession = current;
    page.cleanup = () => {}; page.renderForm = () => {};
    const original = { show: OrderPreview.show, valid: FormValidator.validateAndShowErrors, back: RouterService.goBackProgrammatically, push: RouterService.pushOverlayState, network: FormNetwork.submitOrder };
    let registered = 0; let confirmation;
    try {
        FormValidator.validateAndShowErrors = () => true;
        window.confirm = () => { throw new Error('Native confirmation is forbidden'); };
        FormNetwork.submitOrder = () => { throw new Error('Waitlist must not create a payable order'); };
        RouterService.pushOverlayState = () => {};
        RouterService.goBackProgrammatically = () => setTimeout(() => window.dispatchEvent(new window.PopStateEvent('popstate')), 0);
        page.waitlistCommands = { command: async (operation, payload) => {
            registered++; assert.equal(operation, 'register');
            assert.deepEqual(payload.tickets, [{ fields: [{ 2: 'Alex' }] }]);
            assert.equal(payload.email, 'alex@example.invalid');
            assert.equal(payload.ticket, undefined);
            return { code: 200, order: { order_symbol: 'ABC123' } };
        } };
        OrderPreview.show = (form, passedModel, price, callback) => { assert.equal(passedModel, model); confirmation = callback; };
        page._previewModulePromise = Promise.resolve({ OrderPreview });
        const form = document.createElement('form');
        page.validateAndSubmit(form, model);
        await new Promise(resolve => setTimeout(resolve, 0));
        assert.equal(registered, 0); assert.equal(typeof confirmation, 'function');
        const overlay = document.createElement('div'); overlay.id = 'order-preview-overlay'; document.body.appendChild(overlay);
        confirmation(overlay);
        await new Promise(resolve => setTimeout(resolve, 25));
        assert.equal(registered, 1);
        assert.equal(document.querySelector('.fullscreen-result-overlay .result-title').textContent, 'Jste v pořadníku náhradníků');
        assert.equal(document.querySelector('.result-payment-card'), null);
        assert.equal(document.querySelector('.fullscreen-loader-overlay'), null);
    } finally {
        OrderPreview.show = original.show; FormValidator.validateAndShowErrors = original.valid;
        RouterService.goBackProgrammatically = original.back; RouterService.pushOverlayState = original.push;
        FormNetwork.submitOrder = original.network; d.window.close();
    }
});

test('management and confirmation retain event and enrollment context without interpreting customer answers as markup', async () => {
    const d = dom(); const { FormPage } = await import('../../src/components/forms/form_page.js');
    const page = new FormPage('host'); page.waitlistScope = { orderId: 20 };
    const bundle = {
        occasionTitle: 'Víkend <setkání>', orderSymbol: 'ABC123', form: { fields },
        tickets: [{ id: 8837, lifecycle: 'waiting', answers: { fields: [{2: 'Alex'}] } }],
    };
    page.applyTheme = () => {};
    page.renderWaitlistManagement(bundle);
    assert.equal(page.host.querySelector('.waitlist-context h1').textContent, 'Víkend <setkání>');
    assert.equal(page.host.querySelector('.waitlist-order-symbol').textContent, 'Symbol přihlášky: ABC123');
    assert.equal(page.host.querySelector('.waitlist-person-row strong').textContent, 'Alex');
    assert.equal(page.host.querySelector('.waitlist-person-status').textContent, 'Zatím jste náhradník, místo ještě není potvrzené.');
    assert.equal(page.host.querySelector('.waitlist-withdraw').textContent, 'Nemám již zájem se zúčastnit');
    assert.equal(page.host.querySelector('setkání'), null);
    const original = OrderPreview.show;
    try {
        OrderPreview.show = (form, model, price, confirm, close, payload, presentation) => {
            assert.equal(presentation.occasionTitle, bundle.occasionTitle);
            assert.equal(presentation.orderSymbol, bundle.orderSymbol);
            assert.match(presentation.explanation, /^Ukončíte čekání na místo/);
            assert.equal(presentation.title, 'Nemám již zájem se zúčastnit');
        };
        await page.resolveWaitlist('withdraw', [8837]);
    } finally { OrderPreview.show = original; }
    page.waitlistScope = { offerId: 'expired' };
    page.renderWaitlistManagement({ offerStatus: 'expired', form: null, tickets: [] });
    assert.equal(page.host.querySelector('.waitlist-context'), null);
    assert.equal(page.host.querySelector('button'), null);
    d.window.close();
});

test('display names use own ticket names only, with a natural single enrollment fallback', () => {
    const form = { fields: [
        {id: 10, type: 'name'},
        {id: 2, type: 'name', is_ticket_field: true},
        {id: 5, type: 'surname', is_ticket_field: true},
        {id: 6, type: 'note', is_ticket_field: true},
        {id: 7, type: 'id_document', is_ticket_field: true},
    ] };
    const person = { id: 8837, answers: { fields: [{10: 'Buyer'}, {2: 'Alex'}, {5: 'Novotný'}, {6: 'Private note'}, {7: 'AB123'}] } };
    assert.equal(ticketLabel(person, 0, form, 1), 'Alex Novotný');
    assert.equal(ticketLabel({ ...person, answers: { fields: [{6:'Private note'}] } }, 0, form, 1), 'Vaše přihláška');
    assert.equal(ticketLabel({ id: 9000, answers: {fields:[{2:'Robin'}]} }, 1, form, 2), 'Robin');
    assert.equal(ticketLabel({ id: 9000, displayName: 'Server Name' }, 1, form, 2), 'Server Name');
});

test('waiting success and shared preview show occasion and enrollment context without a numbered single person', () => {
    const d = dom(); const host = document.querySelector('main');
    const model = new FormModel({ registrationMode: 'waitlist', occasion: {title:'Víkend setkání'}, fields });
    const session = new FormSession(model);
    session.state.tickets = [{ fields: [{name: 'Alex', _subFieldId: 2}] }];
    session._syncPayloadFromState();
    const prepared = OrderPreview._prepareData(null, model, session.state, session.payload);
    host.innerHTML = OrderPreview._render(prepared);
    assert.match(host.textContent, /Víkend setkání/);
    assert.match(host.textContent, /Vaše přihláška/);
    assert.doesNotMatch(host.textContent, /Osoba 1/);
    OrderResult.render(host, true, {ticketOrder:{order:{order_symbol:'ABC123'}}}, model, () => {});
    assert.equal(host.querySelector('.result-occasion-title').textContent, 'Víkend setkání');
    assert.equal(host.querySelector('.result-order-symbol').textContent, 'Symbol přihlášky: ABC123');
    assert.match(host.querySelector('.result-subtitle').textContent, /místo ještě není potvrzené/);
    d.window.close();
});

test('shared preview resolves empty standard labels for both modes and keeps custom labels', () => {
    const d = dom(); const host = document.querySelector('main');
    for (const registrationMode of ['regular', 'waitlist']) {
        const model = new FormModel({ registrationMode, fields: [
            {id:1,type:'ticket'}, {id:2,type:'surname',title:null,is_ticket_field:true},
            {id:3,type:'name',title:'   ',is_ticket_field:true},
            {id:4,type:'email',title:''}, {id:5,type:'phone',title:'Váš telefon'},
        ] });
        const payload = {fields:[{4:'alex@example.invalid'},{5:'123'}],ticket:[{fields:[
            {_subFieldId:2,surname:'Novotný'}, {_subFieldId:3,name:'Alex'},
        ]}]};
        const prepared = OrderPreview._prepareData(null, model, {totalPrice:0,currency:'CZK'}, payload);
        host.innerHTML = OrderPreview._render(prepared);
        assert.deepEqual([...host.querySelectorAll('.preview-label')].map(el=>el.textContent), ['E-mail:', 'Váš telefon:', 'Příjmení:', 'Jméno:']);
        assert.doesNotMatch(host.textContent, /null:|undefined:/);
    }
    d.window.close();
});

test('empty waitlist cards disappear while multiple meaningful own answers and count remain', () => {
    const d = dom(); const host = document.querySelector('main');
    const model = new FormModel({registrationMode:'waitlist',fields:[
        {id:1,type:'ticket'}, {id:2,type:'name',is_ticket_field:true},
        {id:3,type:'text',title:'Diet',is_ticket_field:true}, {id:4,type:'text',title:'Access',is_ticket_field:true},
    ]});
    const price={totalPrice:0,currency:'CZK'};
    const render=ticket=>{host.innerHTML=OrderPreview._render(OrderPreview._prepareData(null,model,price,{fields:[],ticket}));};
    render([{fields:[]}]);
    assert.equal(host.querySelector('.ticket-card'),null);
    assert.equal(host.querySelector('.preview-registration-count'),null);
    render([{fields:[]},{fields:[{_subFieldId:2,name:'Robin'},{_subFieldId:3,text:'Vegan'},{_subFieldId:4,text:'Step-free'}]}]);
    assert.equal(host.querySelectorAll('.ticket-card').length,1);
    assert.equal(host.querySelector('.ticket-header-title').textContent,'Přihláška 2');
    assert.equal(host.querySelector('.preview-registration-count').textContent,'Počet přihlášek: 2');
    assert.match(host.textContent,/Robin/);assert.match(host.textContent,/Vegan/);assert.match(host.textContent,/Step-free/);
    model.registrationMode='regular';render([{fields:[]}]);
    assert.equal(host.querySelectorAll('.ticket-card').length,1);
    d.window.close();
});

test('one distinct accessible product notice sits outside all disabled groups', () => {
    const d=dom(); const host=document.querySelector('main');
    const model=new FormModel({registrationMode:'waitlist',data:{design:{is_card_design:true}},fields:[...fields,
        {...fields[2],id:6,title:'Strava'},
    ]});
    const current=new FormSession(model);
    FormRenderer.render(host,current,model,false,{});
    renderWaitlistControls({host,currentSession:current},model);
    const groups=[...host.querySelectorAll('.waitlist-product-options')];
    assert.equal(groups.length,2);
    assert.equal(host.querySelectorAll('.waitlist-product-notice').length,1);
    const note=host.querySelector('.waitlist-product-notice');
    assert.equal(note.getAttribute('role'),'note');
    assert.equal(note.closest('.form-field-card'), null);
    current._emitStateChanged();
    assert.equal(host.querySelectorAll('.waitlist-product-notice').length,1);
    assert.equal(note.nextElementSibling.contains(groups[0]),true);
    assert.equal(host.querySelector('.form-registration-status').contains(note),false);
    for(const group of groups){assert.equal(group.getAttribute('aria-describedby'),note.id);assert.equal(group.contains(note),false);assert.ok(group.disabled);}
    assert.equal(host.querySelector('.form-registration-status h2'),null);
    assert.match(host.querySelector('.waitlist-mode-label').textContent,/režimu náhradníků/);
    assert.doesNotMatch(note.textContent,/zaplat/);
    d.window.close();
});

test('waitlist copy follows the existing formal/informal form tone across registration, preview, result and management', async () => {
    const d=dom(); const host=document.querySelector('main');const {FormPage}=await import('../../src/components/forms/form_page.js');
    for(const tone of ['formal','informal']) for(const count of [1,2]) {
        const model=new FormModel({registrationMode:'waitlist',data:{communication_tone:tone},fields});
        const current=new FormSession(model);FormRenderer.render(host,current,model,false,{});renderWaitlistControls({host,currentSession:current},model);
        assert.match(host.querySelector('.waitlist-intro').textContent,tone==='informal'?/pošleme ti/:/pošleme vám/);
        assert.match(host.querySelector('.waitlist-product-notice').textContent,tone==='informal'?/doplníš/:/doplníte/);
        current.state.tickets=Array.from({length:count},(_,i)=>({fields:[{name:`Name ${i}`,_subFieldId:2}]}));current._syncPayloadFromState();
        host.innerHTML=OrderPreview._render(OrderPreview._prepareData(null,model,current.state,current.payload));
        assert.match(host.textContent,tone==='informal'?/pošleme ti/:/pošleme vám/);
        OrderResult.render(host,true,{},model,()=>{});
        assert.equal(host.querySelector('.result-title').textContent,tone==='informal'?'Jsi v pořadníku náhradníků':'Jste v pořadníku náhradníků');
        assert.doesNotMatch(host.querySelector('.result-subtitle').textContent,/Zde vid/);
        const page=new FormPage(host);page.waitlistScope={orderId:1};page.applyTheme=()=>{};
        page.renderWaitlistManagement({form:{data:{communication_tone:tone},fields},tickets:[{id:1,lifecycle:'waiting',answers:{fields:[]}}]});
        assert.match(host.textContent,tone==='informal'?/pošleme ti/:/pošleme vám/);
    }
    d.window.close();
});

test('return from successful result refetches capacity and server registration mode before displaying the form',async t=>{
    const d=dom(); const [{FormPage},{DbForms},{RouterService},{RightsService},{SeoService}]=await Promise.all([
        import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),import('../../src/services/router_service.js'),import('../../src/services/rights_service.js'),import('../../src/services/seo_service.js')]);
    t.mock.method(RouterService,'pushOverlayState',()=>{});
    t.mock.method(RouterService,'goBackProgrammatically',()=>window.dispatchEvent(new window.PopStateEvent('popstate')));
    t.mock.method(RightsService,'updateAppData',async()=>{});t.mock.method(RightsService,'canSeeReservations',()=>false);t.mock.method(SeoService,'updateMetaTags',()=>{});
    let finish;let requests=0;t.mock.method(DbForms,'getFormByLink',()=>{requests++;return new Promise(resolve=>finish=resolve);});
    const page=new FormPage('host');page.currentLink='test';page.applyTheme=()=>{};const rendered=[];page.renderForm=model=>{rendered.push(model);page.host.textContent=model.registrationMode;};
    page.host.textContent='old regular form';page.showFullScreenResult(true,{},new FormModel({registrationMode:'regular',fields}));
    document.querySelector('.btn-back-to-form').click();
    assert.equal(requests,1);assert.equal(rendered.length,0);assert.doesNotMatch(page.host.textContent,/old regular/);
    finish(new FormModel({registrationMode:'waitlist',capacity:{limit:12,occupiedPeople:12,remainingPublic:0},fields}));await new Promise(resolve=>setTimeout(resolve,0));
    assert.equal(rendered[0].registrationMode,'waitlist');assert.equal(rendered[0].capacity.occupiedPeople,12);assert.equal(document.querySelector('.fullscreen-result-overlay'),null);
    d.window.close();
});


test('offer acceptance uses singular or selected-people label in form and shared preview', () => {
    const d = dom();
    for (const count of [1, 2]) {
        const model = new FormModel({ registrationMode: 'regular', fields });
        model.selectedTicketIds = Array.from({ length: count }, (_, i) => i + 1);
        model.offerBundle = { pendingCount: count, expiresAt: '2030-01-01', tickets: model.selectedTicketIds.map(id => ({ id, lifecycle: 'offered', displayName: `Jméno ${id}` })), slots: model.selectedTicketIds.map(ticketId => ({ ticketId, outcome: 'pending' })) };
        const current = new FormSession(model);
        current.state.tickets = model.selectedTicketIds.map(ticketId => ({ ticketId, fields: [{ name: `Jméno ${ticketId}`, _subFieldId: 2 }] }));
        current._syncPayloadFromState();
        const host = document.querySelector('main');
        FormRenderer.render(host, current, model, false, {});
        renderWaitlistControls({ host, currentSession: current }, model);
        const expected = count === 1 ? 'Potvrdit přihlášení' : 'Potvrdit vybrané přihlášky';
        assert.equal(host.querySelector('.btn-submit').textContent, expected);
        host.innerHTML = OrderPreview._render(OrderPreview._prepareData(null, model, current.state, current.payload));
        assert.equal(host.querySelector('.btn-submit-order').textContent.trim(), expected);
    }
    d.window.close();
});


test('offer facts localize expiry, single acceptance needs no selector and multi selection preserves drafts', () => {
    const d=dom(); const host=document.querySelector('main');
    const model=new FormModel({registrationMode:'offer',fields,capacity:{showRemaining:true,limit:11,occupiedPeople:10,offeredPlaces:1,remainingPublic:0}});
    model.offerBundle={pendingCount:1, expiresAt:'2026-10-14T19:52:28Z',timeZone:'Europe/Prague',slots:[{ticketId:10,outcome:'pending'}],tickets:[{id:10,lifecycle:'offered',displayName:'Junák',answers:{fields:[]}}]};
    let current=new FormSession(model); prepareOfferSession(current,model);
    const page={host,currentSession:current,renderForm:()=>{},resolveWaitlist:()=>{}};
    FormRenderer.render(host,current,model,false,{});renderWaitlistControls(page,model);
    assert.match(host.querySelector('.waitlist-offer-facts').textContent,/14.*10.*2026.*21:52/);
    assert.equal(host.querySelector('.form-occupancy'),null);
    assert.equal(host.querySelector('.waitlist-mode-label'),null);
    assert.match(host.querySelector('.waitlist-offer-facts').textContent,/Nabídnutá místa1/);
    assert.doesNotMatch(host.querySelector('.form-registration-status').textContent,/Obsazenost|Zbývající místa|Zařazení mezi náhradníky/);
    assert.equal(host.querySelector('.waitlist-people legend'),null);
    assert.equal(host.querySelector('.waitlist-people input'),null);
    assert.equal(host.querySelector('.waitlist-person-row strong').textContent,'Junák');
    assert.deepEqual(model.selectedTicketIds,[10]);
    assert.equal(host.querySelector('.waitlist-decline').textContent,'Odmítnout nabídku');
    model.offerBundle.pendingCount=2;
    model.offerBundle.tickets.push({id:11,lifecycle:'waiting',displayName:'Robin',answers:{fields:[]}});
    current=new FormSession(model);prepareOfferSession(current,model);page.currentSession=current;
    FormRenderer.render(host,current,model,false,{});renderWaitlistControls(page,model);
    assert.ok(host.querySelector('.waitlist-people legend'));
    host.querySelectorAll('.waitlist-people input')[1].click();
    assert.deepEqual(model.selectedTicketIds,[10,11]);
    assert.ok(model.ticketDrafts.has(10));
    d.window.close();
});

test('terminal outcomes reuse order result without waiting promise and preserve context', async () => {
    const d=dom();const {FormPage}=await import('../../src/components/forms/form_page.js');
    const page=new FormPage('host');page.waitlistScope={offerId:'done'};
    for(const offerStatus of ['declined','cancelled','expired','accepted']) {
        page.renderWaitlistManagement({offerStatus,form:null,occasionTitle:'Setkání',orderSymbol:'ABC123',communicationTone:'informal',tickets:[]});
        assert.ok(page.host.querySelector('.result-container'));
        assert.equal(page.host.querySelector('.result-occasion-title').textContent,'Setkání');
        assert.match(page.host.querySelector('.result-order-symbol').textContent,/ABC123/);
        assert.doesNotMatch(page.host.querySelector('.result-subtitle').textContent,/Až.*nabídn|Waitlist\./);
    }
    d.window.close();
});


test('terminal back action removes capability and fetches fresh normal form capacity', async t => {
    const d=dom();const [{FormPage},{DbForms},{RightsService},{SeoService}]=await Promise.all([
        import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),import('../../src/services/rights_service.js'),import('../../src/services/seo_service.js')]);
    window.history.replaceState(null,'','/order?lang=cs&waitlist=1&token='+ 'a'.repeat(64)+'&offer_id=11111111-1111-1111-1111-111111111111');
    t.mock.method(RightsService,'updateAppData',async()=>{});t.mock.method(RightsService,'canSeeReservations',()=>false);t.mock.method(SeoService,'updateMetaTags',()=>{});
    let requests=0;t.mock.method(DbForms,'getFormByLink',async link=>{assert.equal(link,'test');requests++;return new FormModel({registrationMode:'waitlist',capacity:{limit:12,occupiedPeople:12,remainingPublic:0},fields});});
    const page=new FormPage('host');page.currentLink='test';page.waitlistScope={offerId:'old'};page.applyTheme=()=>{};
    let rendered;page.renderForm=model=>rendered=model;
    page.renderWaitlistManagement({offerStatus:'declined',form:null,formLink:'test',communicationTone:'informal',occasionTitle:'Setkání',orderSymbol:'ABC123',tickets:[]});
    assert.equal(page.host.querySelector('.result-occasion-title').textContent,'Setkání');
    assert.match(page.host.querySelector('.result-order-symbol').textContent,/ABC123/);
    page.host.querySelector('.btn-back-to-form').click();await new Promise(resolve=>setTimeout(resolve,0));
    assert.equal(requests,1);assert.equal(rendered.capacity.occupiedPeople,12);
    assert.equal(page.waitlistScope,null);assert.equal(window.location.hash,'');assert.equal(window.location.search,'?lang=cs');
    d.window.close();
});
