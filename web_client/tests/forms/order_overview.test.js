import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { loadOrderOverview, parseOrderLocation, renderOrderOverview, stopOrderOverview } from '../../src/components/forms/order_overview.js';
import { WaitlistCommands } from '../../src/components/forms/waitlist_commands.js';
const fixture = () => ({ code: 200, root: { id: 1, title: '<script>unsafe</script>', symbol: 'ROOT', hasTickets: true }, serverTime: '2026-10-15T12:00:00Z',
    people: [{ id: 1, label: 'Waiting', effectiveLifecycle: 'offered' }, { id: 2, currentOrderId: 2, label: 'Accepted', effectiveLifecycle: 'admitted' }],
    offers: [{ pendingPlaces: 1, effectiveStatus: 'pending', expiresAt: '2026-10-16T12:00:00Z' }],
    orders: [{ id: 2, symbol: 'CHILD', state: 'paid', total: 1000, currency: 'CZK', items: [],
        payment: { status: 'deposit_paid', received: 300, totalOutstanding: 700, dueNow: 700, returned: 0, overpaid: 0, instructionsAvailable: true, publicAccount: '123/0100', referenceKind: 'VS', reference: '123' },
        tickets: [{ id: 2, label: 'Accepted', displayStatus: 'unused' }] }] });
function setup(t) { const dom = new JSDOM('<main></main>', { url: 'https://tickets.invalid/form/example' }); globalThis.window = dom.window; globalThis.document = dom.window.document; t.after(() => dom.window.close()); return document.querySelector('main'); }
test('only standalone query capabilities are accepted', () => {
 const token = 'a'.repeat(64);
 for (const path of [`/form/test?order_id=12&token=${token}`, `/form/test#order?order_id=12&token=${token}`, `/order#order?order_id=12&token=${token}`]) {
   assert.equal(parseOrderLocation(new URL(path, 'https://tickets.invalid')), null);
 }
 for (const id of ['0','-1','NaN','9007199254740993']) assert.throws(() => parseOrderLocation(new URL(`/order?order_id=${id}&token=${token}`, 'https://tickets.invalid')));
});
test('partial overview renders separate payment facts and no write controls', t => {
    const host = setup(t); renderOrderOverview(host, fixture());
    assert.equal(host.querySelector('script'), null);
    assert.match(host.textContent, /300,00\s*Kč/); assert.match(host.textContent, /700,00\s*Kč/);
    assert.equal(host.querySelectorAll('button').length, 0);
    assert.equal(host.querySelector('input'), null);
    assert.equal(host.querySelector('img,canvas'), null);
});
test('refresh reads current ticket facts; failure replaces old sensitive data; retry restores', async t => {
    const host = setup(t); let fail = false; let calls = 0;
    const commands = { overview: async () => { calls++; if (fail) throw new Error('offline'); const f = fixture(); f.orders[0].tickets[0].displayStatus = calls === 1 ? 'unused' : 'used'; return f; } };
    await loadOrderOverview(host, commands, {}); assert.match(host.textContent, /CHILD/);
    fail = true; await loadOrderOverview(host, commands, {}); assert.equal(host.textContent.includes('CHILD'), false); assert.ok(host.querySelector('[role=alert]'));
    fail = false; await loadOrderOverview(host, commands, {}); assert.match(host.textContent, /used/);
});
test('out of order responses cannot replace a different root scope', async t => {
    const host = setup(t); let finish;
    const first = loadOrderOverview(host, { overview: () => new Promise(resolve => finish = resolve) }, {});
    const second = fixture(); second.root.symbol = 'NEW';
    await loadOrderOverview(host, { overview: async () => second }, {});
    finish(fixture()); await first; assert.match(host.textContent, /NEW/); assert.equal(host.textContent.includes('ROOT'), false);
});
test('view transport calls only read RPC; resolver remains a separate POST', async () => {
    const calls = [];
    const client = { rpc: async (name, params) => { calls.push({ name, params }); return { data: fixture() }; } };
    const commands = new WaitlistCommands(client); await commands.overview({ token: 'view', orderId: 1 });
    assert.equal(calls[0].name, 'get_customer_order_overview'); assert.deepEqual(calls[0].params, { p_token: 'view', p_order_id: 1 });
    assert.equal(commands.pending.size, 0);
});

test('canonical query keeps the root token and rejects ambiguous scope', () => {
    const scope = { orderId: 12, token: 'a'.repeat(64) };
    assert.deepEqual(parseOrderLocation(new URL(`https://example.invalid/order?order_id=12&token=${scope.token}`)), scope);
    assert.equal(parseOrderLocation({ pathname: '/order', search: '?waitlist=1&order_id=12&token=bad' }), null);
    assert.throws(() => parseOrderLocation({ pathname: '/order', search: `?order_id=12&order_id=13&token=${scope.token}` }));
});
test('history and received transactions include changes without interpreting refunds as payments', t => {
    const host = setup(t), data = fixture();
    data.timeline = [{ kind: 'order_changed', at: data.serverTime, previousTotal: 1000, total: 1500, currency: 'CZK', itemsChanged: true, itemsBefore: [{ title: 'Old', price: 1000 }], itemsAfter: [{ title: 'New', price: 1500 }] }];
    data.orders[0].payment.transactions = [{ kind: 'payment_received', amount: 300, currency: 'CZK', date: '2026-10-15' }, { kind: 'refund', amount: -100, currency: 'CZK', date: null }];
    renderOrderOverview(host, data);
    assert.equal(host.querySelectorAll('.overview-transactions li').length, 2);
    assert.match(host.textContent, /transactions \(1\)/);
    assert.match(host.textContent, /Old/); assert.match(host.textContent, /New/);
    assert.ok(host.querySelector('.overview-timeline time'));
});

test('automatic refresh pauses in hidden tabs, resumes on return and stops on cleanup', async t => {
    const host = setup(t), doc = host.ownerDocument, win = doc.defaultView;
    let visibility = 'visible', calls = 0, nextId = 0;
    host.getClientRects = () => [{}];
    Object.defineProperty(doc, 'visibilityState', { get: () => visibility });
    const timers = new Map();
    win.setTimeout = (callback, delay) => { assert.equal(delay, 30000); timers.set(++nextId, callback); return nextId; };
    win.clearTimeout = id => timers.delete(id);
    const commands = { overview: async () => { calls++; return fixture(); } };
    await loadOrderOverview(host, commands, {});
    assert.equal(calls, 1); assert.equal(timers.size, 1);
    const heading = host.querySelector('h1');
    const tick = [...timers.values()][0]; await tick();
    assert.equal(calls, 2); assert.equal(host.querySelector('h1'), heading, 'unchanged reads do not rebuild content');
    visibility = 'hidden'; doc.dispatchEvent(new win.Event('visibilitychange'));
    assert.equal(timers.size, 0); assert.equal(calls, 2);
    visibility = 'visible'; doc.dispatchEvent(new win.Event('visibilitychange'));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 3); assert.equal(timers.size, 1);
    stopOrderOverview(host); assert.equal(timers.size, 0);
    doc.dispatchEvent(new win.Event('visibilitychange')); assert.equal(calls, 3);
});

for (const hasTickets of [false, true]) test(`overview uses feature terminology: tickets=${hasTickets}`, t => {
    const host = setup(t), data = fixture(); data.root.hasTickets = hasTickets;
    data.people = [{ effectiveLifecycle: 'admitted' }]; data.offers = [];
    data.orders[0].payment.status = 'unpaid';
    renderOrderOverview(host, data);
    assert.match(host.querySelector('.overview-people h3').textContent, hasTickets ? /ticket/ : /registration/);
    assert.match(host.querySelector('.overview-timeline-current').textContent, /unpaid/);
    assert.doesNotMatch(host.textContent, /statusAbove|participant|people/);
});
for (const currency of ['CZK', 'EUR']) test(`overview shares collapsed payable QR and removes it after full payment: ${currency}`, async t => {
    const host = setup(t), data = fixture(); data.orders[0].currency = currency;
    const payment = data.orders[0].payment;
    payment.qrPayment = { amount: 700, currency_code: currency, account_number: 'CZ6508000000192000145399', variable_symbol: '123', creditor_name: 'Example', creditor_reference: 'RF18539007547034' };
    renderOrderOverview(host, data);
    for (let i=0;i<30 && !host.querySelector('.result-payment-qr');i++) await new Promise(resolve => setTimeout(resolve,20));
    assert.match(host.querySelector('.result-payment-qr')?.src || '', /^data:image\/png;base64,/);
    assert.equal(host.querySelector('.result-payment-more').open, false);
    assert.match(host.querySelector('.result-payment-total').textContent, /700/);
    assert.equal(host.querySelector('.result-download').href, host.querySelector('.result-payment-qr').src);
    payment.status = 'fully_paid'; payment.instructionsAvailable = false; payment.dueNow = 0; payment.qrPayment = null;
    renderOrderOverview(host, data);
    assert.equal(host.querySelector('.result-payment-qr'), null);
    assert.match(host.querySelector('.overview-timeline-current').textContent, /fully_paid/);
});

for (const hasTickets of [true, false]) test(`items stay with their admission, payment belongs to order: ${hasTickets}`, t => {
    const host = setup(t), data = fixture(); data.root.hasTickets = hasTickets;
    data.people = [1, 2].map(id => ({ id, currentOrderId: 10, effectiveLifecycle: 'admitted' }));
    data.orders[0].id = 10;
    data.orders[0].tickets = [1, 2].map(id => ({ id, displayStatus: 'awaiting_payment' }));
    data.orders[0].items = [1, 2].map(id => ({ ticketId: id, title: `Product ${id}`, price: 100, currency: 'CZK' }));
    data.timeline = [{ kind: 'registration_received', at: data.serverTime }, { kind: 'order_ordered', at: data.serverTime }];
    renderOrderOverview(host, data);
    const rows = host.querySelectorAll('.overview-people > li');
    assert.equal(rows.length, 2);
    assert.match(rows[0].textContent, /Product 1/);
    assert.doesNotMatch(rows[0].textContent, /Product 2|awaiting_payment|admitted/);
    assert.match(rows[1].textContent, /Product 2/);
    assert.equal(host.querySelector('.order-overview-card').textContent.includes('Product'), true);
    assert.equal(host.querySelector('.overview-timeline').textContent.includes('registration_received'), false);
    assert.match(host.querySelector('.overview-timeline').textContent, /order_ordered/);
    data.orders[0].tickets[0].displayStatus = 'used';
    renderOrderOverview(host, data);
    assert.equal(host.querySelector('.overview-people').textContent.includes('OrderOverview.used'), hasTickets);
});

test('single registration shows one heading, collapsed answers and no ticket wording', t => {
    const host = setup(t), data = fixture(); data.root.hasTickets = false;
    data.people = [{id:2,currentOrderId:2,effectiveLifecycle:'admitted',symbol:'T123',answers:[{title:'Diet',value:'<b>vegetarian</b>'}]}];
    data.timeline = [{kind:'registration_received',at:data.serverTime},{kind:'order_sent',at:data.serverTime}];
    renderOrderOverview(host,data);
    assert.match(host.querySelector('.overview-people h3').textContent,/registration/);
    assert.equal(host.querySelector('.overview-answers').open,false);
    assert.equal(host.querySelector('.overview-answers b'),null);
    assert.match(host.textContent,/confirmation_sent/);
    assert.doesNotMatch(host.textContent,/T123|registration_received|order_sent/);
    data.root.hasTickets=true;
    renderOrderOverview(host,data);
    assert.match(host.querySelector('.overview-people h3').textContent,/T123/);
});

test('payments show recorded timestamps consistently in the list and history',t=>{
    const host=setup(t),data=fixture();
    data.timeline=[{kind:'payment_received',at:'2026-10-15T19:30:31Z',timeKind:'recorded',amount:300,currency:'CZK'}];
    data.orders[0].payment.transactions=[{kind:'payment_received',recordedAt:'2026-10-15T19:30:31Z',date:'2026-10-15',amount:300,currency:'CZK'}];
    renderOrderOverview(host,data);
    const timestamp=host.querySelector('.overview-timeline time');
    assert.equal(timestamp.dateTime,'2026-10-15T19:30:31Z');
    assert.match(timestamp.textContent,/\d{1,2}:\d{2}/);
    assert.doesNotMatch(timestamp.textContent,/recordedAt|Zaevidováno/);
    assert.ok(host.querySelector('.overview-history-card'));
    assert.equal(host.querySelector('.overview-transactions small').textContent,timestamp.textContent);
});

test('one order has its reference in the status heading and a standalone paid status',t=>{
    const host=setup(t),data=fixture();data.people=[];data.orders[0].payment.status='fully_paid';
    renderOrderOverview(host,data);
    assert.equal(host.querySelector('.overview-status h2').textContent,'OrderOverview.currentOrderStatus CHILD');
    assert.doesNotMatch(host.querySelector('.overview-state-row').textContent,/CHILD|check_circle/);
    assert.ok(host.querySelector('.overview-state-complete svg'));
    assert.match(host.querySelector('.order-overview-card h2').textContent,/orderDetails CHILD/);
});

test('payment status distinguishes awaiting, overdue and completed without an overdue warning for paid orders',t=>{
 const host=setup(t),data=fixture(),p=data.orders[0].payment;
 p.status='unpaid';p.dueAt='2026-10-18T12:00Z';p.overdue=false;
 renderOrderOverview(host,data);
 assert.match(host.querySelector('.overview-status').textContent,/withinDeadline/);
 p.overdue=true;renderOrderOverview(host,data);
 assert.ok(host.querySelector('.overview-status .overview-state-overdue'));
 p.status='fully_paid';renderOrderOverview(host,data);
 assert.ok(host.querySelector('.overview-status .overview-state-complete'));
 assert.equal(host.querySelector('.overview-status .overview-state-deadline'),null);
});

test('refresh preserves each disclosure by identity and keeps newly added answers collapsed', async t=>{
 const host=setup(t),data=fixture();data.people[0].answers=[{title:'Name',value:'A'}];
 const commands={overview:async()=>data};
 await loadOrderOverview(host,commands,{});
 host.querySelector('.overview-answers').open=true;
 data.people.unshift({id:99,effectiveLifecycle:'waiting',answers:[{title:'Name',value:'B'}]});
 await loadOrderOverview(host,commands,{},null,false,true);
 assert.equal(host.querySelector('[data-overview-key="answers:ticket:1"]').open,true);
 assert.equal(host.querySelector('[data-overview-key="answers:ticket:99"]').open,false);
});

test('overview groups contacts, admissions and total while payments follow history', t=>{
 const host=setup(t),data=fixture();data.people=[data.people[1]];
 data.orders[0].answers=[{type:'name',value:'Jane'},{type:'surname',value:'Doe'},{type:'email',value:'jane@example.invalid'},{type:'phone',value:'+420 123 456 789'},{type:'note',value:'Extra details'}];
 data.orders[0].items=[{ticketId:2,title:'Dinner',price:100,currency:'CZK'}];
 renderOrderOverview(host,data);
 assert.equal(host.querySelector('h1').textContent,'OrderOverview.title ROOT');
 assert.equal(host.querySelector('.overview-event-title').textContent,data.root.title);
 assert.equal(host.querySelector('.overview-status').nextElementSibling.className,'overview-updated');
 const card=host.querySelector('.order-overview-card');
 assert.equal(card.querySelector('.overview-customer strong').textContent,'Jane Doe');
 assert.equal(card.querySelector('.overview-customer a').getAttribute('href'),'mailto:jane@example.invalid');
 assert.equal(card.querySelector('.overview-answers').open,false);
 assert.match(card.querySelector('.overview-people').textContent,/Dinner/);
 assert.equal(card.querySelector('.overview-customer').compareDocumentPosition(card.querySelector('.overview-people')) & 4,4);
 assert.equal(card.querySelector('.overview-people').compareDocumentPosition(card.querySelector('.overview-order-total')) & 4,4);
 assert.equal(card.querySelector('.overview-transactions'),null);
 assert.equal(host.querySelector('.overview-history-card').nextElementSibling.className,'overview-payments-card');
});
