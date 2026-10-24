import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { loadOrderOverview, parseOrderFragment, renderOrderOverview } from '../../src/components/forms/order_overview.js';
import { WaitlistCommands } from '../../src/components/forms/waitlist_commands.js';
const fixture = () => ({ code: 200, root: { id: 1, title: '<script>unsafe</script>', symbol: 'ROOT' }, serverTime: '2026-10-15T12:00:00Z',
    people: [{ id: 1, label: 'Waiting', effectiveLifecycle: 'offered' }, { id: 2, label: 'Accepted', effectiveLifecycle: 'admitted' }],
    offers: [{ pendingPlaces: 1, effectiveStatus: 'pending', expiresAt: '2026-10-16T12:00:00Z' }],
    orders: [{ id: 2, symbol: 'CHILD', state: 'paid', total: 1000, currency: 'CZK', items: [],
        payment: { status: 'deposit_paid', received: 300, totalOutstanding: 700, dueNow: 700, returned: 0, overpaid: 0, instructionsAvailable: true, publicAccount: '123/0100', referenceKind: 'VS', reference: '123' },
        tickets: [{ id: 2, label: 'Accepted', displayStatus: 'unused' }] }] });
function setup(t) { const dom = new JSDOM('<main></main>', {url:'https://tickets.invalid/form/example'}); globalThis.window = dom.window; globalThis.document = dom.window.document; t.after(() => dom.window.close()); return document.querySelector('main'); }
test('view fragment distinct from write scope and validates root', () => {
    assert.equal(parseOrderFragment('#waitlist?token=bad'), null);
    assert.deepEqual(parseOrderFragment(`#order?order_id=12&token=${'a'.repeat(64)}`), { orderId: 12, token: 'a'.repeat(64) });
    for (const id of ['0','-1','NaN','9007199254740993']) assert.throws(() => parseOrderFragment(`#order?order_id=${id}&token=${'a'.repeat(64)}`));
});
test('partial overview renders separate payment facts and no write controls', t => {
    const host = setup(t); renderOrderOverview(host, fixture(), () => {});
    assert.equal(host.querySelector('script'), null);
    assert.match(host.textContent, /300 CZK/); assert.match(host.textContent, /700 CZK/);
    assert.equal(host.querySelectorAll('button').length, 1);
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
test('overview keeps table and seat beside their product and safely renders custom labels', t => {
    const host = setup(t); const data = fixture();
    data.orders[0].items = [{title:'Místo',price:450,currency:'CZK',spotGroupTitle:'7',spotTitle:'<b>3</b>'}, {title:'Lunch',price:100,currency:'CZK'}];
    renderOrderOverview(host, data, () => {});
    const details = [...host.querySelectorAll('p span')];
    assert.equal(details.length,1);
    assert.match(details[0].textContent,/7.*<b>3<\/b>/);
    assert.match(details[0].parentElement.textContent,/Místo: 450 CZK/);
    assert.equal(details[0].querySelector('b'),null);
});
