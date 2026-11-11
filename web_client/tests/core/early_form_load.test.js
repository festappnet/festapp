import assert from 'node:assert/strict';
import test from 'node:test';
import {EarlyFormLoad} from '../../src/startup/early_form_load.js';
import {SupabaseService} from '../../src/services/supabase_service.js';
import {FormModel} from '../../src/components/forms/form_models.js';
import {initializeCoreServices} from '../../src/startup/initialize_core_services.js';

function fixture(path = '/form/example?embed=1') {
    const win = {location: new URL(path, 'https://example.test')};
    let session = null, calls = 0;
    const client = {auth: {getSession: async () => ({data: {session}})}};
    const service = {isCanonicalBackend: true, getClient: () => client,
        isAnonymousClient: SupabaseService.isAnonymousClient};
    const model = {link: 'example'};
    const args = {win, service, load: async link => { calls++; assert.equal(link, 'example'); return model; }};
    return {early: new EarlyFormLoad(), args, model, calls: () => calls++, count: () => calls,
        session: value => { session = value; }};
}

test('starts before rights settle and consumes an in-flight request only once', async () => {
    const f = fixture();
    let finish;
    f.args.load = () => { f.calls(); return new Promise(resolve => { finish = resolve; }); };
    await initializeCoreServices({localizationService: {init: async () => {}},
        supabaseService: {initialize: async () => {}}, isAppSupported: false,
        onBackendReady: () => f.early.start(f.args),
        rightsService: {updateAppData: async () => {
            assert.ok(f.early.entry.promise);
            await new Promise(resolve => setImmediate(resolve));
            assert.equal(f.count(), 1);
        }}});
    const first = f.early.consume('example', f.args);
    assert.equal(await f.early.consume('example', f.args), null);
    finish(f.model);
    assert.equal(await first, f.model);
    f.early.start(f.args);
    assert.equal(f.count(), 1);
});

test('missing request and link mismatch fall back', async () => {
    const f = fixture();
    assert.equal(await f.early.consume('example', f.args), null);
    f.early.start(f.args);
    assert.equal(await f.early.consume('other', f.args), null);
    assert.equal(await f.early.consume('example', f.args), null);
});

test('failure, empty or unexpected result fall back without unhandled rejection', async () => {
    for (const load of [async () => { throw Error('offline'); }, async () => null, async () => undefined]) {
        const f = fixture(); f.args.load = load;
        f.early.start(f.args);
        await new Promise(resolve => setImmediate(resolve));
        assert.equal(await f.early.consume('example', f.args) ?? null, null);
    }
});

for (const path of ['/order', '/form/example?preview=true', '/form/example?admin=1',
    '/form/example?waitlist=1', '/form/example?order_id=1&token=secret',
    '/form/example#sale_opening=unsubscribe', '/form/example#order?token=secret',
    '/form/example?unknown=1', '/form/example/nested']) {
    test(`private or unexpected route skips early fetch: ${path}`, async () => {
        const f = fixture(path); f.early.start(f.args);
        assert.equal(await f.early.consume('example', f.args), null);
        assert.equal(f.count(), 0);
    });
}

test('session, captured sale scope and unresolved activation skip early fetch', async () => {
    for (const setup of [f => f.session({user: {id: 'user'}}),
        f => { f.args.win.__festappSaleOpeningLink = '{}'; },
        f => { f.args.service.isCanonicalBackend = false; },
        f => { f.args.service.getClient = () => { throw Error('not initialized'); }; }]) {
        const f = fixture(); setup(f); f.early.start(f.args);
        assert.equal(await f.early.consume('example', f.args), null);
        assert.equal(f.count(), 0);
    }
});

test('reload, auth change, client change, route change and sale scope invalidate reuse', async () => {
    for (const setup of [f => { f.args.disabled = true; }, f => f.session({user: {id: 'user'}}),
        f => { f.args.service.getClient = () => ({}); },
        f => { f.args.win.location = new URL('https://example.test/form/other'); },
        f => { f.args.win.__festappSaleOpeningLink = '{}'; }]) {
        const f = fixture(); f.early.start(f.args);
        await new Promise(resolve => setImmediate(resolve));
        setup(f);
        assert.equal(await f.early.consume('example', f.args), null);
    }
});

test('normal direct visits also reuse the early request', async () => {
    const f = fixture('/form/example'); f.early.start(f.args);
    assert.equal(await f.early.consume('example', f.args), f.model);
    assert.equal(f.count(), 1);
});

for (const boundary of ['start_time', 'end_time']) {
    for (const pending of [false, true]) {
        for (const offset of [0, 1]) {
            test(`${boundary} crossed ${pending ? 'during RPC' : 'while startup waits'} invalidates at boundary + ${offset}`, async t => {
                const at = Date.parse('2030-01-01T12:00:00Z');
                let now = at - 1000;
                t.mock.method(Date, 'now', () => now);
                const f = fixture();
                const stale = new FormModel({link: 'example', registrationMode: 'closed',
                    data: {schedule: {[boundary]: new Date(at).toISOString()}}});
                let finish;
                f.args.load = () => new Promise(resolve => { finish = resolve; });
                f.early.start(f.args);
                await new Promise(resolve => setImmediate(resolve));
                if (!pending) { finish(stale); await f.early.entry.promise; }
                const result = f.early.consume('example', f.args);
                now = at + offset;
                if (pending) finish(stale);
                assert.equal(await result, null, 'the caller must fetch fresh authoritative availability');
                assert.equal(await f.early.consume('example', f.args), null);
            });
        }
    }
}

test('unchanged availability windows and absent or invalid dates preserve reuse', async t => {
    const at = Date.parse('2030-01-01T12:00:00Z');
    let now = at;
    t.mock.method(Date, 'now', () => now);
    for (const schedule of [{}, {start_time: 'invalid', end_time: 'invalid'},
        {start_time: new Date(at - 1000).toISOString()},
        {start_time: new Date(at + 10000).toISOString(), end_time: new Date(at + 20000).toISOString()}]) {
        now = at;
        const f = fixture();
        const model = new FormModel({link: 'example', data: {schedule}});
        f.args.load = async () => model;
        f.early.start(f.args);
        await f.early.entry.promise;
        now += 1000;
        assert.equal(await f.early.consume('example', f.args), model);
    }
});

test('session changes while RPC is pending invalidate the result', async () => {
    const f = fixture();
    let finish;
    f.args.load = () => new Promise(resolve => { finish = resolve; });
    f.early.start(f.args);
    await new Promise(resolve => setImmediate(resolve));
    const result = f.early.consume('example', f.args);
    f.session({user: {id: 'signed-in'}});
    finish(f.model);
    assert.equal(await result, null);
});
