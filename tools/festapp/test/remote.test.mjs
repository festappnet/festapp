import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer as httpServer } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { fixture, profile, actor, token as supabaseToken, reply } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { openRemoteStorage } from '../src/remote/storage.mjs';
import { createRemoteApp } from '../src/remote/server.mjs';
import { DelegatedOwner, boundOwner } from '../src/remote/delegation.mjs';
import { Operations } from '../src/operations/catalog.mjs';

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const secrets = { cookieKeys: ['a'.repeat(48), 'b'.repeat(48)], jwks: { keys: [{
    ...privateKey.export({ format: 'jwk' }), kid: 'fixture', use: 'sig', alg: 'RS256',
}] } };
const csrf = html => html.match(/name="csrf" value="([^"]+)"/)[1];
const rawProfile = () => { const { binding, ...p } = profile(); return p; };
const configuration = (issuer) => ({ schemaVersion: 1, issuer, profile: rawProfile(),
    clients: [{ id: 'chatgpt-fixture', name: 'ChatGPT fixture', redirectUris: [issuer + '/callback'] }],
    operators: [{ userId: actor, occasions: [7] }],
});
async function setup(t, { native = false } = {}) {
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
    const config = parseRemoteConfig(raw);
    const audit = [];
    const service = createRemoteApp(config, storage, { ...secrets, fetchImpl: base.owner.fetch, audit: r => audit.push(r) });
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
async function connect(f, { badVerifier = false, clientId = 'chatgpt-fixture', callbackUri = f.issuer + '/callback' } = {}) {
    const verifier = randomBytes(32).toString('base64url');
    const params = new URLSearchParams({ client_id: clientId, response_type: 'code',
        redirect_uri: callbackUri, scope: `openid offline_access ${READ_SCOPE}`,
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
    r = await f.browser(`/connect/${uid}/consent`, { csrf: csrf(consent), occasion: '7' });
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
    assert.equal(flow.occasions.join(','), '7');
    assert(!JSON.stringify(f.audit).includes('fixture-password'));
});

test('real OAuth code exchange and SDK HTTP reads, rotating refresh and browser revocation', async t => {
    const f = await setup(t);
    const { tokens, exchange } = await connect(f);
    assert.equal(tokens.token_type, 'Bearer');
    assert(tokens.refresh_token);
    assert.notEqual(tokens.access_token, supabaseToken);
    const client = new Client({ name: 'remote-fixture', version: '1' });
    t.after(() => client.close());
    await client.connect(new StreamableHTTPClientTransport(new URL(f.config.resource), {
        requestInit: { headers: { authorization: `Bearer ${tokens.access_token}` } },
    }));
    const list = await client.listTools();
    assert.deepEqual(list.tools.map(t => t.name), ['festapp_context_inspect', 'festapp_ticket_layouts_inspect']);
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
        profileBinding: f.config.profile.binding, occasions: [7], expiresAt: Date.now() + 60000, revoked: false };
    f.storage.put('Delegation', grant.id, grant);
    const token = { grantId: grant.id, accountId: actor, clientId: grant.clientId, aud: f.config.resource,
        exp: Math.floor(Date.now() / 1000) + 300, scope: READ_SCOPE };
    for (const bad of [{ aud: 'https://wrong.example/mcp' }, { scope: 'openid' },
        { accountId: '00000000-0000-4000-8000-000000000002' }, { clientId: 'other-client' }, { exp: 1 }])
        assert.throws(() => new DelegatedOwner(f.config, f.storage, { ...token, ...bad }), /FORBIDDEN/);
    const owner = new DelegatedOwner(f.config, f.storage, token, { fetchImpl: f.owner.fetch });
    const ops = new Operations(owner);
    assert.deepEqual(ops.catalog.map(d => d.id), ['context.inspect', 'ticket_layouts.inspect']);
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
    const config = { ...f.config, operators: [...f.config.operators, { userId: otherActor, occasions: [7] }] };
    const owners = [];
    for (const [userId, upstream] of [[actor, f.owner.fetch], [otherActor, other.owner.fetch]]) {
        const binding = `actor-${userId}`;
        await boundOwner(config, f.storage, binding, { fetchImpl: upstream }).login('fixture@example.test', 'fixture-password');
        const id = `grant-${userId}`;
        f.storage.put('Delegation', id, { id, userId, clientId: 'chatgpt-fixture', binding,
            profileBinding: config.profile.binding, occasions: [7], expiresAt: Date.now() + 60000, revoked: false });
        owners.push(new DelegatedOwner(config, f.storage, { grantId: id, accountId: userId,
            clientId: 'chatgpt-fixture', aud: config.resource, scope: READ_SCOPE, exp: Date.now() / 1000 + 300 }, { fetchImpl: upstream }));
    }
    const results = await Promise.all(owners.map(o => new Operations(o).invoke('context.inspect', {})));
    assert.deepEqual(results.map(r => r.data.userId), [actor, otherActor]);
    f.storage.revoke(`grant-${actor}`);
    assert.equal((await new Operations(owners[1]).invoke('context.inspect', {})).data.userId, otherActor);
});
