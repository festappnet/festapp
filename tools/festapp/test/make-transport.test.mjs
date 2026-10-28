import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fixture, profile, reply, token as backendToken } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { openRemoteStorage } from '../src/remote/storage.mjs';
import { createRemoteApp } from '../src/remote/server.mjs';
import { validateMakePage } from '../src/remote/make-transport.mjs';

const privateKey = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
const secret = 'NEVER_DELIVER_BUYER_TEXT';
const row = id => ({ id, occasionId: 7, symbol: String(id).padStart(10, 'A'), state: 'ordered',
    createdAt: null, updatedAt: null, revision: 'a'.repeat(64),
    customer: { name: secret, surname: secret, email: secret }, note: secret,
    ticketCount: 1, price: '100.00', currency: 'CZK', allowedActions: ['view','cancel'],
    payment: { method: secret, variableSymbol: secret, deadline: secret, amount: '100.00', paid: '0.00', returned: '0.00' },
});

async function setup(t) {
    let fail, wrongDetail = false, missingDetail = false, malformedCursor = false;
    const source = Array.from({ length: 52 }, (_, i) => row(52 - i));
    const base = await fixture(t, { fetchImpl: (url, init) => {
        if (url.pathname.endsWith('/get_operator_order_report_v1')) {
            if (fail) return reply({ message: secret }, fail);
            return reply({ occasionId: 7, report: { schema_version: 1,
                valid: { tickets: { total: 52 } }, money_by_currency: [{ currency: 'CZK', net_received: '0.00' }],
                warnings: [{ code: 'fixture_warning' }] }, waitingTickets: 0 });
        }
        if (!url.pathname.endsWith('/get_operator_orders_v1')) return;
        if (fail) return reply({ message: secret }, fail);
        const args = JSON.parse(init.body);
        if (args.p_order) return reply({ occasionId: 7, orders: missingDetail ? [] : [row(wrongDetail ? args.p_order + 1 : args.p_order)], nextCursor: null });
        let rows = source.filter(r => !args.p_before || r.id < args.p_before);
        const more = rows.length > args.p_limit;
        rows = rows.slice(0, args.p_limit);
        return reply({ occasionId: 7, orders: rows, nextCursor: malformedCursor ? 999 : more ? rows.at(-1).id : null });
    } });
    const server = createServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const issuer = `http://127.0.0.1:${server.address().port}`;
    const { binding, ...rawProfile } = profile();
    const clients = [
        { id: 'festapp-make', name: 'Make', redirectUris: ['https://www.make.com/oauth/cb/app'],
            allowedScopes: [READ_SCOPE, 'festapp:orders:read'], dataProfile: 'order-summary' },
        { id: 'festapp-chatgpt', name: 'ChatGPT', redirectUris: ['https://chatgpt.com/connector_platform_oauth_redirect'],
            allowedScopes: [READ_SCOPE, 'festapp:orders:read'], dataProfile: 'order-summary' },
    ];
    const config = parseRemoteConfig({ schemaVersion: 2, issuer, profile: rawProfile, clients, tenantOrigin: 'https://tenant.fixture.test' });
    const storageRoot = await mkdtemp(join(tmpdir(), 'festapp-make-remote-'));
    const storage = await openRemoteStorage(storageRoot, randomBytes(32));
    const service = createRemoteApp(config, storage, { cookieKeys: ['a'.repeat(48), 'b'.repeat(48)],
        jwks: { keys: [{ ...privateKey.export({ format: 'jwk' }), kid: 'make-fixture', use: 'sig', alg: 'RS256' }] },
        brokerSecret: 'b'.repeat(43), fetchImpl: base.owner.fetch });
    server.on('request', service.app);
    t.after(async () => { await new Promise(resolve => server.close(resolve)); await storage.close(); await rm(storageRoot, { recursive: true, force: true }); });
    const authorize = async (clientId = 'festapp-make', scope = `${READ_SCOPE} festapp:orders:read`) => {
        const client = clients.find(c => c.id === clientId), callback = client.redirectUris[0];
        const verifier = randomBytes(32).toString('base64url'), jar = new Map();
        const browse = async (path, body) => {
            const r = await fetch(new URL(path, issuer), { redirect: 'manual', method: body ? 'POST' : 'GET',
                body: body && new URLSearchParams(body), headers: { cookie: [...jar].map(([k,v]) => `${k}=${v}`).join('; '), ...(body ? { origin: issuer } : {}) } });
            for (const c of r.headers.getSetCookie()) { const [p] = c.split(';'), at = p.indexOf('='); jar.set(p.slice(0, at), p.slice(at + 1)); }
            return r;
        };
        let r = await browse('/auth?' + new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: callback,
            scope: 'openid offline_access ' + scope, resource: config.resource, state: 'make-state',
            code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' }));
        assert.equal(r.status, 303);
        r = await browse(r.headers.get('location'));
        const request = new URL(r.headers.get('location')).searchParams.get('request');
        const broker = async (operation, extra = {}) => {
            const response = await fetch(issuer + '/tenant-connection', { method: 'POST',
                headers: { 'content-type': 'application/json', 'x-festapp-mcp-broker': 'b'.repeat(43) },
                body: JSON.stringify({ operation, request, tenantId: config.profile.tenantId,
                    organizationId: config.profile.organizationId, tenantOrigin: config.tenantOrigin, ...extra }) });
            assert.equal(response.status, 200, await response.clone().text()); return response.json();
        };
        const prepared = await broker('prepare', { accessToken: backendToken,
            access: { consentVersion: 2, selection: { type: 'occasions', occasionIds: [7] }, permissions: ['festapp:orders:read'] } });
        const completed = await broker('complete', { lease: prepared.lease,
            session: { access_token: backendToken, refresh_token: 'make-fixture-independent-session' } });
        r = await browse(completed.resumeUrl);
        let location = r.headers.get('location');
        for (let i = 0; i < 8 && new URL(location, issuer).origin === issuer; i++) { r = await browse(location); location = r.headers.get('location'); assert(location); }
        const result = new URL(location);
        assert.equal(result.origin + result.pathname, callback); assert.equal(result.searchParams.get('state'), 'make-state'); assert.equal(result.searchParams.get('iss'), issuer);
        r = await fetch(issuer + '/token', { method: 'POST', body: new URLSearchParams({ client_id: clientId, grant_type: 'authorization_code',
            code: result.searchParams.get('code'), redirect_uri: callback, code_verifier: verifier, resource: config.resource }) });
        assert.equal(r.status, 200, await r.clone().text()); return r.json();
    };
    const post = (token, operation, input = {}, headers = {}) => fetch(issuer + '/make/v1/operations/' + operation, {
        method: 'POST', headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json', ...headers }, body: JSON.stringify(input), redirect: 'manual' });
    return { ...base, issuer, config, storage, authorize, post,
        fail: status => { fail = status; }, wrongDetail: value => { wrongDetail = value; }, missingDetail: value => { missingDetail = value; }, malformedCursor: value => { malformedCursor = value; } };
}

test('Make HTTP transport uses real OAuth tokens, canonical projections and live delegated boundaries', async t => {
    const f = await setup(t), tokens = await f.authorize();
    const documentation = await (await fetch(f.issuer + '/make/v1')).json();
    assert.equal(documentation.openapi, '3.1.0');
    assert.equal(Object.keys(documentation.paths).length, 5);
    assert(!JSON.stringify(documentation.paths['/operations/orders.inspect']).includes('customer'));
    assert(!JSON.stringify(documentation.paths['/operations/context.inspect']).includes('userId'));
    const call = async (op, input = {}, headers) => {
        const r = await f.post(tokens.access_token, op, input, headers), text = await r.text();
        assert(!text.includes(secret), 'no buyer text in any transport response');
        return { status: r.status, headers: r.headers, body: JSON.parse(text) };
    };
    let r = await call('context.inspect'); assert.equal(r.status, 200); assert.equal(r.body.data.userId, undefined);
    assert.deepEqual(r.body.data.enabledOperations.sort(), ['context.inspect','access.inspect','orders.report','orders.list','orders.inspect'].sort());
    r = await call('access.inspect'); assert.deepEqual(r.body.data.occasions.map(o => o.id), [7]);
    r = await call('orders.report', { occasionId: 7 }); assert.equal(r.status, 200); assert.equal(r.body.data.report.valid.tickets.total, 52);
    assert.equal(r.body.data.report.money_by_currency[0].net_received, '0.00'); assert.equal(r.body.data.report.warnings[0].code, 'fixture_warning');
    const first = await call('orders.list', { occasionId: 7, limit: 50 }); assert.equal(first.status, 200); assert.equal(first.body.data.nextCursor, 3);
    const second = await call('orders.list', { occasionId: 7, limit: 50, before: 3 }); assert.equal(second.status, 200); assert.equal(second.body.data.nextCursor, null);
    const rows = [...first.body.data.orders, ...second.body.data.orders]; assert.equal(rows.length, 52); assert.equal(new Set(rows.map(r => r.id)).size, 52);
    assert.deepEqual(Object.keys(rows[0]).sort(), ['id','occasionId','symbol','state','ticketCount','price','currency','allowedActions','payment'].sort());
    assert.deepEqual(rows[0].allowedActions, ['view']);
    assert.equal((await call('orders.list', { occasionId: 7, search: 'buyer@example.test' })).status, 422);
    const later = await call('orders.list', { occasionId: 7, limit: 1, search: row(1).symbol }); assert.equal(later.status, 200); assert.deepEqual(later.body.data.orders.map(o => o.id), [1]);
    r = await call('orders.inspect', { occasionId: 7, orderId: 1 }); assert.equal(r.status, 200); assert.equal(r.body.data.orders[0].id, 1);
    f.wrongDetail(true); r = await call('orders.inspect', { occasionId: 7, orderId: 1 }); assert.equal(r.status, 502); assert.equal(r.body.data, undefined); f.wrongDetail(false);
    f.missingDetail(true); assert.equal((await call('orders.inspect', { occasionId: 7, orderId: 1 })).status, 404); f.missingDetail(false);
    f.malformedCursor(true); assert.equal((await call('orders.list', { occasionId: 7, limit: 50 })).status, 502); f.malformedCursor(false);
    const reads = f.calls.length; assert.equal((await call('orders.report', { occasionId: 8 })).status, 403); assert.equal(f.calls.length, reads);
    for (const op of ['orders.cancel','payments.record','ticket_layouts.inspect','unknown']) assert.equal((await call(op, { occasionId: 7 })).status, 403);
    assert.equal((await f.post(tokens.access_token, 'orders.report', { occasionId: 7 }, { origin: 'https://foreign.example' })).status, 403);
    assert.equal((await fetch(f.issuer + '/make/v1/operations/orders.report')).status, 405);
    for (const status of [429, 503]) { f.fail(status); r = await call('orders.report', { occasionId: 7 }); assert.equal(r.status, status === 429 ? 429 : 502); assert.equal(r.body.ok, false); } f.fail(undefined);
    const other = await f.authorize('festapp-chatgpt'); assert.equal((await f.post(other.access_token, 'context.inspect')).status, 403);
    assert.equal((await f.post('not-a-token', 'context.inspect')).status, 401);
    const grant = f.storage.values('Delegation').find(g => g.clientId === 'festapp-make'); f.storage.revoke(grant.id);
    assert.equal((await call('orders.report', { occasionId: 7 })).status, 401);
    // Revoking Make does not invalidate the other client's existing token.
    const mcp = await fetch(f.issuer + '/mcp', { method: 'POST', headers: { authorization: 'Bearer ' + other.access_token,
        'content-type': 'application/json', accept: 'application/json, text/event-stream', 'mcp-protocol-version': '2025-11-25' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'festapp_context_inspect', arguments: {} } }) });
    assert.equal(mcp.status, 200);
});

test('Make pagination guard fails before a silent technical cutoff and rejects malformed or repeated cursors', () => {
    const page = { ok: true, data: { orders: [{ id: 3 }, { id: 2 }], nextCursor: 2 } };
    validateMakePage('orders.list', { before: 4 }, page, { 'x-festapp-make-page': '50', 'x-festapp-make-total-limit': '2500' });
    assert.throws(() => validateMakePage('orders.list', { before: 4 }, page, { 'x-festapp-make-page': '50' }), /PAGINATION_LIMIT_EXCEEDED/);
    assert.throws(() => validateMakePage('orders.list', {}, page, { 'x-festapp-make-page': '51' }), /PAGINATION_LIMIT_EXCEEDED/);
    assert.throws(() => validateMakePage('orders.list', {}, page, { 'x-festapp-make-page': '1x' }), /INVALID_INPUT/);
    for (const data of [{ orders: [{ id: 3 }, { id: 3 }], nextCursor: null }, { orders: [{ id: 3 }], nextCursor: 4 }, { orders: [], nextCursor: 2 }])
        assert.throws(() => validateMakePage('orders.list', { before: 4 }, { ok: true, data }), /UPSTREAM_CONTRACT_FAILURE/);
});
