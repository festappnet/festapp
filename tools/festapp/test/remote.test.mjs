import {invokeFormOperation} from '../src/operations/forms.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer as httpServer } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { Client, StreamableHTTPClientTransport } from '@modelcontextprotocol/client';
import { Client as LegacyClient } from 'mcp-sdk-legacy/client/index.js';
import { StreamableHTTPClientTransport as LegacyHTTPClientTransport } from 'mcp-sdk-legacy/client/streamableHttp.js';
import { fixture, profile, actor, token as supabaseToken, reply } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, verifyPermissions } from '../src/remote/config.mjs';
import { openRemoteStorage } from '../src/remote/storage.mjs';
import { createRemoteApp } from '../src/remote/server.mjs';
import { DelegatedOwner, boundOwner } from '../src/remote/delegation.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { verifyConsent } from '../src/remote/consent.mjs';
import { verifySelection } from '../src/operations/access.mjs';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const secrets = { cookieKeys: ['a'.repeat(48), 'b'.repeat(48)], jwks: { keys: [{
    ...privateKey.export({ format: 'jwk' }), kid: 'fixture', use: 'sig', alg: 'RS256',
}] } };
const csrf = html => html.match(/name="csrf" value="([^"]+)"/)[1];
const rawProfile = () => { const { binding, ...p } = profile(); return p; };
const configuration = (issuer) => ({ schemaVersion: 2, issuer, profile: rawProfile(),
    clients: [{ id: 'chatgpt-fixture', name: 'ChatGPT fixture', redirectUris: [issuer + '/callback'] }],
});
async function setup(t, { native = false, tenant = false } = {}) {
    const base = await fixture(t, { fetchImpl: url => url.pathname.startsWith('/functions/v1/preview-ticket-layout')
        ? reply({ presets: {}, fonts: {} }) : undefined });
    const root = await mkdtemp(join(tmpdir(), 'festapp-remote-'));
    const key = randomBytes(32);
    const storage = await openRemoteStorage(root, key);
    const server = httpServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const issuer = `http://127.0.0.1:${server.address().port}`;
    const raw = configuration(issuer);
    if (native) raw.clients[0] = { id: 'codex-fixture', name: 'Codex fixture', applicationType: 'native', redirectUris: ['http://127.0.0.1/callback'] };
    if (tenant) raw.tenantOrigin = 'https://tenant.fixture.test';
    const config = parseRemoteConfig(raw);
    const audit = [];
    const service = createRemoteApp(config, storage, { ...secrets, brokerSecret: 'b'.repeat(43), fetchImpl: base.owner.fetch, audit: r => audit.push(r) });
    server.on('request', service.app);
    t.after(async () => { await new Promise(resolve => server.close(resolve)); await storage.close(); await rm(root, { recursive: true, force: true }); });
    const jar = new Map();
    const browser = async (path, body, extra = {}) => {
        const r = await fetch(new URL(path, issuer), { redirect: 'manual',
            method: body ? 'POST' : 'GET', body: body && new URLSearchParams(body),
            headers: { cookie: [...jar].map(([k, v]) => `${k}=${v}`).join('; '),
                ...(body ? { origin: issuer } : {}), ...extra } });
        for (const c of r.headers.getSetCookie()) {
            const [pair] = c.split(';'); const at = pair.indexOf('=');
            jar.set(pair.slice(0, at), pair.slice(at + 1));
        }
        return r;
    };
    return { ...base, root, key, storage, server, issuer, config, audit, browser, ...service };
}
async function connect(f, { badVerifier = false, clientId = 'chatgpt-fixture', callbackUri = f.issuer + '/callback', scope = READ_SCOPE, unitId, create = false } = {}) {
    const verifier = randomBytes(32).toString('base64url');
    const params = new URLSearchParams({ client_id: clientId, response_type: 'code',
        redirect_uri: callbackUri, scope: `openid offline_access ${scope}`,
        code_challenge: createHash('sha256').update(verifier).digest('base64url'),
        code_challenge_method: 'S256', resource: f.config.resource, state: 'fixture-state' });
    let r = await f.browser('/auth?' + params);
    assert.equal(r.status, 303);
    const location = r.headers.get('location');
    r = await f.browser(location);
    assert.equal(r.status, 200);
    const html = await r.text();
    const uid = new URL(location, f.issuer).pathname.split('/').at(-1);
    r = await f.browser(`/connect/${uid}/login`, { csrf: csrf(html), email: 'fixture@example.test', password: 'fixture-password' });
    assert.equal(r.status, 303);
    r = await f.browser(r.headers.get('location'));
    const consent = await r.text();
    assert.match(consent, /Povolit přístup/);
    assert.match(consent, /value="7"/);
    assert.doesNotMatch(consent, /value="8"/);
    r = await f.browser(`/connect/${uid}/consent`, { csrf: csrf(consent), ...(unitId ? { unit: String(unitId), ...(create ? { create: '1' } : {}) } : { occasion: '7' }) });
    assert.equal(r.status, 303);
    let redirect = r.headers.get('location');
    for (let i = 0; i < 8 && !new URL(redirect, f.issuer).pathname.startsWith('/callback'); i++) {
        r = await f.browser(redirect); redirect = r.headers.get('location');
        assert(redirect, `missing callback redirect, status ${r.status}: ${await r.text()}`);
    }
    const callback = new URL(redirect, f.issuer);
    assert.equal(callback.searchParams.get('state'), 'fixture-state');
    assert.equal(callback.searchParams.get('iss'), f.issuer);
    assert(callback.searchParams.get('code'), callback.href);
    const exchange = async (codeVerifier = verifier) => fetch(f.issuer + '/token', { method: 'POST', body: new URLSearchParams({
        client_id: clientId, grant_type: 'authorization_code', code: callback.searchParams.get('code'),
        redirect_uri: callbackUri, code_verifier: codeVerifier, resource: f.config.resource,
    }) });
    const response = await exchange(badVerifier ? 'wrong-verifier'.repeat(4) : verifier);
    assert.equal(response.status, badVerifier ? 400 : 200, await response.clone().text());
    return { callback, exchange, response, tokens: await response.json() };
}

test('remote configuration rejects insecure origins, redirects and duplicate identities', () => {
    const c = configuration('http://127.0.0.1:3456');
    assert.equal(parseRemoteConfig(c).resource, c.issuer + '/mcp');
    assert.throws(() => parseRemoteConfig({ ...c, issuer: 'http://public.example' }));
    assert.throws(() => parseRemoteConfig({ ...c, clients: [...c.clients, ...c.clients] }));
    assert.throws(() => parseRemoteConfig({ ...c, clients: [{ ...c.clients[0], redirectUris: ['https://user:password@example.test/callback'] }] }));
});

test('native OAuth accepts only explicit IP loopback callbacks and honors an ephemeral port', async t => {
    const f = await setup(t, { native: true });
    const { tokens, callback } = await connect(f, { clientId: 'codex-fixture', callbackUri: 'http://127.0.0.1:51789/callback' });
    assert.equal(callback.origin, 'http://127.0.0.1:51789');
    assert(tokens.access_token);
    for (const uri of ['http://localhost/callback', 'http://evil.example/callback', 'https://127.0.0.1/callback', 'http://127.0.0.1/callback?code=other']) {
        const c = configuration(f.issuer);
        c.clients[0] = { ...c.clients[0], applicationType: 'native', redirectUris: [uri] };
        assert.throws(() => parseRemoteConfig(c));
    }
    const request = new URLSearchParams({ client_id: 'codex-fixture', response_type: 'code', redirect_uri: 'http://127.0.0.1:51789/other',
        scope: READ_SCOPE, code_challenge_method: 'S256', code_challenge: 'a'.repeat(43) });
    assert.equal((await f.browser('/auth?' + request)).status, 400);
});

test('tenant consent uses app access proof, an independent session and the original OAuth browser', async t => {
    const f = await setup(t, { tenant: true });
    const verifier = 'v'.repeat(43);
    const query = new URLSearchParams({ client_id: 'chatgpt-fixture', response_type: 'code',
        redirect_uri: f.issuer + '/callback', resource: f.config.resource, scope: [READ_SCOPE, CREATE_SCOPE, ...MCP_SCOPES].join(' '),
        code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
    let r = await f.browser('/auth?' + query);
    const connectPath = r.headers.get('location');
    r = await f.browser(connectPath);
    assert.equal(r.status, 303);
    const tenant = new URL(r.headers.get('location'));
    assert.equal(tenant.origin, f.config.tenantOrigin);
    assert.equal(tenant.pathname, '/settings/mcp-connect');
    const request = tenant.searchParams.get('request');
    const broker = (operation, extra = {}, secret = 'b'.repeat(43)) => fetch(f.issuer + '/tenant-connection', {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-festapp-mcp-broker': secret },
        body: JSON.stringify({ operation, request, tenantId: f.config.profile.tenantId, organizationId: f.config.profile.organizationId, tenantOrigin: f.config.tenantOrigin, ...extra }),
    });
    assert.equal((await broker('details', { accessToken: supabaseToken }, 'wrong')).status, 403);
    assert.equal((await broker('details', { accessToken: supabaseToken, organizationId: 999 })).status, 403);
    assert.equal((await broker('details', { accessToken: supabaseToken, tenantOrigin: 'https://other.invalid' })).status, 403);
    r = await broker('details', { accessToken: supabaseToken });
    assert.equal(r.status, 200, await r.clone().text());
    const info = await r.json();
    assert.deepEqual(info.occasions.map(o => o.id), [7]);
    assert.equal((await broker('prepare', { accessToken: supabaseToken, access: { type: 'occasions', occasionIds: [8] } })).status, 403);
    // Merely displaying consent never mints or adopts a backend refresh session.
    assert.equal(f.calls.filter(c => c.url.pathname === '/auth/v1/token').length, 0);
    assert.equal(f.storage.values('Delegation').length, 0);
    r = await broker('prepare', { accessToken: supabaseToken, access: { consentVersion: 2, selection: { type: 'selection', units: [{ unitId: 3, canCreateOccasions: true }], occasionIds: [] }, permissions: MCP_SCOPES } });
    const prepared = await r.json();
    assert.equal(prepared.userId, actor);
    assert.deepEqual(await (await broker('status', { accessToken: supabaseToken })).json(), { status: 'pending' });
    assert.equal((await broker('prepare', { accessToken: supabaseToken, access: { type: 'occasions', occasionIds: [7] } })).status, 403);
    assert.equal((await broker('complete', { lease: 'wrong', session: {} })).status, 403);
    r = await broker('complete', { lease: prepared.lease,
        session: { access_token: supabaseToken, refresh_token: 'independent-broker-refresh' } });
    assert.equal(r.status, 200, await r.clone().text());
    const { resumeUrl } = await r.json();
    assert.equal((await broker('complete', { lease: prepared.lease })).status, 403);
    assert.equal((await fetch(resumeUrl, { redirect: 'manual' })).status, 400);
    r = await f.browser(resumeUrl);
    assert.equal(r.status, 303);
    let target = r.headers.get('location');
    for (let i = 0; i < 8 && !new URL(target, f.issuer).pathname.startsWith('/callback'); i++) {
        r = await f.browser(target); target = r.headers.get('location');
    }
    const callback = new URL(target, f.issuer);
    assert(callback.searchParams.get('code'));
    assert.deepEqual(await (await broker('status', { accessToken: supabaseToken })).json(), { status: 'pending' });
    r = await fetch(f.issuer + '/token', { method: 'POST', body: new URLSearchParams({
        grant_type: 'authorization_code', code: callback.searchParams.get('code'), client_id: 'chatgpt-fixture',
        redirect_uri: f.issuer + '/callback', code_verifier: verifier, resource: f.config.resource,
    }) });
    assert.equal(r.status, 200, await r.clone().text());
    const tokens = await r.json();
    assert(tokens.access_token);
    assert(tokens.scope.split(' ').includes(CREATE_SCOPE));
    assert(MCP_SCOPES.every(scope => tokens.scope.split(' ').includes(scope)));
    assert.deepEqual(f.storage.values('Delegation')[0].permissions, MCP_SCOPES);
    assert.deepEqual(await (await broker('status', { accessToken: supabaseToken })).json(), { status: 'pending' });
    assert.equal(f.storage.values('Delegation').length, 1);
    assert.deepEqual(f.storage.values('Delegation')[0].access, { type: 'selection', units: [{ unitId: 3, canCreateOccasions: true }], occasionIds: [] });
    const client = new Client({ name: 'tenant-consent-test', version: '1' }, { versionNegotiation: { mode: { pin: '2026-07-28' } } });
    await client.connect(new StreamableHTTPClientTransport(new URL(f.config.resource), {
        requestInit: { headers: { authorization: `Bearer ${tokens.access_token}` } },
    }));
    t.after(() => client.close());
    const tools = await client.listTools();
    assert(tools.tools.some(t => t.name === 'festapp_orders_update' && t.annotations.destructiveHint === true));
    assert(tools.tools.some(t => t.name === 'festapp_orders_report' && t.annotations.readOnlyHint === true));
    assert(tools.tools.some(t => t.name === 'festapp_products_list' && t.annotations.readOnlyHint === true));
    assert(tools.tools.some(t => t.name === 'festapp_products_save' && t.annotations.destructiveHint === true));
    assert.deepEqual(await (await broker('status', { accessToken: supabaseToken })).json(), { status: 'connected' });
    const result = await client.callTool({ name: 'festapp_context_inspect', arguments: {} });
    assert.equal(result.isError, undefined);
    // Account management is independent of the consent request and password login.
    const manage = (operation, extra = {}, secret = 'b'.repeat(43)) => fetch(f.issuer + '/tenant-connections', {
        method: 'POST', headers: { 'content-type': 'application/json', 'x-festapp-mcp-broker': secret },
        body: JSON.stringify({ operation, accessToken: supabaseToken, tenantId: f.config.profile.tenantId,
            organizationId: f.config.profile.organizationId, tenantOrigin: f.config.tenantOrigin, ...extra }),
    });
    const own = f.storage.values('Delegation')[0];
    f.storage.put('Delegation', 'foreign-grant', { ...own, id: 'foreign-grant', userId: 'other-user' });
    f.storage.put('Delegation', 'foreign-profile', { ...own, id: 'foreign-profile', profileBinding: 'other-profile' });
    const mintedBefore = f.calls.filter(c => c.url.pathname === '/auth/v1/token').length;
    assert.equal((await manage('list', {}, 'wrong')).status, 403);
    assert.equal((await manage('list', { organizationId: 999 })).status, 403);
    assert.equal((await manage('list', { tenantOrigin: 'https://wrong.invalid' })).status, 403);
    assert.notEqual((await manage('list', { accessToken: null })).status, 200);
    assert.equal((await manage('list', { userId: 'other-user' })).status, 403);
    const listed = await (await manage('list')).json();
    assert.deepEqual(listed.connections.map(c => c.id), [own.id]);
    assert.equal(listed.connections[0].client, 'ChatGPT fixture');
    assert.deepEqual(listed.connections[0].permissions, MCP_SCOPES);
    assert.doesNotMatch(JSON.stringify(listed), /refresh_token|accessToken|profileBinding|binding|userId/);
    assert.equal((await manage('revoke', { connectionId: 'foreign-grant' })).status, 403);
    assert.equal((await manage('revoke', { connectionId: 'foreign-profile' })).status, 403);
    assert.equal((await manage('revoke', { connectionId: 'missing' })).status, 403);
    assert.equal((await f.browser('/connections')).headers.get('location'), f.config.tenantOrigin + '/settings/connections');
    assert.deepEqual(await (await manage('revoke', { connectionId: own.id })).json(), { connectionId: own.id, revoked: true });
    assert.deepEqual(await (await manage('revoke', { connectionId: own.id })).json(), { connectionId: own.id, revoked: true });
    assert.deepEqual(await (await manage('list')).json(), { connections: [] });
    assert.equal(f.calls.filter(c => c.url.pathname === '/auth/v1/token').length, mintedBefore, 'management never creates a backend session');
    assert.equal(f.storage.get('Backend', own.binding), undefined);
    assert.equal((await fetch(f.config.resource, { method: 'POST', headers: { authorization: `Bearer ${tokens.access_token}`, 'content-type': 'application/json' }, body: '{}' })).status, 401);
    assert.equal((await fetch(f.issuer + '/token', { method: 'POST', body: new URLSearchParams({ client_id: 'chatgpt-fixture', grant_type: 'refresh_token', refresh_token: tokens.refresh_token, resource: f.config.resource }) })).status, 400);
    assert.equal((await broker('status', { accessToken: supabaseToken })).status, 403);
});

test('tenant cancellation and expired requests cannot issue or prepare a grant', async t => {
    const f = await setup(t, { tenant: true });
    const start = async () => {
        const q = new URLSearchParams({ client_id: 'chatgpt-fixture', response_type: 'code',
            redirect_uri: f.issuer + '/callback', resource: f.config.resource, scope: READ_SCOPE,
            code_challenge: 'a'.repeat(43), code_challenge_method: 'S256' });
        let r = await f.browser('/auth?' + q);
        const path = r.headers.get('location'); r = await f.browser(path);
        return { uid: path.split('/').at(-1), request: new URL(r.headers.get('location')).searchParams.get('request') };
    };
    const first = await start();
    const broker = (request, operation, extra = {}) => fetch(f.issuer + '/tenant-connection', { method: 'POST',
        headers: { 'content-type': 'application/json', 'x-festapp-mcp-broker': 'b'.repeat(43) },
        body: JSON.stringify({ request, operation, tenantId: f.config.profile.tenantId, organizationId: f.config.profile.organizationId, tenantOrigin: f.config.tenantOrigin, ...extra }) });
    let r = await broker(first.request, 'cancel');
    const { resumeUrl } = await r.json();
    r = await f.browser(resumeUrl);
    assert.equal(r.status, 303);
    assert.equal((await broker(first.request, 'prepare', { accessToken: supabaseToken, access: { type: 'occasions', occasionIds: [7] } })).status, 403);
    assert.equal(f.storage.values('Delegation').length, 0);
    const second = await start();
    f.storage.put('Connect', second.uid, { ...f.storage.get('Connect', second.uid), expiresAt: Date.now() - 1 }, 60);
    assert.equal((await broker(second.request, 'details', { accessToken: supabaseToken })).status, 403);
    assert.equal(f.calls.filter(c => c.url.pathname === '/auth/v1/token').length, 0);
});

test('encrypted durable adapter survives restart and refuses another process or key', async t => {
    const root = await mkdtemp(join(tmpdir(), 'festapp-store-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const key = randomBytes(32);
    let s = await openRemoteStorage(root, key);
    s.put('Backend', 'binding', { refreshToken: 'never-plaintext', userId: actor });
    const adapter = s.adapter('AuthorizationCode');
    await adapter.upsert('one-time-code', { grantId: 'test' }, 60);
    const consumed = await Promise.allSettled([adapter.consume('one-time-code'), adapter.consume('one-time-code')]);
    assert.equal(consumed.filter(r => r.status === 'fulfilled').length, 1);
    assert(!(await readFile(join(root, 'remote.sqlite'))).includes(Buffer.from('never-plaintext')));
    await assert.rejects(openRemoteStorage(root, key));
    await s.close();
    await assert.rejects(openRemoteStorage(root, randomBytes(32)));
    s = await openRemoteStorage(root, key);
    assert.equal(s.get('Backend', 'binding').refreshToken, 'never-plaintext');
    await s.close();
});

test('OAuth discovery, exact callbacks, browser CSRF and PKCE fail closed', async t => {
    const f = await setup(t);
    const metadata = await (await fetch(f.issuer + '/.well-known/openid-configuration')).json();
    assert(metadata.code_challenge_methods_supported.includes('S256'));
    assert.equal(metadata.authorization_response_iss_parameter_supported, true);
    assert.equal(metadata.registration_endpoint, undefined);
    const oauthMetadata = await fetch(f.issuer + '/.well-known/oauth-authorization-server', { redirect: 'manual' });
    assert.equal(oauthMetadata.status, 200);
    assert.equal((await oauthMetadata.json()).issuer, f.issuer);
    const challenge = await fetch(f.issuer + '/mcp', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
    assert.equal(challenge.status, 401);
    assert.match(challenge.headers.get('www-authenticate'), /oauth-protected-resource/);
    for (const bearer of [supabaseToken, 'invented-access-token-1234567890']) {
        assert.equal((await fetch(f.issuer + '/mcp', { method: 'POST', headers: { authorization: `Bearer ${bearer}`, 'content-type': 'application/json' }, body: '{}' })).status, 401);
    }
    const forged = await f.browser('/auth?' + new URLSearchParams({ client_id: 'chatgpt-fixture', response_type: 'code', redirect_uri: 'https://evil.example/callback', scope: 'openid' }));
    assert.equal(forged.status, 400);
    const { response } = await connect(f, { badVerifier: true });
    assert.equal(response.status, 400);
    const flow = f.storage.values('Delegation')[0];
    assert.equal(flow.access.occasionIds.join(','), '7');
    assert(!JSON.stringify(f.audit).includes('fixture-password'));
});

for (const modern of [true, false]) test(`real OAuth code exchange and ${modern ? '2026-07-28' : 'legacy'} SDK HTTP reads, rotating refresh and browser revocation`, async t => {
    const f = await setup(t);
    const { tokens, exchange } = await connect(f);
    assert.equal(tokens.token_type, 'Bearer');
    assert(tokens.refresh_token);
    assert.notEqual(tokens.access_token, supabaseToken);
    const client = new (modern ? Client : LegacyClient)({ name: 'remote-fixture', version: '1' }, modern ? { versionNegotiation: { mode: { pin: '2026-07-28' } } } : {});
    t.after(() => client.close());
    await client.connect(new (modern ? StreamableHTTPClientTransport : LegacyHTTPClientTransport)(new URL(f.config.resource), {
        requestInit: { headers: { authorization: `Bearer ${tokens.access_token}` } },
    }));
    if (modern) assert.equal(client.getProtocolEra(), 'modern');
    const list = await client.listTools();
    assert.deepEqual(list.tools.map(t => t.name), ['festapp_access_inspect', 'festapp_context_inspect', 'festapp_ticket_layouts_inspect']);
    const result = await client.callTool({ name: 'festapp_context_inspect', arguments: {} });
    assert.equal(result.structuredContent.ok, true);
    assert.equal(result.structuredContent.data.writesEnabled, false);
    const denied = await client.callTool({ name: 'festapp_ticket_layouts_inspect', arguments: { occasionId: 8 } });
    assert.equal(denied.isError, true);
    assert.equal(denied.structuredContent.error.code, 'FORBIDDEN');
    const refresh = await fetch(f.issuer + '/token', { method: 'POST', body: new URLSearchParams({
        client_id: 'chatgpt-fixture', grant_type: 'refresh_token', refresh_token: tokens.refresh_token,
        resource: f.config.resource,
    }) });
    assert.equal(refresh.status, 200, await refresh.clone().text());
    const next = await refresh.json();
    assert.notEqual(next.refresh_token, tokens.refresh_token);
    const authOriginDenied = await fetch(f.config.resource, { method: 'POST',
        headers: { origin: 'https://evil.example', authorization: `Bearer ${next.access_token}`, 'content-type': 'application/json' }, body: '{}' });
    assert.equal(authOriginDenied.status, 403);
    let r = await f.browser('/connections');
    const login = await r.text();
    r = await f.browser('/connections/login', { csrf: csrf(login), email: 'fixture@example.test', password: 'fixture-password' });
    assert.equal(r.status, 303);
    r = await f.browser('/connections');
    const management = await r.text();
    assert.match(management, /ChatGPT fixture/);
    const grant = f.storage.values('Delegation')[0];
    const noOrigin = await f.browser('/connections/revoke', { csrf: csrf(management), grant: grant.id }, { origin: 'https://evil.example' });
    assert.equal(noOrigin.status, 403);
    r = await f.browser('/connections/revoke', { csrf: csrf(management), grant: grant.id });
    assert.equal(r.status, 303);
    assert.equal(f.storage.get('Delegation', grant.id).revoked, true);
    const revoked = await fetch(f.config.resource, { method: 'POST', headers: {
        authorization: `Bearer ${next.access_token}`, 'content-type': 'application/json',
    }, body: '{}' });
    assert.equal(revoked.status, 401);
    assert.equal((await exchange()).status, 400, 'authorization code is single use');
    assert(!JSON.stringify(f.audit).includes(tokens.access_token));
});

test('delegated handlers deny other occasions and writes and discard a revoked in-flight read', async t => {
    const f = await setup(t);
    const bound = boundOwner(f.config, f.storage, 'grant-binding', { fetchImpl: f.owner.fetch });
    await bound.login('fixture@example.test', 'fixture-password');
    const grant = { id: 'grant-1', userId: actor, clientId: 'chatgpt-fixture', binding: 'grant-binding',
        profileBinding: f.config.profile.binding, access: { type: 'occasions', occasionIds: [7] }, expiresAt: Date.now() + 60000, revoked: false };
    f.storage.put('Delegation', grant.id, grant);
    const token = { grantId: grant.id, accountId: actor, clientId: grant.clientId, aud: f.config.resource,
        exp: Math.floor(Date.now() / 1000) + 300, scope: READ_SCOPE };
    for (const bad of [{ aud: 'https://wrong.example/mcp' }, { scope: 'openid' },
        { accountId: '00000000-0000-4000-8000-000000000002' }, { clientId: 'other-client' }, { exp: 1 }])
        assert.throws(() => new DelegatedOwner(f.config, f.storage, { ...token, ...bad }), /FORBIDDEN/);
    const owner = new DelegatedOwner(f.config, f.storage, token, { fetchImpl: f.owner.fetch });
    const ops = new Operations(owner);
    assert.deepEqual(ops.catalog.map(d => d.id), ['access.inspect', 'context.inspect', 'ticket_layouts.inspect']);
    const before = f.calls.length;
    assert.equal((await ops.invoke('ticket_layouts.inspect', { occasionId: 8 })).error.code, 'FORBIDDEN');
    assert.equal(f.calls.length, before);
    assert.equal((await ops.invoke('ticket_layouts.save', {})).ok, false);
    const read = await ops.invoke('ticket_layouts.inspect', { occasionId: 7 });
    assert.equal(read.ok, true, JSON.stringify(read));
    f.storage.put('Binding', grant.binding, { id: grant.id });
    await assert.rejects(owner.authorized(async () => { f.storage.revoke(grant.id); return 'secret'; }), /FORBIDDEN/);
    assert.equal(f.storage.get('Backend', grant.binding), undefined);
    await assert.rejects(f.storage.backendStore.write(grant.binding, { userId: actor, refreshToken: 'late-rotation' }), /CONNECTION_REVOKED/);
    assert.throws(() => owner.current(), /FORBIDDEN/);
});

test('two delegated actors on one process keep their refresh sessions and identities separate', async t => {
    const f = await setup(t);
    const otherActor = '00000000-0000-4000-8000-000000000002';
    const other = await fixture(t, { userId: otherActor });
    const config = f.config;
    const owners = [];
    for (const [userId, upstream] of [[actor, f.owner.fetch], [otherActor, other.owner.fetch]]) {
        const binding = `actor-${userId}`;
        await boundOwner(config, f.storage, binding, { fetchImpl: upstream }).login('fixture@example.test', 'fixture-password');
        const id = `grant-${userId}`;
        f.storage.put('Delegation', id, { id, userId, clientId: 'chatgpt-fixture', binding,
            profileBinding: config.profile.binding, access: { type: 'occasions', occasionIds: [7] }, expiresAt: Date.now() + 60000, revoked: false });
        owners.push(new DelegatedOwner(config, f.storage, { grantId: id, accountId: userId,
            clientId: 'chatgpt-fixture', aud: config.resource, scope: READ_SCOPE, exp: Date.now() / 1000 + 300 }, { fetchImpl: upstream }));
    }
    const results = await Promise.all(owners.map(o => new Operations(o).invoke('context.inspect', {})));
    assert.deepEqual(results.map(r => r.data.userId), [actor, otherActor]);
    f.storage.revoke(`grant-${actor}`);
    assert.equal((await new Operations(owners[1]).invoke('context.inspect', {})).data.userId, otherActor);
});

test('organizer consent needs requested create scope; read consent never exposes creation', async t => {
    const denied = await setup(t);
    await assert.rejects(connect(denied, { unitId: 3, create: true }), /403/);
    const f = await setup(t);
    const { tokens } = await connect(f, { unitId: 3 });
    const token = await f.provider.AccessToken.find(tokens.access_token);
    const owner = new DelegatedOwner(f.config, f.storage, token, { fetchImpl: f.owner.fetch });
    assert(!owner.allowedOperations.includes('occasions.create'));
    const listed = await new Operations(owner).invoke('access.inspect', {});
    assert.equal(listed.ok, true);
    assert.equal(listed.data.units[0].canCreateOccasions, false);
    const start=f.calls.length;
    assert.equal((await new Operations(owner).invoke('ticket_layouts.inspect',{occasionId:7})).ok,true);
    const sqlRequests=f.calls.slice(start).filter(c=>c.url.pathname.startsWith('/rest/v1/rpc/'));
    assert.equal(sqlRequests.length,1,'delegated inspection has no separate permission RPC');
    assert.equal(sqlRequests[0].url.pathname,'/rest/v1/rpc/get_delegated_ticket_layout_for_authoring_v1');
    const requestBody=JSON.parse(sqlRequests[0].init.body);
    assert.equal(requestBody.p_unit,3);assert.equal(requestBody.p_organization,1);
    const withScope = await setup(t);
    const connected = await connect(withScope, { unitId: 3, create: true, scope: `${READ_SCOPE} ${CREATE_SCOPE}` });
    const authorized = new DelegatedOwner(withScope.config, withScope.storage,
        await withScope.provider.AccessToken.find(connected.tokens.access_token), { fetchImpl: withScope.owner.fetch });
    assert(authorized.allowedOperations.includes('occasions.create'));
    assert.throws(() => authorized.authorizeOperation('occasions.create', { unitId: 4 }), /FORBIDDEN/);
    await authorized.authorizeOperation('occasions.create', { unitId: 3 });
});


test('tree consent validates every organizer, occasion and create permission', () => {
    const available={units:[{id:3,canCreateOccasions:true},{id:4,canCreateOccasions:false}],occasions:[{id:7,unitId:3},{id:8,unitId:5}]};
    const selection={type:'selection',units:[{unitId:3,canCreateOccasions:true},{unitId:4,canCreateOccasions:false}],occasionIds:[8]};
    assert.deepEqual(verifySelection(selection,available,true),selection);
    for (const invalid of [
        {...selection,units:[{unitId:3,canCreateOccasions:true},{unitId:999,canCreateOccasions:false}]},
        {...selection,units:[{unitId:4,canCreateOccasions:true}]},
        {...selection,units:[{unitId:3,canCreateOccasions:false},{unitId:3,canCreateOccasions:true}]},
        {...selection,occasionIds:[999]}, {type:'selection',units:[],occasionIds:[]},
    ]) assert.throws(()=>verifySelection(invalid,available,true),/FORBIDDEN/);
    assert.throws(()=>verifySelection(selection,available,false),/FORBIDDEN/);
});

test('tree grant includes future occasions only in selected organizers and keeps creation scoped', async t => {
    const f=await setup(t);
    const binding='tree-session';
    await boundOwner(f.config,f.storage,binding,{fetchImpl:f.owner.fetch}).login('fixture@example.test','fixture-password');
    const id='tree-grant';
    f.storage.put('Delegation',id,{id,userId:actor,clientId:'chatgpt-fixture',binding,
        profileBinding:f.config.profile.binding,access:{type:'selection',units:[{unitId:3,canCreateOccasions:true},{unitId:4,canCreateOccasions:false}],occasionIds:[8]},expiresAt:Date.now()+60000,revoked:false});
    const owner=new DelegatedOwner(f.config,f.storage,{grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:READ_SCOPE+' '+CREATE_SCOPE,exp:Date.now()/1000+300},{fetchImpl:f.owner.fetch});
    let occasions=[{id:7,title:'Current',unitId:3},{id:8,title:'Selected separately',unitId:5},{id:9,title:'Other organizer',unitId:5},{id:10,title:'Second organizer',unitId:4}];
    const client={rpc:async()=>({data:{units:[{id:3,title:'First',canCreateOccasions:true},{id:4,title:'Second',canCreateOccasions:true},{id:5,title:'Excluded',canCreateOccasions:true}],occasions:occasions.map(o=>({...o,capabilities:{'ticket_layouts.read':true}}))},error:null})};
    const listed=await owner.listAccess(client);
    assert.deepEqual(listed.occasions.map(o=>o.id),[7,8,10]);
    assert.deepEqual(listed.units.map(u=>u.canCreateOccasions),[true,false]);
    occasions.push({id:11,title:'Future',unitId:4});
    assert.deepEqual((await owner.listAccess(client)).occasions.map(o=>o.id),[7,8,10,11]);
    assert.deepEqual(await owner.delegatedContext(client,11),{organizationId:1,unitId:4});
    assert.deepEqual(await owner.delegatedContext(client,8),{organizationId:1,unitId:null});
    await assert.rejects(owner.delegatedContext(client,9),/FORBIDDEN/);
    occasions[0].unitId=5;
    await assert.rejects(owner.delegatedContext(client,7),/FORBIDDEN/);
    assert.throws(()=>owner.authorizeOperation('occasions.create',{unitId:4}),/FORBIDDEN/);
    assert.throws(()=>owner.authorizeOperation('occasions.create',{unitId:5}),/FORBIDDEN/);
    owner.authorizeOperation('occasions.create',{unitId:3});
    const readOnly=new DelegatedOwner(f.config,f.storage,{...owner.token,scope:READ_SCOPE},{fetchImpl:f.owner.fetch});
    assert(!readOnly.allowedOperations.includes('occasions.create'));
    f.storage.revoke(id);await assert.rejects(owner.delegatedContext(client,8),/FORBIDDEN/);
});


test('order permissions require explicit requested consent and both persisted grant and OAuth token scopes', async t => {
    assert.deepEqual(verifyPermissions(undefined,MCP_SCOPES),[]);
    const available={units:[],occasions:[{id:7}]};
    const selected={type:'occasions',occasionIds:[7]};
    assert.deepEqual(verifyConsent(selected,available,false,MCP_SCOPES).permissions,[]);
    for(const raw of [{consentVersion:3,selection:selected,permissions:[]},{consentVersion:2,selection:selected,permissions:[],admin:true},{consentVersion:2,selection:selected,permissions:['festapp:orders:write']}]) assert.throws(()=>verifyConsent(raw,available,false,MCP_SCOPES),/FORBIDDEN/);
    assert.throws(()=>verifyPermissions(['festapp:orders:write'],MCP_SCOPES),/FORBIDDEN/);
    assert.throws(()=>verifyPermissions(['festapp:orders:read'],[]),/FORBIDDEN/);
    assert.throws(()=>verifyPermissions(['arbitrary:admin'],MCP_SCOPES),/FORBIDDEN/);
    assert.throws(()=>verifyPermissions(['festapp:products:write'],MCP_SCOPES),/FORBIDDEN/);
    assert.deepEqual(verifyPermissions(['festapp:products:read'],MCP_SCOPES),['festapp:products:read']);
    const f=await setup(t);
    const id='order-permissions';const binding='order-permissions-session';
    const grant={id,binding,userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},expiresAt:Date.now()+60000,revoked:false};
    const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
    const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
    f.storage.put('Delegation',id,grant);
    assert(!owner().allowedOperations.includes('orders.list'),'old consent never acquires order access from a broader token');
    f.storage.put('Delegation',id,{...grant,permissions:['festapp:orders:read']});
    const readOnly=owner();assert(readOnly.allowedOperations.includes('orders.report'));assert(!readOnly.allowedOperations.includes('orders.update'));
    f.storage.put('Delegation',id,{...grant,permissions:MCP_SCOPES});
    assert(!readOnly.allowedOperations.includes('products.list'), 'order consent never expands to catalog administration');
    const all=owner();assert(all.allowedOperations.includes('products.save'));assert(all.allowedOperations.includes('payments.record'));assert(all.allowedOperations.includes('orders.send_tickets'));
    assert.throws(()=>all.authorizeOperation('orders.list',{occasionId:8}),/FORBIDDEN/);
    token.scope=READ_SCOPE;assert(!owner().allowedOperations.includes('products.list'));assert(!owner().allowedOperations.includes('orders.list'),'grant cannot exceed the current OAuth token');
});

test('product schedule tools require new explicit consent; old product grants stay unchanged',async t=>{
 const f=await setup(t);const id='schedule-permissions';
 const permissions=['festapp:products:read','festapp:products:write'];
 const grant={id,binding:'schedule-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions,expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(owner().allowedOperations.includes('products.save'));
 assert(!owner().allowedOperations.includes('product_schedules.list'));
 assert(!owner().allowedOperations.includes('product_schedules.change'));
 assert(!owner().allowedOperations.includes('inventory.prepare_standing'));
 assert(!owner().allowedOperations.includes('inventory.pools.list'));
 assert(!owner().allowedOperations.includes('inventory.contexts.list'));
 assert.throws(()=>verifyPermissions(['festapp:product-schedules:write'],MCP_SCOPES));
 const scheduled=['festapp:products:read','festapp:product-schedules:read','festapp:product-schedules:write'];
 assert.deepEqual(verifyPermissions(scheduled,MCP_SCOPES),scheduled);
 f.storage.put('Delegation',id,{...grant,permissions:scheduled});
 assert(owner().allowedOperations.includes('product_schedules.change'));
 token.scope=[READ_SCOPE,'festapp:products:read','festapp:product-schedules:read'].join(' ');
 assert(owner().allowedOperations.includes('product_schedules.list'));
 assert(!owner().allowedOperations.includes('product_schedules.change'),'token must also include explicit write scope');
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:products:read','festapp:standing-inventory:write']});
 token.scope=[READ_SCOPE,...MCP_SCOPES].join(' ');
 assert(owner().allowedOperations.includes('inventory.prepare_standing'));
 token.scope=READ_SCOPE+' festapp:products:read';
 assert(!owner().allowedOperations.includes('inventory.prepare_standing'),'standing preparation requires its explicit token scope');
});


test('inventory summaries require inventory consent in both grant and token',async t=>{
 const f=await setup(t),id='inventory-read-permissions';
 const grant={id,binding:'inventory-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:inventory:read'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:READ_SCOPE+' festapp:inventory:read',exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert.deepEqual(verifyPermissions(grant.permissions,MCP_SCOPES),grant.permissions);
 for(const op of ['inventory.pools.list','inventory.contexts.list']) assert(owner().allowedOperations.includes(op));
 assert(!owner().allowedOperations.includes('inventory.prepare_standing'));
 token.scope=READ_SCOPE;assert(!owner().allowedOperations.includes('inventory.pools.list'));
 token.scope=READ_SCOPE+' festapp:inventory:read';f.storage.put('Delegation',id,{...grant,permissions:['festapp:products:read']});
 assert(!owner().allowedOperations.includes('inventory.contexts.list'));
});

test('inventory writes require new consent and token scope, separate from standing and inventory reads',async t=>{
 const f=await setup(t),id='inventory-write-permissions';
 const grant={id,binding:'inventory-write-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:inventory:read'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('inventory.change'));assert.throws(()=>verifyPermissions(['festapp:inventory:write'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:inventory:read','festapp:inventory:write']});assert(owner().allowedOperations.includes('inventory.change'));
 token.scope=READ_SCOPE+' festapp:inventory:read';assert(!owner().allowedOperations.includes('inventory.change'));
 token.scope=[READ_SCOPE,...MCP_SCOPES].join(' ');f.storage.put('Delegation',id,{...grant,permissions:['festapp:products:read','festapp:standing-inventory:write']});assert(!owner().allowedOperations.includes('inventory.change'));
});

test('unused product choices require explicit consent beyond previously issued product grants',async t=>{
 const f=await setup(t),id='product-options-permissions';const permissions=['festapp:products:read','festapp:products:write'];
 const grant={id,binding:'product-options-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions,expiresAt:Date.now()+60000,revoked:false};f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('products.options'));assert.throws(()=>verifyPermissions(['festapp:product-options:read'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:products:read','festapp:product-options:read']});assert(owner().allowedOperations.includes('products.options'));
 token.scope=READ_SCOPE+' festapp:products:read';assert(!owner().allowedOperations.includes('products.options'));
});

test('seat lifecycle reads and blocking require separate explicit grants and token scopes',async t=>{
 const f=await setup(t),id='seat-permissions';const grant={id,binding:'seat-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:orders:read','festapp:orders:write','festapp:inventory:read','festapp:inventory:write'],expiresAt:Date.now()+60000,revoked:false};f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});assert(!owner().allowedOperations.includes('seats.list'));assert(!owner().allowedOperations.includes('seats.block'));assert.throws(()=>verifyPermissions(['festapp:seats:block'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:seats:read']});assert(owner().allowedOperations.includes('seats.list'));assert(!owner().allowedOperations.includes('seats.preview_block'));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:seats:read','festapp:seats:block']});assert(owner().allowedOperations.includes('seats.block'));token.scope=READ_SCOPE+' festapp:seats:read';assert(!owner().allowedOperations.includes('seats.block'));
});

test('hold release needs explicit permission independently of seat blocking or order grants',async t=>{
 const f=await setup(t),id='hold-release-permissions';const grant={id,binding:'hold-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:seats:read','festapp:seats:block','festapp:orders:read','festapp:orders:write'],expiresAt:Date.now()+60000,revoked:false};f.storage.put('Delegation',id,grant);const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});assert(!owner().allowedOperations.includes('seats.release_holds'));assert.throws(()=>verifyPermissions(['festapp:seats:release-holds'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:seats:read','festapp:seats:release-holds']});assert(owner().allowedOperations.includes('seats.preview_release'));assert(owner().allowedOperations.includes('seats.release_holds'));assert(!owner().allowedOperations.includes('seats.block'));token.scope=READ_SCOPE+' festapp:seats:read';assert(!owner().allowedOperations.includes('seats.release_holds'));
});

test('seat swaps require their own financial-effect consent and both seat/order reads',async t=>{
 const f=await setup(t),id='seat-swap-permissions';const grant={id,binding:'swap-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:seats:read','festapp:seats:block','festapp:seats:release-holds','festapp:orders:read','festapp:orders:write','festapp:payments:write'],expiresAt:Date.now()+60000,revoked:false};f.storage.put('Delegation',id,grant);const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});assert(!owner().allowedOperations.includes('seats.swap'));
 for(const missing of ['festapp:seats:read','festapp:orders:read'])assert.throws(()=>verifyPermissions(['festapp:seats:read','festapp:orders:read','festapp:seats:swap'].filter(p=>p!==missing),MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:seats:read','festapp:orders:read','festapp:seats:swap']});assert(owner().allowedOperations.includes('seats.preview_swap'));assert(owner().allowedOperations.includes('seats.swap'));assert(!owner().allowedOperations.includes('seats.release_holds'));token.scope=READ_SCOPE+' festapp:seats:read festapp:orders:read';assert(!owner().allowedOperations.includes('seats.swap'));
});

test('seat order creation requires explicit consent and both semantic preview reads',async t=>{
 const f=await setup(t),id='seat-order-permissions';
 const grant={id,binding:'seat-order-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:seats:read','festapp:orders:read','festapp:orders:write','festapp:seats:swap'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('seats.create_order'));
 const explicit=['festapp:seats:read','festapp:orders:read','festapp:seats:create-orders'];
 for(const missing of explicit.slice(0,2))assert.throws(()=>verifyPermissions(explicit.filter(p=>p!==missing),MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:explicit});
 assert(owner().allowedOperations.includes('seats.preview_order'));assert(owner().allowedOperations.includes('seats.create_order'));
 assert(!owner().allowedOperations.includes('seats.swap'));
 token.scope=READ_SCOPE+' festapp:seats:read festapp:orders:read';assert(!owner().allowedOperations.includes('seats.create_order'));
});

test('seat cancellation requires fresh explicit consent and both semantic reads',async t=>{
 const f=await setup(t),id='seat-cancellation-permissions';
 const grant={id,binding:'seat-cancellation-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,access:{type:'occasions',occasionIds:[7]},permissions:['festapp:seats:read','festapp:orders:read','festapp:orders:write','festapp:seats:swap'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('seats.cancel_tickets'));
 const explicit=['festapp:seats:read','festapp:orders:read','festapp:seats:cancel-tickets'];
 for(const missing of explicit.slice(0,2))assert.throws(()=>verifyPermissions(explicit.filter(p=>p!==missing),MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:explicit});
 assert(owner().allowedOperations.includes('seats.preview_cancel'));assert(owner().allowedOperations.includes('seats.cancel_tickets'));
 assert(!owner().allowedOperations.includes('seats.swap'));
 token.scope=READ_SCOPE+' festapp:seats:read festapp:orders:read';assert(!owner().allowedOperations.includes('seats.cancel_tickets'));
});

test('email template consent never expands old grants or promotes occasion access into organizer access',async t=>{
 const f=await setup(t),id='email-template-permissions';
 const grant={id,binding:'email-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,
  access:{type:'occasions',occasionIds:[7]},permissions:['festapp:orders:read','festapp:orders:write'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);
 const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('email_templates.inspect'));
 assert.throws(()=>verifyPermissions(['festapp:email-templates:write'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:email-templates:read','festapp:email-templates:write']});
 assert(owner().allowedOperations.includes('email_templates.change'));assert(owner().allowedOperations.includes('email_templates.preview'));
 await owner().authorizeOperation('email_templates.inspect',{entityType:'occasion',entityId:7});
 assert.throws(()=>owner().authorizeOperation('email_templates.inspect',{entityType:'occasion',entityId:8}));
 assert.throws(()=>owner().authorizeOperation('email_templates.change',{entityType:'unit',entityId:1}));
 await assert.rejects(owner().delegatedUnitContext({},1));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:email-templates:read','festapp:email-templates:write'],access:{type:'selection',occasionIds:[7],units:[{unitId:11,canCreateOccasions:false}]}});
 await owner().authorizeOperation('email_templates.change',{entityType:'unit',entityId:11});
 assert.equal((await owner().delegatedUnitContext({},11)).unitId,11);
 assert.throws(()=>owner().authorizeOperation('email_templates.change',{entityType:'unit',entityId:12}));
 token.scope=READ_SCOPE+' festapp:email-templates:read';assert(!owner().allowedOperations.includes('email_templates.change'));
});


test('form scopes do not widen older grants and copy must consent both source and target',async t=>{
 const f=await setup(t),id='form-authoring-permissions';
 const grant={id,binding:'form-session',userId:actor,clientId:'chatgpt-fixture',profileBinding:f.config.profile.binding,
  access:{type:'occasions',occasionIds:[7]},permissions:['festapp:products:read','festapp:products:write'],expiresAt:Date.now()+60000,revoked:false};
 f.storage.put('Delegation',id,grant);const token={grantId:id,accountId:actor,clientId:'chatgpt-fixture',aud:f.config.resource,scope:[READ_SCOPE,...MCP_SCOPES].join(' '),exp:Date.now()/1000+300};
 const owner=()=>new DelegatedOwner(f.config,f.storage,token,{fetchImpl:f.owner.fetch});
 assert(!owner().allowedOperations.includes('forms.save'));assert.throws(()=>verifyPermissions(['festapp:forms:write'],MCP_SCOPES));
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:forms:read','festapp:forms:write']});assert(owner().allowedOperations.includes('forms.duplicate'));
 const args={occasionId:7,sourceOccasionId:9,sourceFormId:42,locale:'cs',commandId:'00000000-0000-4000-8000-000000000099'};let calls=0;
 const client={rpc:async(name,p)=>{calls++;assert.equal(name,'manage_form');assert.equal(p.p_payload.source_occasion_id,9);assert.equal(p.p_payload.source_unit_id,null);
  return{error:null,data:{code:200,status:'applied',mutation:{commandId:args.commandId,receiptId:args.commandId},data:{occasionId:7,formId:88,authoring:{form:{id:88,occasion:7,aggregate_version:0},fields:[],productTypes:[],products:[],productVersions:{},productTypeVersions:{}}}}};}};
 await assert.rejects(invokeFormOperation(owner(),client,'forms.duplicate',args),e=>e.code==='FORBIDDEN');assert.equal(calls,0);
 f.storage.put('Delegation',id,{...grant,permissions:['festapp:forms:read','festapp:forms:write'],access:{type:'occasions',occasionIds:[7,9]}});
 assert.equal((await invokeFormOperation(owner(),client,'forms.duplicate',args)).formId,88);assert.equal(calls,1);
 token.scope=READ_SCOPE+' festapp:forms:read';assert(!owner().allowedOperations.includes('forms.save'));
});
