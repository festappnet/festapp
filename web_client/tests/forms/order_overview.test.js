import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { loadOrderOverview, parseOrderFragment, parseOrderLocation, renderOrderOverview, stopOrderOverview } from '../../src/components/forms/order_overview.js';
import { WaitlistCommands } from '../../src/components/forms/waitlist_commands.js';
const fixture = () => ({ code: 200, root: { id: 1, title: '<script>unsafe</script>', symbol: 'ROOT' }, serverTime: '2026-10-15T12:00:00Z',
    people: [{ id: 1, label: 'Waiting', effectiveLifecycle: 'offered' }, { id: 2, label: 'Accepted', effectiveLifecycle: 'admitted' }],
    offers: [{ pendingPlaces: 1, effectiveStatus: 'pending', expiresAt: '2026-10-16T12:00:00Z' }],
    orders: [{ id: 2, symbol: 'CHILD', state: 'paid', total: 1000, currency: 'CZK', items: [],
        payment: { status: 'deposit_paid', received: 300, totalOutstanding: 700, dueNow: 700, returned: 0, overpaid: 0, instructionsAvailable: true, publicAccount: '123/0100', referenceKind: 'VS', reference: '123' },
        tickets: [{ id: 2, label: 'Accepted', displayStatus: 'unused' }] }] });
function setup(t) { const dom = new JSDOM('<main></main>', { url: 'https://tickets.invalid/form/example' }); globalThis.window = dom.window; globalThis.document = dom.window.document; t.after(() => dom.window.close()); return document.querySelector('main'); }
test('view fragment distinct from write scope and validates root', () => {
    assert.equal(parseOrderFragment('#waitlist?token=bad'), null);
    assert.deepEqual(parseOrderFragment(`#order?order_id=12&token=${'a'.repeat(64)}`), { orderId: 12, token: 'a'.repeat(64) });
    for (const id of ['0','-1','NaN','9007199254740993']) assert.throws(() => parseOrderFragment(`#order?order_id=${id}&token=${'a'.repeat(64)}`));
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
    assert.deepEqual(parseOrderLocation(new URL(`https://example.invalid/form/test?order_id=12&token=${scope.token}`)), scope);
    assert.equal(parseOrderLocation({ search: '?waitlist=1&order_id=12&token=bad' }), null);
    assert.throws(() => parseOrderLocation({ search: `?order_id=12&order_id=13&token=${scope.token}` }));
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
