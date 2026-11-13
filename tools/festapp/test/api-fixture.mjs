import assert from 'node:assert/strict';
import { request as nodeRequest, createServer as httpServer } from 'node:http';
import { generateKeyPairSync, randomBytes, createHash } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fixture, profile, reply } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { openRemoteStorage } from '../src/remote/storage.mjs';
import { createRemoteApp } from '../src/remote/server.mjs';
const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const secrets = { cookieKeys: ['a'.repeat(48), 'b'.repeat(48)], jwks: { keys: [{
    ...privateKey.export({ format: 'jwk' }), kid: 'fixture', use: 'sig', alg: 'RS256',
}] } };
const csrf = html => html.match(/name="csrf" value="([^"]+)"/)[1];
const rawProfile = () => { const { binding, ...p } = profile(); return p; };
const configuration = (issuer) => ({ schemaVersion: 2, issuer, profile: rawProfile(),
    clients: [{ id: 'chatgpt-fixture', name: 'ChatGPT fixture', redirectUris: [issuer + '/callback'] }],
});
export async function setup(t, { api = true, apiPolicy, makeMigration = false, auditObserver, profileValue = profile(), userId, proofProfile = 'bearer', global = false, native = false, tenant = false, pilot = false, fetchImpl, webCallback, publicClient = false, previewFetch, rateLimiter, canonical = false, genericClients = false, clientMetadataDocuments, metadataFetch } = {}) {
    const base = await fixture(t, { profileValue, ...(userId ? {userId} : {}), fetchImpl: (url, init) => global && url.pathname === '/second-activation.json'
        ? reply({ schemaVersion: 1, tenantId: 'second', generation: 1, backend: 'canonical' }) : url.pathname.startsWith('/functions/v1/preview-ticket-layout')
        ? (previewFetch?.(url,init) ?? reply({ presets: {}, fonts: {} })) : fetchImpl?.(url, init) });
    const root = await mkdtemp(join(tmpdir(), 'festapp-remote-'));
    const key = randomBytes(32);
    const storage = await openRemoteStorage(root, key);
    const server = httpServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => { await new Promise(resolve => server.close(resolve)); await storage.close(); await rm(root, { recursive: true, force: true }); });
    const issuer = `http://127.0.0.1:${server.address().port}`;
    const raw = configuration(issuer);
    const {binding: profileBinding,...configuredProfile}=profileValue;
    raw.profile=configuredProfile;
    if (webCallback) raw.clients[0].redirectUris = [webCallback];
    if (native) raw.clients[0] = { id: 'codex-fixture', name: 'Codex fixture', applicationType: 'native', redirectUris: ['http://127.0.0.1/callback'] };
    if (pilot) raw.clients = [raw.clients[0], { id: 'portable-fixture', name: 'Portable fixture', redirectUris: [issuer + '/callback/portable'], allowedScopes: [READ_SCOPE] }].map((c, i) => i ? c : { ...c, allowedScopes: [READ_SCOPE, 'festapp:orders:read'] });
    if (pilot) raw.regionalPortal = { name: 'vstupenky.online', platform: 'Festapp' };
    if (publicClient) { raw.clients[0].id = 'arbitrary-summary-client'; raw.clients[0].dataProfile = 'order-summary'; }
    if (genericClients) raw.clients = raw.clients.map((c, i) => ({ ...c, id: i ? 'browser-fixture' : 'desktop-fixture', name: i ? 'Browser application' : 'Desktop application' }));
    if (clientMetadataDocuments) raw.clientMetadataDocuments = clientMetadataDocuments;
    if (tenant) raw.tenantOrigin = 'https://tenant.fixture.test';
    if (global) {
        const second = { ...rawProfile(), tenantId: 'second', name: 'second', organizationId: 2,
            activationUrl: rawProfile().backendOrigin + '/second-activation.json',
            activationSha256: digest(JSON.stringify({ schemaVersion: 1, tenantId: 'second', generation: 1, backend: 'canonical' })) };
        second.canonicalProfileSha256 = canonicalBackendProfileSha256({ tenantId: second.tenantId,
            canonicalOrigin: second.backendOrigin, canonicalAnonKey: second.publicApiKey, canonicalOrganizationId: 2 });
        raw.contexts = [{ name: 'First environment', profile: raw.profile, tenantOrigin: 'https://first.fixture.test' },
            { name: 'Second environment', profile: second, tenantOrigin: 'https://second.fixture.test' }];
        delete raw.profile; delete raw.tenantOrigin;
    }
    if (api) {
        raw.schemaVersion = 3;
        raw.endpoints = [
            { endpointId: 'global-api', publicBase: 'https://api.festapp.net/integrations/v1', resource: 'https://api.festapp.net/integrations', issuer,
                brand: 'Festapp', profilePolicy: { type: 'selected' }, allowedClients: ['api-fixture'] },
            { endpointId: 'regional-api', publicBase: 'https://api.vstupenky.online/integrations/v1', resource: 'https://api.vstupenky.online/integrations', issuer,
                brand: 'vstupenky.online', profilePolicy: { type: 'fixed', profileBinding: profileValue.binding }, allowedClients: ['api-fixture'] },
        ];
        raw.clients = [{ ...raw.clients[0], id: 'api-fixture', transports: ['api'], resources: raw.endpoints.map(e => e.resource),
            proofProfile, tokenEndpointAuthMethod: 'none', allowedScopes: [READ_SCOPE, 'festapp:products:read', 'festapp:products:write', 'festapp:orders:read'],
            allowedOperations: ['context.inspect', 'access.inspect', 'products.list', 'products.save', 'orders.list'] },
            { ...raw.clients[0], transports: ['mcp'], resources: [issuer + '/mcp'] }];
    }
    if(makeMigration){
        const client=raw.clients[0];Object.assign(client,{id:'festapp-make',dataProfile:'order-summary',transports:['api','legacy-make'],resources:[raw.endpoints[1].resource,issuer+'/mcp'],redirectUris:['https://www.make.com/oauth/cb/app'],allowedScopes:[READ_SCOPE,'festapp:orders:read'],allowedOperations:['context.inspect','access.inspect','orders.report','orders.list','orders.inspect']});
        raw.endpoints.forEach(endpoint=>endpoint.allowedClients=['festapp-make']);
    }
    if (apiPolicy) raw.clients[0]={...raw.clients[0],...apiPolicy};
    const parsedConfig = parseRemoteConfig(raw);
    const config = canonical ? { ...parsedConfig, profile: { ...parsedConfig.profile, kind: 'canonical' } } : parsedConfig;
    const audit = [];
    const service = createRemoteApp(config, storage, { ...secrets, brokerSecret: 'b'.repeat(43), fetchImpl: base.owner.fetch, audit: r => {audit.push(r);auditObserver?.(r);}, rateLimiter, metadataFetch });
    server.on('request', service.app);
    const jar = new Map();
    const browser = async (path, body, extra = {}) => {
        const r = await fetch(new URL(path, issuer), { redirect: 'manual',
            method: body ? 'POST' : 'GET', body: body && new URLSearchParams(Object.entries(body).flatMap(([key,value]) => [value].flat().map(v => [key,String(v)]))),
            headers: { cookie: [...jar].map(([k, v]) => `${k}=${v}`).join('; '),
                ...(body ? { origin: issuer } : {}), ...extra } });
        for (const c of r.headers.getSetCookie()) {
            const [pair] = c.split(';'); const at = pair.indexOf('=');
            jar.set(pair.slice(0, at), pair.slice(at + 1));
        }
        return r;
    };
    return { ...base, root, key, storage, server, issuer, config, audit, browser, keyMaterial: secrets, clearBrowserCookies: () => jar.clear(), ...service };
}
export async function connect(f, { badVerifier = false, usePar = false, clientId = 'api-fixture', callbackUri = f.issuer + '/callback', scope = READ_SCOPE, unitId, occasionIds, create = false, handleFormPost, consentFields = {}, consentStatus = 303, resources = [f.config.endpoints?.[0]?.resource ?? f.config.resource] } = {}) {
    const verifier = randomBytes(32).toString('base64url');
    const params = new URLSearchParams({ client_id: clientId, response_type: 'code',
        redirect_uri: callbackUri, scope: `openid offline_access ${scope}`,
        code_challenge: createHash('sha256').update(verifier).digest('base64url'),
        code_challenge_method: 'S256', state: 'fixture-state' });
    for (const resource of resources) params.append('resource', resource);
    let authorize=params;
    if(usePar){
        params.set('prompt','consent');
        const response=await fetch(f.issuer+'/request',{method:'POST',body:params});
        assert.equal(response.status,201,await response.clone().text());
        const pushed=await response.json();
        f.lastPar=pushed.request_uri;
        authorize=new URLSearchParams({client_id:clientId,request_uri:pushed.request_uri});
    }
    let r = await f.browser('/auth?' + authorize);
    assert.equal(r.status, 303);
    const location = r.headers.get('location');
    r = await f.browser(location);
    assert.equal(r.status, 200);
    let html = await r.text();
    if (html.includes('/context')) {
        const contextUid = new URL(location, f.issuer).pathname.split('/').at(-1);
        r = await f.browser(`/connect/${contextUid}/context`, {csrf:csrf(html),context:f.config.profile.binding});
        assert.equal(r.status,303);
        r = await f.browser(r.headers.get('location'));
        html = await r.text();
    }
    const uid = new URL(location, f.issuer).pathname.split('/').at(-1);
    r = await f.browser(`/connect/${uid}/login`, { csrf: csrf(html), email: 'fixture@example.test', password: 'fixture-password' });
    assert.equal(r.status, 303);
    r = await f.browser(r.headers.get('location'));
    const consent = await r.text();
    assert.match(consent, /Povolit přístup/);
    assert.match(consent, /name="consentVersion" value="3"/);
    assert.doesNotMatch(consent, /type="checkbox" name="(?:permission|create)"/);
    assert.match(consent, /value="7"/);
    assert.doesNotMatch(consent, /value="8"/);
    r = await f.browser(`/connect/${uid}/consent`, { csrf: csrf(consent), consentVersion: '3', ...consentFields, ...(unitId ? { unit: String(unitId), ...(create ? { create: '1' } : {}) } : { occasion: occasionIds ?? '7' }) });
    assert.equal(r.status, consentStatus);
    if (consentStatus !== 303) return;
    let redirect = r.headers.get('location');
    const callbackTarget = new URL(callbackUri);
    const isCallback = value => { const u = new URL(value, f.issuer); return u.origin === callbackTarget.origin && u.pathname === callbackTarget.pathname; };
    for (let i = 0; i < 8 && !isCallback(redirect); i++) {
        r = await f.browser(redirect);
        if (handleFormPost && r.status === 200 && r.headers.get('content-type')?.includes('text/html'))
            r = await handleFormPost(r);
        redirect = r.headers.get('location');
        assert(redirect, `missing callback redirect, status ${r.status}: ${await r.text()}`);
    }
    const callback = new URL(redirect, f.issuer);
    assert.equal(callback.searchParams.get('state'), 'fixture-state');
    assert.equal(callback.searchParams.get('iss'), f.issuer);
    assert(callback.searchParams.get('code'), callback.href);
    const exchange = async (codeVerifier = verifier) => fetch(f.issuer + '/token', { method: 'POST', headers: f.tokenProof ? { DPoP: await f.tokenProof() } : {}, body: new URLSearchParams({
        client_id: clientId, grant_type: 'authorization_code', code: callback.searchParams.get('code'),
        redirect_uri: callbackUri, code_verifier: codeVerifier, resource: resources[0],
        ...(f.clientAssertion ? {client_assertion_type:'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',client_assertion:await f.clientAssertion()} : {}),
    }) });
    const response = await exchange(badVerifier ? 'wrong-verifier'.repeat(4) : verifier);
    assert.equal(response.status, badVerifier ? 400 : 200, await response.clone().text());
    return { callback, exchange, response, tokens: await response.json() };
}


export function httpRequest(url, {method='GET', headers={}, body} = {}) {
    return new Promise((resolve,reject)=> {
        const request=nodeRequest(url,{method,headers},response=> {
            const chunks=[];response.on('data',chunk=>chunks.push(chunk));response.on('end',()=>resolve(new Response([204,205,304].includes(response.statusCode)?null:Buffer.concat(chunks),{status:response.statusCode,headers:response.headers})));
        });request.on('error',reject);request.end(body);
    });
}
export async function apiRequest(f, tokens, operation = 'context.inspect', body = {}, endpointId = 'global-api', extra = {}) {
    const endpoint = f.config.endpoints.find(e => e.endpointId === endpointId);
    return httpRequest(f.issuer + '/integrations/v1/operations/' + operation, { method: 'POST',
        headers: { host: new URL(endpoint.publicBase).host, 'x-forwarded-host': new URL(endpoint.publicBase).host,
            'x-forwarded-proto': 'https', 'x-festapp-endpoint': endpointId,
            authorization: 'Bearer ' + tokens.access_token, 'content-type': 'application/json', ...extra }, body: typeof body === 'string' ? body : JSON.stringify(body) });
}
