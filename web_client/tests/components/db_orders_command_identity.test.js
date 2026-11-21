import test from 'node:test';
import assert from 'node:assert/strict';

import { DbOrders } from '../../src/components/eshop/db_orders.js';
import { SupabaseService } from '../../src/services/supabase_service.js';

test('ticket order sends stable command identity and clears it after success', async () => {
    const values = new Map();
    globalThis.localStorage = {
        getItem: (key) => values.get(key) ?? null,
        setItem: (key, value) => values.set(key, value),
        removeItem: (key) => values.delete(key),
    };

    const bodies = [];
    let shouldFail = true;
    SupabaseService._backend = { supabaseUrl: "https://fixture.example" };
    SupabaseService._client = {
        auth: { getSession: async () => ({ data: { session: null }, error: null }) },
        functions: {
            invoke: async (_name, options) => {
                bodies.push(options.body);
                return shouldFail
                    ? { data: null, error: new Error('temporary failure') }
                    : { data: { code: 200 }, error: null };
            },
        },
    };

    const order = { occasion: 1121, tickets: [] };
    const originalConsoleError = console.error;
    console.error = () => {};
    try {
        await DbOrders.sendOrder(order);
        shouldFail = false;
        await DbOrders.sendOrder(order);
    } finally {
        console.error = originalConsoleError;
    }

    assert.equal(bodies.length, 2);
    assert.deepEqual(bodies[0].orderDetails, order);
    assert.match(bodies[0].commandId, /^[0-9a-f-]{36}$/);
    assert.match(bodies[0].clientId, /^[0-9a-f-]{36}$/);
    assert.equal(bodies[1].commandId, bodies[0].commandId);
    assert.equal(bodies[1].clientId, bodies[0].clientId);
    assert.equal(localStorage.getItem('client_command_pending:ticket_order'), null);
});

test('blocked persistent storage preserves order identity across in-page retries', async (t) => {
    const original = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
    Object.defineProperty(globalThis, 'localStorage', {
        configurable: true,
        get() { throw new Error('SecurityError'); },
    });
    t.after(() => {
        if (original) Object.defineProperty(globalThis, 'localStorage', original);
        else delete globalThis.localStorage;
    });
    const bodies = [];
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: { getSession: async () => ({ data: { session: null }, error: null }) },
        functions: { invoke: async (_, { body }) => {
            bodies.push(body);
            return bodies.length === 1
                ? { data: null, error: new Error('retry') }
                : { data: { code: 200 }, error: null };
        } },
    }));
    t.mock.method(console, 'error', () => {});
    const order = { occasion: 1121, tickets: [] };
    await DbOrders.sendOrder(order);
    await DbOrders.sendOrder(order);
    assert.equal(bodies[0].commandId, bodies[1].commandId);
    assert.equal(bodies[0].clientId, bodies[1].clientId);
    await DbOrders.sendOrder(order);
    assert.notEqual(bodies[1].commandId, bodies[2].commandId, 'a completed order must clear its pending command');
});

test('uncertain order outcomes retain the same intent through the actual form network boundary', async t => {
    const { FormNetwork } = await import('../../src/components/forms/form_network.js');
    let failure;
    const bodies = [];
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: { getSession: async () => ({ data: { session: null }, error: null }) },
        functions: { invoke: async (_, { body }) => {
            bodies.push(body);
            if (failure === 'throw') throw new TypeError('Failed to fetch');
            if (failure === 'error') return {data:null,error:new Error('Connection lost')};
            if (failure === 'missing') return {data:null,error:null};
            if (failure === 'server') return {data:{code:503},error:null};
            return {data:{code:200},error:null};
        } },
    }));
    for (const kind of ['throw','error','missing','server']) {
        const payload = {form:`uncertain-${kind}`,secret:`synthetic-${kind}`,ticket:[]};
        failure = kind;
        const result = await FormNetwork.submitOrder(payload);
        assert.equal(result.success,false);
        assert.equal(result.data.code,503);
        assert.equal(result.data.errorCode,'ORDER_OUTCOME_UNKNOWN');
        failure = null;
        assert.equal((await FormNetwork.submitOrder(payload)).success,true);
        const [first,retry] = bodies.slice(-2);
        assert.equal(first.commandId,retry.commandId);
        assert.equal(first.clientId,retry.clientId);
        assert.deepEqual(first.orderDetails,retry.orderDetails);
    }
});

test('a refreshed Wix proof preserves the exact request after a lost order response', async t => {
    const bodies = [];
    const firstProof = 'cHJvdmVuYW5jZQ.' + 'a'.repeat(64);
    const nextProof = 'cHJvdmVuYW5jZQ.' + 'b'.repeat(64);
    const previousLocation = Object.getOwnPropertyDescriptor(globalThis, 'location');
    Object.defineProperty(globalThis, 'location', {configurable:true, writable:true,
        value:{pathname:'/form/retry-proof',search:`?checkout_origin=${firstProof}`}});
    t.after(() => {
        if (previousLocation) Object.defineProperty(globalThis, 'location', previousLocation);
        else delete globalThis.location;
    });
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: {getSession:async()=>({data:{session:null},error:null})},
        functions: {invoke:async(_, {body})=>{
            bodies.push(body);
            if (bodies.length===1) throw new TypeError('Response lost after commit');
            return {data:{code:200},error:null};
        }},
    }));
    const order={form:'wix-proof-retry',ticket:[]};
    assert.equal((await DbOrders.sendOrder(order)).errorCode,'ORDER_OUTCOME_UNKNOWN');
    globalThis.location.search=`?checkout_origin=${nextProof}`;
    assert.equal((await DbOrders.sendOrder(order)).success,true);
    assert.deepEqual(bodies[1],bodies[0]);
    assert.equal(bodies[1].orderDetails.checkoutOrigin,firstProof);
    await DbOrders.sendOrder(order);
    assert.notEqual(bodies[2].commandId,bodies[0].commandId);
    assert.equal(bodies[2].orderDetails.checkoutOrigin,nextProof);
});


test('capacity rejection releases the intent while opaque throttling retains it', async t => {
    let result;
    const bodies = [];
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: {getSession: async () => ({data: {session: null}, error: null})},
        functions: {invoke: async (_, {body}) => {
            bodies.push(body);
            return {data: result, error: null};
        }},
    }));
    for (const definitive of [false, true]) {
        const payload = {form: `capacity-retry-${definitive}`, ticket: []};
        result = {code: 429, ...(definitive ? {errorCode: 'ABUSE_LIMIT_EXCEEDED'} : {})};
        assert.equal((await DbOrders.sendOrder(payload)).code, 429);
        result = {code: 200};
        await DbOrders.sendOrder(payload);
        const [first, retry] = bodies.slice(-2);
        assert.equal(first.commandId === retry.commandId, !definitive);
    }
});

test('a restricted buyer retries the same guest intent after MFA and preserves an earlier account intent', async t => {
    const actor = {id: 'buyer-account'};
    let decision = 'account_recovery';
    let authToken = 'held-token';
    let loseResponse = true;
    const requests = [];
    const invoke = mode => async (_, options) => {
        requests.push({mode, ...options});
        return loseResponse ? {error: new Error('response lost')} : {data: {code: 200}};
    };
    t.mock.getter(SupabaseService, 'isCanonicalBackend', () => true);
    t.mock.method(SupabaseService, 'getGuestClient', () => ({functions: {invoke: invoke('guest')}}));
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: {getSession: async () => ({data: {session: {user: actor, access_token: authToken}}})},
        rpc: name => ({setHeader: async (key, value) => {
            assert.equal(name, 'get_account_assurance_v1');
            assert.equal(key, 'Authorization');
            assert.equal(value, `Bearer ${authToken}`);
            return {data: decision};
        }}),
        functions: {invoke: invoke('account')},
    }));
    const purchase = {form: 'mfa-guest-intent', tickets: []};
    assert.equal((await DbOrders.sendOrder(purchase)).errorCode, 'ORDER_OUTCOME_UNKNOWN');
    decision = 'allowed';
    authToken = 'upgraded-token';
    loseResponse = false;
    assert.equal((await DbOrders.sendOrder(purchase, {reusePendingOnly: true})).success, true);
    assert.deepEqual(requests[1], requests[0]);
    assert.equal(requests[0].mode, 'guest');
    assert.equal(requests[0].headers, undefined);

    loseResponse = true;
    assert.equal((await DbOrders.sendOrder(purchase)).errorCode, 'ORDER_OUTCOME_UNKNOWN');
    decision = 'mfa_required';
    authToken = 'expired-proof-token';
    await assert.rejects(DbOrders.sendOrder(purchase), /PAYMENT_RECOVERY_REQUIRED/);
    assert.equal(requests.length, 3);
    decision = 'allowed';
    authToken = 'new-proof-token';
    loseResponse = false;
    assert.equal((await DbOrders.sendOrder(purchase, {reusePendingOnly: true})).success, true);
    assert.deepEqual(requests[3].body, requests[2].body);
    assert.equal(requests[3].mode, 'account');
    assert.equal(requests[3].headers.Authorization, 'Bearer new-proof-token');
});

test('public Form RPCs retry only a structured account assurance refusal', async t => {
    const {DbForms} = await import('../../src/components/forms/db_forms.js');
    let error = {code: '42501', message: 'account_recovery'};
    const guest = t.mock.fn(async () => ({data: {code: 200, spotIds: [6]}}));
    const account = t.mock.fn(async () => ({error}));
    t.mock.method(SupabaseService, 'getClient', () => ({rpc: account}));
    t.mock.method(SupabaseService, 'getGuestClient', () => ({rpc: guest}));
    t.mock.method(console, 'error', () => {});
    await DbForms.selectSpot('fixture-form', 'fixture-reservation', 6, true);
    assert.deepEqual(guest.mock.calls[0].arguments, account.mock.calls[0].arguments);
    error = {code: '42501', message: 'unrelated prohibition'};
    await assert.rejects(DbForms.selectSpot('fixture-form', 'fixture-reservation', 6, true), /unrelated prohibition/);
    error = {code: '503', message: 'account_recovery'};
    await assert.rejects(DbForms.selectSpot('fixture-form', 'fixture-reservation', 6, true), /account_recovery/);
    assert.equal(guest.mock.calls.length, 1);
});

test('canonical checkout pins the guest transport selected before concurrent sign-in', async t => {
    t.mock.getter(SupabaseService, 'isCanonicalBackend', () => true);
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: {getSession: async () => ({data: {session: null}})},
        functions: {invoke: () => assert.fail('shared SDK session was used for a guest intent')},
    }));
    const guest = t.mock.fn(async () => ({data: {code: 200}}));
    t.mock.method(SupabaseService, 'getGuestClient', () => ({functions: {invoke: guest}}));
    assert.equal((await DbOrders.sendOrder({form: 'mfa-guest-before-auth-change', tickets: []})).success, true);
    assert.equal(guest.mock.calls.length, 1);
});


test('withdrawal while checkout waits for the session strips consent before the order request', async t => {
    const { FormNetwork } = await import('../../src/components/forms/form_network.js');
    const { PurchaseConsentOrders } = await import('../../src/components/forms/meta_purchase_consent.js');
    const authenticated = Promise.withResolvers();
    const now = Date.now();
    const snapshot = {
        source: 'klaro', consentRevision: 'c'.repeat(32), websiteOrigin: 'https://fixture.example',
        ad_storage: true, ad_user_data: true, ad_personalization: true,
        decidedAt: '2099-01-01T00:00:00.000Z', capturedAt: new Date(now).toISOString(),
    };
    const tracker = new PurchaseConsentOrders({ clock: () => now, revoke: t.mock.fn() });
    const attempt = tracker.capture(snapshot, { revision: 'a'.repeat(32) });
    const invoke = t.mock.fn(async () => ({ data: { code: 200 }, error: null }));
    t.mock.method(SupabaseService, 'getClient', () => ({
        auth: { getSession: () => authenticated.promise },
        functions: { invoke },
    }));
    const pending = FormNetwork.submitOrder(
        { form: 7291, tickets: [], metaPurchaseConsent: snapshot },
        { canSendMetaPurchaseConsent: () => tracker.canDispatch(attempt) },
    );
    tracker.observe({ purchaseConsent: {
        ...snapshot, ad_storage: false, decidedAt: new Date(now).toISOString(),
    } });
    authenticated.resolve({ data: { session: null }, error: null });

    assert.equal((await pending).success, true);
    assert.equal(invoke.mock.calls.length, 1);
    assert.equal(invoke.mock.calls[0].arguments[1].body.orderDetails.metaPurchaseConsent, undefined);
    assert.equal(tracker.orders.size, 0);
});
