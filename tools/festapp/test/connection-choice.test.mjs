import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { verifyConnectionChoice, activeConnections, installConnectionReplacement } from '../src/remote/connection-choice.mjs';
import { verifyConsent } from '../src/remote/consent.mjs';
import { consentForm, connectionsPage } from '../src/remote/views.mjs';

const old = { id: 'old', userId: 'user', clientId: 'application', profileBinding: 'profile', expiresAt: Date.now() + 60000,
    access: { type: 'occasions', occasionIds: [7] }, permissions: [], binding: 'session' };
const storage = { get: (_model, id) => id === 'old' ? old : undefined, values: () => [old] };
const verify = choice => verifyConnectionChoice(choice, storage, 'user', 'application', 'profile');
test('names are normalized and bounded; additional devices require a nonblank name', () => {
    assert.deepEqual(verify(undefined), { durationDays: 7 });
    assert.equal(verify({ mode: 'new', name: ' Office ' }).name, 'Office');
    for (const name of ['', '   ', 'x'.repeat(81), 'bad\nname']) assert.throws(() => verify({ mode: 'new', name }), /FORBIDDEN/);
    assert.throws(() => verify({ mode: 'new', name: 'Office', connectionId: 'old' }), /FORBIDDEN/);
    assert.throws(() => verify({ mode: 'replace' }));
    assert.throws(() => verify({ mode: 'replace', connectionId: 'missing' }));
    assert.deepEqual(verifyConnectionChoice({ mode: 'new', name: ' ' }, { values: () => [] }, 'u', 'c', 'p'), { durationDays: 7, name: undefined, replaces: undefined });
});
test('replacement keeps the previous device name unless the user renames it', () => {
    const named = { ...old, name: 'Office Mac', durationDays: 365 };
    const namedStorage = { get: (_model, id) => id === 'old' ? named : undefined, values: () => [named] };
    const choose = name => verifyConnectionChoice({ mode: 'replace', connectionId: 'old', ...(name ? { name } : {}) },
        namedStorage, 'user', 'application', 'profile');
    assert.equal(choose().name, 'Office Mac');
    assert.equal(choose().durationDays, 7, 'replacement never inherits a longer duration');
    assert.equal(choose('Laptop').name, 'Laptop');
});
test('versioned consent preserves choice without expanding approved permissions', () => {
    const result = verifyConsent({ consentVersion: 2, selection: old.access, permissions: [], connection: { mode: 'replace', connectionId: 'old' } }, { occasions: [{ id: 7 }], units: [] }, false, []);
    assert.equal(result.connection.connectionId, 'old'); assert.deepEqual(result.permissions, []);
});
test('active candidates are restricted to actor/client/profile and newest first', () => {
    const values = [old, { ...old, id: 'latest', expiresAt: old.expiresAt + 1000 }, { ...old, clientId: 'foreign' },
        { ...old, userId: 'foreign' }, { ...old, profileBinding: 'foreign' }, { ...old, revoked: true }];
    assert.deepEqual(activeConnections({ values: () => values }, 'user', 'application', 'profile').map(g => g.id), ['latest', 'old']);
});
test('replacement listener ignores refresh and contains storage/audit exceptions', () => {
    const provider = new EventEmitter(); let revocations = 0;
    const store = { get: (_m, id) => id === 'new' ? { ...old, id, replaces: 'old' } : old,
        revoke: () => { revocations++; throw Error('disk unavailable'); } };
    installConnectionReplacement(provider, store, () => { throw Error('audit unavailable'); });
    const ctx = { oidc: { params: { grant_type: 'refresh_token' }, entities: { AuthorizationCode: { grantId: 'new' } } } };
    provider.emit('grant.success', ctx); assert.equal(revocations, 0);
    ctx.oidc.params.grant_type = 'authorization_code';
    assert.doesNotThrow(() => provider.emit('grant.success', ctx)); assert.equal(revocations, 1);
    store.get = (_m, id) => id === 'new' ? { ...old, id, replaces: 'old' } : { ...old, clientId: 'other' };
    provider.emit('grant.success', ctx); assert.equal(revocations, 1, 'recheck ownership at issuance');
});
test('standalone consent and management escape device names', () => {
    const name = '<img src=x onerror=alert(1)>';
    const connections = [{ ...activeConnections(storage, 'user', 'application', 'profile')[0], name }];
    const html = consentForm({ csrf: 'test', client: 'Application', action: '/consent', occasions: [], selectedTenant: 'Tenant', connections });
    assert(!html.includes('<img')); assert(html.includes('&lt;img'));
    assert(connectionsPage('csrf', [{ ...old, name }], []).includes('&lt;img'));
});

test('consent duration accepts exactly the four numeric choices and defaults to seven days', () => {
    for (const durationDays of [7, 30, 90, 365]) assert.equal(verify({ mode: 'replace', connectionId: 'old', durationDays }).durationDays, durationDays);
    for (const durationDays of [0, -7, 1, 8, 364, 366, 7.5, '7', '365', null, true, {}, []])
        assert.throws(() => verify({ mode: 'replace', connectionId: 'old', durationDays }), /FORBIDDEN/);
    assert.equal(verify({ mode: 'replace', connectionId: 'old' }).durationDays, 7);
    for (const raw of [old.access, { consentVersion: 2, selection: old.access, permissions: [] }]) {
        const result = verifyConsent(raw, { occasions: [{ id: 7 }], units: [] }, false, []);
        assert.equal(verifyConnectionChoice(result.connection, storage, 'user', 'application', 'profile').durationDays, 7);
    }
});
test('newest creation wins regardless of selected lifetime; legacy grants retain seven-day fallback', () => {
    const now = Date.now();
    const values = [{ ...old, id: 'year', createdAt: now - 1000, durationDays: 365, expiresAt: now + 365 * 86400000 },
        { ...old, id: 'week', createdAt: now, durationDays: 7, expiresAt: now + 7 * 86400000 }];
    assert.deepEqual(activeConnections({ values: () => values }, 'user', 'application', 'profile').map(g => g.id), ['week', 'year']);
});
test('standalone duration choice defaults to seven days and explains long access and revocation', () => {
    const html = consentForm({ csrf: 'test', client: 'Application', action: '/consent', occasions: [], selectedTenant: 'Tenant' });
    assert.match(html, /name="durationDays"/);
    assert.match(html, /value="7" selected>7 dní/);
    for (const days of [30, 90, 365]) assert(html.includes(`value="${days}"`));
    assert.match(html, /1 rok/); assert.match(html, /Kdykoli jej můžete odebrat/);
    assert(!html.includes('Přístup vyprší za 7 dní'));
});
