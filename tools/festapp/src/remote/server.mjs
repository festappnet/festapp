import express from 'express';
import { tenantConnections } from './management.mjs';
import { tenantBridge } from './tenant-bridge.mjs';
import { Provider, errors } from 'oidc-provider';
import { randomBytes, randomUUID } from 'node:crypto';
import { createMcpHandler } from '@modelcontextprotocol/server';
import { toNodeHandler } from '@modelcontextprotocol/node';
import { Operations } from '../operations/catalog.mjs';
import { createServer } from '../mcp/server.mjs';
import { authChallenge } from '../mcp/protocol.mjs';
import { check, safeError } from '../errors.mjs';
import { digest } from '../context/profile.mjs';
import { operatorAccess, verifySelection, canCreateWithAccess } from '../operations/access.mjs';
import { READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, verifyPermissions, clientAllowsScopes } from './config.mjs';
import { DelegatedOwner, boundOwner, connectionBinding } from './delegation.mjs';
import { loginForm, consentForm, connectionsPage, page } from './views.mjs';

const nonce = () => randomBytes(32).toString('base64url');
const cookieName = 'festapp_mcp_management';

export function createRemoteApp(config, storage, { cookieKeys, jwks, brokerSecret, fetchImpl = fetch, audit = () => {} } = {}) {
    check(cookieKeys?.length >= 2 && cookieKeys.every(k => typeof k === 'string' && k.length >= 32), 'INVALID_COOKIE_KEYS');
    check(jwks?.keys?.length > 0, 'INVALID_ISSUER_KEYS');
    const binding = digest(JSON.stringify([config.issuer, config.profile.binding]));
    const previous = storage.get('Metadata', 'deployment');
    check(!previous || previous.binding === binding, 'REMOTE_STORAGE_TARGET_MISMATCH');
    storage.put('Metadata', 'deployment', { binding }, 86400 * 3650);
    const provider = new Provider(config.issuer, {
        adapter: model => storage.adapter(model),
        clients: config.clients.map(c => ({ client_id: c.id, client_name: c.name,
            application_type: c.applicationType,
            ...(c.allowedScopes ? { scope: ['openid', 'offline_access', ...c.allowedScopes].join(' ') } : {}),
            redirect_uris: c.redirectUris, response_types: ['code'],
            grant_types: ['authorization_code', 'refresh_token'], token_endpoint_auth_method: 'none', })),
        cookies: { keys: cookieKeys }, jwks,
        scopes: ['openid', 'offline_access', READ_SCOPE, CREATE_SCOPE, ...MCP_SCOPES], responseTypes: ['code'],
        pkce: { required: () => true },
        features: {
            devInteractions: { enabled: false },
            registration: { enabled: false },
            revocation: { enabled: true },
            resourceIndicators: { enabled: true,
                defaultResource: () => config.resource,
                useGrantedResource: () => true,
                getResourceServerInfo: async (ctx, resource) => {
                    if (resource !== config.resource) throw new errors.InvalidTarget();
                    return { scope: (config.clients.find(c => c.id === ctx.oidc.client?.clientId)?.allowedScopes ?? [READ_SCOPE, CREATE_SCOPE, ...MCP_SCOPES]).join(' '), audience: config.resource, accessTokenTTL: 300, accessTokenFormat: 'opaque' };
                },
            },
        },
        ttl: { AccessToken: 300, IdToken: 300, AuthorizationCode: 60, Interaction: 600, Grant: 86400 * 7,
            RefreshToken: 86400 * 7, Session: 3600 },
        issueRefreshToken: (_ctx, client, source) => {
            if (!clientAllowsScopes(config, client.clientId, source.scope?.split(' ') ?? []))
                throw new errors.InvalidGrant('client scope policy changed; reconnect');
            const grant = storage.get('Delegation', source.grantId);
            return Boolean(grant && !grant.revoked && grant.clientId === client.clientId && grant.expiresAt > Date.now());
        },
        expiresWithSession: () => false,
        rotateRefreshToken: ctx => {
            // Narrowed policies invalidate older wider refresh credentials. Never
            // mint another credential with a retired scope from a stored grant.
            const source = ctx.oidc.entities.RefreshToken;
            if (!clientAllowsScopes(config, ctx.oidc.client.clientId, source.scope?.split(' ') ?? []))
                throw new errors.InvalidGrant('client scope policy changed; reconnect');
            const grant = storage.get('Delegation', source.grantId);
            if (!grant || grant.revoked || grant.clientId !== ctx.oidc.client.clientId || grant.expiresAt <= Date.now())
                throw new errors.InvalidGrant('connection expired or revoked');
            return true;
        },
        // A new connection always requires explicit consent, never a global
        // grant inferred from an issuer browser session.
        loadExistingGrant: async ctx => {
            const id = ctx.oidc.result?.consent?.grantId;
            return id ? provider.Grant.find(id) : undefined;
        },
        interactions: { url: (_ctx, interaction) => `/connect/${interaction.uid}` },
        findAccount: async (_ctx, id) => ({ accountId: id, claims: async () => ({ sub: id }) }),
        renderError: async (ctx) => {
            ctx.type = 'html';
            ctx.body = page('Připojení se nezdařilo', '<p>Požadavek není platný nebo vypršel. Spusť připojení znovu v aplikaci.</p>');
        },
    });
    // Only a loopback-bound listener behind the configured trusted TLS proxy.
    // The outer host/proto check below rejects forged forwarded destinations.
    provider.proxy = config.profile.kind === 'canonical';
    provider.on('server_error', () => audit({ event: 'issuer_error' }));
    const app = express();
    app.disable('x-powered-by');
    const form = express.urlencoded({ extended: false, limit: '8kb', parameterLimit: 110 });
    const active = new Map();
    let totalActive = 0;
    const limit = (bucket, max) => {
        const key = digest(bucket);
        const old = storage.get('Rate', key) ?? { n: 0 };
        check(old.n < max, 'TEMPORARILY_LIMITED');
        storage.put('Rate', key, { n: old.n + 1 }, old.expires ? (old.expires - Date.now()) / 1000 : 60);
        if (!old.expires) storage.put('Rate', key, { n: 1, expires: Date.now() + 60000 }, 60);
    };
    app.use((req, res, next) => {
        const expected = new URL(config.issuer);
        const canonical = config.profile.kind === 'canonical';
        const loopback = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
        if (req.headers.host !== expected.host || !loopback ||
            (canonical && req.headers['x-forwarded-proto'] !== 'https')) return res.sendStatus(400);
        if (req.path === '/mcp' && req.headers.origin && req.headers.origin !== config.issuer)
            return res.sendStatus(403);
        res.set({ 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
            'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
            'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'" });
        if (canonical) res.set('Strict-Transport-Security', 'max-age=31536000');
        try { limit(`http:${req.socket.remoteAddress}`, 240); next(); } catch { res.sendStatus(429); }
    });
    app.get('/healthz', (_req, res) => res.json({ ok: true }));
    const metadata = { resource: config.resource, authorization_servers: [config.issuer], scopes_supported: [READ_SCOPE, CREATE_SCOPE, ...MCP_SCOPES] };
    for (const route of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'])
        app.get(route, (_req, res) => res.set('Access-Control-Allow-Origin', '*').json(metadata));
    // OAuth metadata can be discovered without assuming OIDC URL conventions.
    app.get('/.well-known/oauth-authorization-server', (req, res) => {
        req.url = '/.well-known/openid-configuration';
        return provider.callback()(req, res);
    });
    const csrfCheck = (req, record) => check(req.headers.origin === config.issuer &&
        typeof req.body?.csrf === 'string' && req.body.csrf === record.csrf, 'FORBIDDEN');
    const details = async req => {
        const d = await provider.interactionDetails(req, req.res);
        check(d.uid === req.params.uid && config.clients.some(c => c.id === d.params.client_id), 'FORBIDDEN');
        check(d.params.resource === undefined || d.params.resource === config.resource, 'FORBIDDEN');
        check(String(d.params.scope ?? '').split(' ').includes(READ_SCOPE), 'FORBIDDEN');
        return d;
    };
    const flow = (uid) => storage.get('Connect', uid);
    const loginOwner = uid => boundOwner(config, storage, connectionBinding(config.profile, uid), { fetchImpl });
    // Upgrade existing selected-event delegations once without widening them.
    for (const previousGrant of storage.values('Delegation')) {
        if (previousGrant.access || !previousGrant.occasions) continue;
        const { occasions, ...grant } = previousGrant;
        storage.put('Delegation', grant.id, { ...grant, access: { type: 'occasions', occasionIds: occasions } },
            Math.max(1, (grant.expiresAt - Date.now()) / 1000));
    }
    const availableAccess = async (_owner, backend) => operatorAccess(backend, config.profile);
    const canRequestCreate = d => String(d.params.scope ?? '').split(' ').includes(CREATE_SCOPE);
    const completeConsent = async (req, res, d, f, selection) => {
        const access = await loginOwner(d.uid).authorized(async backend =>
            verifySelection(selection, await availableAccess(null, backend), canRequestCreate(d)));
        const permissions = verifyPermissions(f.permissions, String(d.params.scope ?? '').split(' '));
        const scopes = [READ_SCOPE, ...(canCreateWithAccess(access) ? [CREATE_SCOPE] : []), ...permissions].join(' ');
        check(clientAllowsScopes(config, d.params.client_id, scopes.split(' ')), 'FORBIDDEN');
        const grant = new provider.Grant({ accountId: f.userId, clientId: d.params.client_id });
        grant.addOIDCScope(`openid offline_access ${scopes}`);
        grant.addResourceScope(config.resource, scopes);
        const grantId = await grant.save();
        const sessionBinding = connectionBinding(config.profile, d.uid);
        storage.put('Delegation', grantId, { id: grantId, userId: f.userId, clientId: d.params.client_id,
            profileBinding: config.profile.binding, binding: sessionBinding,
            access, permissions, expiresAt: Date.now() + 86400 * 7000, revoked: false }, 86400 * 7);
        storage.put('Binding', sessionBinding, { id: grantId }, 86400 * 8);
        await storage.backendStore.write(sessionBinding, await storage.backendStore.read(sessionBinding));
        if (f.request) storage.put('TenantResult', digest(f.request), { grantId, userId: f.userId, uid: d.uid }, 600);
        storage.remove('Connect', d.uid);
        audit({ event: 'consent', connection: digest(grantId), client: d.params.client_id });
        return provider.interactionFinished(req, res, { login: { accountId: f.userId }, consent: { grantId } }, { mergeWithLastSubmission: false });
    };
    tenantConnections(app, { config, storage, brokerSecret, owner: loginOwner, audit });
    const tenantRedirect = tenantBridge(app, { config, storage, brokerSecret,
        owner: loginOwner, available: availableAccess, canRequestCreate, complete: completeConsent, details, provider });
    const renderConnect = async (req, res, error = '') => {
        const d = await details(req);
        let f = flow(d.uid);
        if (!f) { f = { csrf: nonce() }; storage.put('Connect', d.uid, f, 600); }
        if (tenantRedirect) return tenantRedirect(res, d, f);
        const client = config.clients.find(c => c.id === d.params.client_id).name;
        if (!f.userId) return res.type('html').send(loginForm({ csrf: f.csrf, client,
            action: `/connect/${d.uid}/login`, consent: true, error }));
        const consentOwner = loginOwner(d.uid);
        const available = await consentOwner.authorized((backend, context) =>
            availableAccess(consentOwner, backend, context.userId));
        check(available.occasions.length > 0 || available.units.length > 0, 'FORBIDDEN');
        f.available = available;
        storage.put('Connect', d.uid, f, 600);
        return res.type('html').send(consentForm({ csrf: f.csrf, client,
            action: `/connect/${d.uid}/consent`, occasions: available.occasions, units: available.units, canRequestCreate: canRequestCreate(d), selectedTenant: config.profile.tenantId }));
    };
    app.get('/connect/:uid', (req, res) => renderConnect(req, res));
    app.post('/connect/:uid/login', form, async (req, res) => {
        check(!tenantRedirect, 'FORBIDDEN');
        const d = await details(req), f = flow(d.uid);
        check(f, 'FORBIDDEN'); csrfCheck(req, f);
        if (req.body.cancel) return provider.interactionFinished(req, res, { error: 'access_denied' }, { mergeWithLastSubmission: false });
        limit(`login:${d.uid}`, 5);
        try {
            check(typeof req.body.email === 'string' && typeof req.body.password === 'string', 'INVALID_INPUT');
            const owner = loginOwner(d.uid);
            const { userId } = await owner.login(req.body.email, req.body.password);
            storage.put('Connect', d.uid, { csrf: nonce(), userId }, 600);
        } catch (e) {
            const message = e.code === 'MFA_REQUIRED'
                ? 'Tento účet vyžaduje vícefaktorové ověření, které toto pilotní připojení zatím nepodporuje.'
                : 'Přihlášení se nezdařilo nebo účet nemá přístup k tomuto připojení.';
            return renderConnect(req, res, message);
        }
        res.redirect(303, `/connect/${d.uid}`);
    });
    app.post('/connect/:uid/consent', form, async (req, res) => {
        check(!tenantRedirect, 'FORBIDDEN');
        const d = await details(req), f = flow(d.uid);
        check(f?.userId, 'FORBIDDEN'); csrfCheck(req, f);
        if (req.body.cancel) {
            await loginOwner(d.uid).logout(); storage.remove('Connect', d.uid);
            return provider.interactionFinished(req, res, { error: 'access_denied' }, { mergeWithLastSubmission: false });
        }
        const selection = req.body.unit ? { type: 'unit', unitId: Number(req.body.unit), canCreateOccasions: req.body.create === '1' }
            : { type: 'occasions', occasionIds: [req.body.occasion].flat().map(Number) };
        return completeConsent(req, res, d, f, selection);
    });
    const manage = (req, res) => {
        const value = req.headers.cookie?.split(';').map(s => s.trim()).find(s => s.startsWith(cookieName + '='))?.slice(cookieName.length + 1);
        let f = value && storage.get('Management', value);
        if (!f) {
            const id = nonce();
            f = { id, csrf: nonce() }; storage.put('Management', id, f, 600);
            res.cookie(cookieName, id, { httpOnly: true, secure: config.profile.kind === 'canonical', sameSite: 'strict', path: '/connections', maxAge: 600000 });
        }
        return f;
    };
    app.get('/connections', (req, res) => {
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res);
        return res.type('html').send(f.userId ? connectionsPage(f.csrf,
            storage.values('Delegation').filter(g => g.userId === f.userId && !g.revoked && g.expiresAt > Date.now()), config.clients)
            : loginForm({ csrf: f.csrf, action: '/connections/login' }));
    });
    app.post('/connections/login', form, async (req, res) => {
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res); csrfCheck(req, f); limit(`manage:${f.id}`, 5);
        const owner = loginOwner(f.id);
        try {
            const { userId } = await owner.login(req.body.email, req.body.password);
            // Rotate the cookie after authentication; no downstream credential is
            // needed for own-connection revocation and none is retained here.
            const id = nonce();
            storage.remove('Management', f.id);
            storage.put('Management', id, { id, csrf: nonce(), userId }, 600);
            res.cookie(cookieName, id, { httpOnly: true, secure: config.profile.kind === 'canonical', sameSite: 'strict', path: '/connections', maxAge: 600000 });
            return res.redirect(303, '/connections');
        } finally { await owner.logout(); }
    });
    app.post('/connections/revoke', form, (req, res) => {
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res); csrfCheck(req, f);
        const g = typeof req.body.grant === 'string' && storage.get('Delegation', req.body.grant);
        check(f.userId && g?.userId === f.userId, 'FORBIDDEN');
        storage.revoke(g.id);
        audit({ event: 'revoked', connection: digest(g.id) });
        return res.redirect(303, '/connections');
    });
    app.post('/connections/logout', form, (req, res) => {
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res); csrfCheck(req, f);
        storage.remove('Management', f.id); res.clearCookie(cookieName, { path: '/connections' });
        return res.redirect(303, '/connections');
    });
    const challenge = res => res.status(401).set('WWW-Authenticate',
        authChallenge(config, { error: 'invalid_token', description: 'Connect your Festapp account.' })).json({ error: 'invalid_token' });
    app.post('/mcp', express.json({ limit: '48kb' }), async (req, res) => {
        let token, owner;
        try {
            const h = req.headers.authorization;
            if (typeof h !== 'string' || !/^Bearer [A-Za-z0-9_-]{20,512}$/.test(h)) return challenge(res);
            token = await provider.AccessToken.find(h.slice(7));
            if (!token) return challenge(res);
            owner = new DelegatedOwner(config, storage, token, { fetchImpl });
            const grant = owner.current();
            if (!grant.clientConnectedAt) storage.put('Delegation', token.grantId,
                { ...grant, clientConnectedAt: Date.now() }, Math.max(1, (grant.expiresAt - Date.now()) / 1000));
        } catch { return challenge(res); }
        const operations = new Operations(owner);
        if (req.body?.method === 'tools/call') {
            const id = operations.operationIdForTool(req.body.params?.name);
            if (id && !owner.permitsOperation(id)) {
                const challenge = owner.challengeFor('INSUFFICIENT_SCOPE', id);
                if (challenge) return res.status(403).set('WWW-Authenticate', challenge).json({ error: 'insufficient_scope' });
                return res.status(403).json({ error: 'access_denied' });
            }
        }
        const count = active.get(token.grantId) ?? 0;
        if (count >= 2 || totalActive >= 16) return res.sendStatus(429);
        try { limit(`grant:${token.grantId}`, 60); } catch { return res.sendStatus(429); }
        active.set(token.grantId, count + 1); totalActive++;
        let handler;
        const requestId = randomUUID();
        try {
            const invoke = operations.invoke.bind(operations);
            operations.invoke = async (id, args) => {
                const result = await invoke(id, args);
                audit({ event: 'operation', requestId: result.meta.requestId,
                    connection: digest(token.grantId), actor: digest(token.accountId),
                    client: token.clientId, tenant: config.profile.tenantId,
                    operation: id, outcome: result.ok ? 'ok' : result.error.code });
                return result;
            };
            // The SDK owns modern per-request serving and the stateless legacy
            // boundary. Both use this same authenticated domain catalog.
            handler = createMcpHandler(() => createServer(operations));
            await toNodeHandler(handler)(req, res, req.body);
            audit({ event: 'request', requestId, connection: digest(token.grantId), status: res.statusCode });
        } finally {
            active.set(token.grantId, (active.get(token.grantId) ?? 1) - 1); totalActive--;
            if (!active.get(token.grantId)) active.delete(token.grantId);
            await handler?.close();
        }
    });
    app.all('/mcp', (_req, res) => res.sendStatus(405));
    // Serialize token exchanges in this single-process deployment. In addition
    // to atomic adapter consumption, this keeps library code/refresh replay
    // revocation ordered before the next exchange can issue credentials.
    let tokenQueue = Promise.resolve(), tokenWaiting = 0;
    app.post('/token', async (req, res) => {
        if (tokenWaiting >= 8) return res.sendStatus(429);
        tokenWaiting++;
        const previous = tokenQueue;
        let release;
        tokenQueue = new Promise(resolve => { release = resolve; });
        await previous;
        try { return await provider.callback()(req, res); }
        finally { tokenWaiting--; release(); }
    });
    app.use(provider.callback());
    app.use((error, _req, res, _next) => {
        if (res.headersSent) return res.end();
        const safe = safeError(error);
        res.status(safe.code === 'FORBIDDEN' ? 403 : safe.code === 'TEMPORARILY_LIMITED' ? 429 : 400)
            .type('html').send(page('Požadavek se nezdařil', '<p>Připojení vypršelo, bylo odmítnuto nebo se službou nelze spojit. Spusť připojení znovu.</p>'));
    });
    return { app, provider };
}
