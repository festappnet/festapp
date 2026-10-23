import assert from 'node:assert/strict';
import test from 'node:test';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';
register('../css_loader.mjs', import.meta.url);

const dom = new JSDOM('<body></body>', { url: 'https://vstupenky.online/' });
Object.assign(globalThis, { window: dom.window, document: dom.window.document,
    HTMLElement: dom.window.HTMLElement, customElements: dom.window.customElements });
const { UserHeader } = await import('../../src/components/users/user_header.js');
const { RightsService } = await import('../../src/services/rights_service.js');
const { SupabaseService } = await import('../../src/services/supabase_service.js');
const { LocalizationService } = await import('../../src/services/localization_service.js');
const signedIn = { user_info: { id: 'user-1', name: 'Eva' }, capabilities: { 'navigation.admin_web': true } };
const guest = { organization: {} };
const nextTask = () => new Promise(resolve => setTimeout(resolve, 0));
test.after(() => dom.window.close());

function fixture(t, rpc) {
    RightsService._context = null;
    RightsService._listeners = [];
    RightsService._identityClient = null;
    RightsService._identityUserId = undefined;
    let authChanged;
    const client = { auth: { onAuthStateChange(callback) {
        authChanged = callback;
        return { data: { subscription: { unsubscribe() {} } } };
    } }, rpc };
    t.mock.method(SupabaseService, 'getClient', () => client);
    t.mock.method(LocalizationService, 'init', async () => {});
    const header = new UserHeader();
    document.body.appendChild(header);
    t.after(() => { header.remove(); clearTimeout(RightsService._authRefreshTimer); });
    return { header, auth: (event, user) => authChanged(event, user ? { user: { id: user } } : null) };
}

for (const duringLoad of [true, false]) {
    test(`account header survives sign-in/session restoration, during initial rights=${duringLoad}`, async t => {
        let complete;
        let calls = 0;
        const { header, auth } = fixture(t, async () => {
            if (++calls === 1) return new Promise(resolve => { complete = resolve; });
            return { data: signedIn, error: null };
        });
        const first = RightsService.updateAppData({ unitId: 7 });
        if (duringLoad) auth('SIGNED_IN', 'user-1');
        complete({ data: signedIn, error: null });
        await first;
        if (!duringLoad) auth('SIGNED_IN', 'user-1');
        await nextTask();
        assert.ok(header.querySelector('.avatar-circle'), 'account must appear without reloading');
        assert.ok(header.querySelector('.btn-admin'), 'event navigation must appear without reloading');
        const settledCalls = calls;
        const avatar = header.querySelector('.avatar-circle');
        auth('SIGNED_IN', 'user-1');
        await nextTask();
        assert.equal(calls, settledCalls, 'same-user SDK notifications do not refetch rights');
        assert.equal(header.querySelector('.avatar-circle'), avatar, 'same-user notification does not blank the header');
    });
}

test('sign-out discards an in-flight private context and renders guest navigation outside the auth callback', async t => {
    let complete;
    let calls = 0;
    let inCallback = false;
    const { header, auth } = fixture(t, async (_, params) => {
        assert.equal(inCallback, false, 'never call Supabase while its auth lock is held');
        assert.equal(params.data_in.unit_id, 7, 'keep the current route scope');
        if (++calls === 1) return new Promise(resolve => { complete = resolve; });
        return { data: guest, error: null };
    });
    const first = RightsService.updateAppData({ unitId: 7 });
    inCallback = true;
    auth('SIGNED_OUT');
    inCallback = false;
    complete({ data: signedIn, error: null });
    assert.equal(await first, false, 'old private response is discarded');
    assert.equal(RightsService.canSeeAdmin(), false);
    await nextTask();
    assert.ok(header.querySelector('.btn-sign-in'), 'guest controls resolve without reload');
    assert.equal(header.querySelector('.avatar-circle'), null);
    assert.equal(header.querySelector('.btn-admin'), null);
});

test('same initial session keeps its pending context request without a duplicate fetch', async t => {
    let complete;
    let calls = 0;
    const { header, auth } = fixture(t, async () => {
        calls++;
        return new Promise(resolve => { complete = resolve; });
    });
    const first = RightsService.updateAppData();
    auth('INITIAL_SESSION', 'user-1');
    auth('SIGNED_IN', 'user-1');
    complete({ data: signedIn, error: null });
    assert.equal(await first, true);
    await nextTask();
    assert.equal(calls, 1);
    assert.ok(header.querySelector('.avatar-circle'));
});

test('switching users clears old rights immediately and discards the previous response', async t => {
    let complete;
    let calls = 0;
    const { header, auth } = fixture(t, async () => {
        if (++calls === 1) return new Promise(resolve => { complete = resolve; });
        return { data: { user_info: { id: 'user-2', name: 'Adam' } }, error: null };
    });
    const first = RightsService.updateAppData();
    auth('INITIAL_SESSION', 'user-1');
    auth('SIGNED_IN', 'user-2');
    complete({ data: signedIn, error: null });
    assert.equal(await first, false);
    assert.equal(RightsService.canSeeAdmin(), false);
    await nextTask();
    assert.equal(RightsService.currentUser.id, 'user-2');
    assert.equal(header.querySelector('.avatar-circle').textContent, 'A');
    assert.ok(header.querySelector('.btn-admin'), 'the new account keeps personal navigation without inheriting old rights');
});

test('explicit post-login refresh supersedes the queued auth refresh without cancelling the awaited result', async t => {
    let completeLogin;
    let calls = 0;
    const { header, auth } = fixture(t, async () => {
        calls++;
        if (calls === 1) return { data: guest, error: null };
        if (calls === 2) return new Promise(resolve => { completeLogin = resolve; });
        return { data: signedIn, error: null };
    });
    await RightsService.updateAppData();
    auth('SIGNED_IN', 'user-1');
    const afterLogin = RightsService.updateAppData();
    await nextTask();
    assert.equal(calls, 2, 'the login owner already started the replacement request');
    completeLogin({ data: signedIn, error: null });
    assert.equal(await afterLogin, true, 'the awaited login response stays current');
    assert.ok(header.querySelector('.btn-admin'));
});
