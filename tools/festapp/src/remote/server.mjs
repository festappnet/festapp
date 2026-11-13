import { readFileSync } from 'node:fs';
import { connectionActive, connectionIssuable, connectionRefreshSeconds, connectionDeadline, consentDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { CONNECTION_DURATION_DAYS, MAX_CONNECTION_DURATION_DAYS, DAY_SECONDS } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { activeConnections, verifyConnectionChoice, installConnectionActivation } from './connection-choice.mjs';
import { createRateLimiter, clientIdentity } from './rate-limit.mjs';
import { MAKE_CLIENT_ID, MAKE_READ_OPERATIONS } from './make-contract.mjs';
import {PreviewArtifacts} from '../operations/preview.mjs';
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
import { contextConfig, remoteContexts, canonicalRemote, READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, verifyPermissions, clientAllowsScopes } from './config.mjs';
import { DOMAIN_SCOPES, clientPolicy, allowsMetadataFetch, allowsMetadataClient } from './client-policy.mjs';
import { DelegatedOwner, boundOwner, connectionBinding, connectionContext } from './delegation.mjs';
import { loginForm, consentForm, contextChoiceForm, contextManagementPage, publicDocument, serviceDocumentation, connectionsPage, page, oauthFailure } from './views.mjs';
import { makeStatus, validateMakePage, makeDocumentation } from './make-transport.mjs';

const nonce = () => randomBytes(32).toString('base64url');
const cookieName = 'festapp_mcp_management';

export function createRemoteApp(config, storage, { cookieKeys, jwks, brokerSecret, fetchImpl = fetch, audit = () => {}, rateLimiter = createRateLimiter(), metadataFetch = fetch } = {}) {
    check(cookieKeys?.length >= 2 && cookieKeys.every(k => typeof k === 'string' && k.length >= 32), 'INVALID_COOKIE_KEYS');
    check(jwks?.keys?.length > 0, 'INVALID_ISSUER_KEYS');
    // Account-switch form POSTs may redirect to a registered web callback.
    // Use protected exact HTTPS URLs, never an incoming redirect parameter.
    const webFormCallbacks = [...new Set(config.clients.filter(c => c.applicationType === 'web')
        .flatMap(c => c.redirectUris).map(value => new URL(value)).filter(u => u.protocol === 'https:')
        .map(u => u.href.replace(/;/g, '%3B').replace(/'/g, '%27')))].sort();
    const formAction = ["'self'", ...webFormCallbacks].join(' ');
    const binding = digest(JSON.stringify(config.contexts ? ['global-contexts', config.issuer] : [config.issuer, config.profile.binding]));
    const boundGrant = grant => { try { connectionContext(config, grant); return true; } catch { return false; } };
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
        fetch: metadataFetch,
        scopes: ['openid', 'offline_access', ...DOMAIN_SCOPES], responseTypes: ['code'],
        pkce: { required: () => true },
        features: {
            devInteractions: { enabled: false },
            registration: { enabled: false },
            clientIdMetadataDocument: { enabled: Boolean(config.clientMetadataDocuments), ack: 'draft-02',
                allowFetch: (_ctx, id) => allowsMetadataFetch(config, id),
                allowClient: (_ctx, client) => allowsMetadataClient(config, client) },
            revocation: { enabled: true },
            resourceIndicators: { enabled: true,
                defaultResource: () => config.resource,
                useGrantedResource: () => true,
                // Owns resource validation before consent and token issuance.
                // The provider invokes this for every indicator, including repeats.
                getResourceServerInfo: async (ctx, resource) => {
                    if (resource !== config.resource) throw new errors.InvalidTarget();
                    return { scope: (clientPolicy(config, ctx.oidc.client?.clientId)?.allowedScopes ?? DOMAIN_SCOPES).join(' '), audience: config.resource, accessTokenTTL: 300, accessTokenFormat: 'opaque' };
                },
            },
        },
        ttl: { AccessToken: 300, IdToken: 300, AuthorizationCode: 60, Interaction: 600, Grant: DAY_SECONDS * MAX_CONNECTION_DURATION_DAYS,
            RefreshToken: (ctx, token) => {
                const grant = storage.get('Delegation', token.grantId);
                if (!boundGrant(grant) || !(connectionActive(grant) || (ctx.oidc.params.grant_type === 'authorization_code' && connectionIssuable(grant))))
                    throw new errors.InvalidGrant('connection expired or revoked');
                return connectionRefreshSeconds(grant);
            }, Session: 3600 },
        issueRefreshToken: (ctx, client, source) => {
            if (!clientAllowsScopes(config, client.clientId, source.scope?.split(' ') ?? []))
                throw new errors.InvalidGrant('client scope policy changed; reconnect');
            const grant = storage.get('Delegation', source.grantId);
            return Boolean(boundGrant(grant) && grant?.clientId === client.clientId && (connectionActive(grant) || (ctx.oidc.params.grant_type === 'authorization_code' && connectionIssuable(grant))));
        },
        expiresWithSession: () => false,
        rotateRefreshToken: ctx => {
            // Narrowed policies invalidate older wider refresh credentials. Never
            // mint another credential with a retired scope from a stored grant.
            const source = ctx.oidc.entities.RefreshToken;
            if (!clientAllowsScopes(config, ctx.oidc.client.clientId, source.scope?.split(' ') ?? []))
                throw new errors.InvalidGrant('client scope policy changed; reconnect');
            const grant = storage.get('Delegation', source.grantId);
            if (!boundGrant(grant) || !connectionActive(grant) || grant.clientId !== ctx.oidc.client.clientId)
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
        renderError: async (ctx, out) => {
            ctx.type = 'html';
            ctx.body = oauthFailure(out.error);
        },
    });
    // Only a loopback-bound listener behind the configured trusted TLS proxy.
    // The outer host/proto check below rejects forged forwarded destinations.
    provider.proxy = canonicalRemote(config);
    installConnectionActivation(provider, storage, audit);
    provider.on('server_error', () => audit({ event: 'issuer_error' }));
    const app = express();
    app.disable('x-powered-by');
    // Keep the existing resource/device budget for supported selections.
    const form = express.urlencoded({ extended: false, limit: '8kb', parameterLimit: 110 + MCP_SCOPES.length });
    const active = new Map();
    const artifacts = new PreviewArtifacts();
    let totalActive = 0;
    const limit = (bucket, max) => {
        const at = bucket.indexOf(':');
        const type = bucket.slice(0, at);
        try { rateLimiter(type, bucket.slice(at + 1), max); }
        catch (error) { audit({ event: 'rate_limit', bucket: type, outcome: 'rejected' }); throw error; }
    };
    const limited = (req, res, error) => {
        res.set('Retry-After', String(error?.retryAfter ?? 60));
        audit({ event: 'rate_limit', route: req.path.startsWith('/tenant-') ? 'broker' : req.path.startsWith('/make/') ? 'make' : req.path === '/mcp' ? 'mcp' : 'issuer', outcome: 'rejected' });
        return (req.path === '/make/v1' || req.path.startsWith('/make/v1/'))
            ? res.status(429).json({ ok: false, error: { code: 'TEMPORARILY_LIMITED', message: 'TEMPORARILY_LIMITED', retryable: true } })
            : res.sendStatus(429);
    };
    app.use((req, res, next) => {
        const expected = new URL(config.issuer);
        const canonical = canonicalRemote(config);
        const loopback = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress);
        if (req.headers.host !== expected.host || !loopback ||
            (canonical && req.headers['x-forwarded-proto'] !== 'https')) return res.sendStatus(400);
        if ((req.path === '/mcp' || req.path.startsWith('/make/v1/')) && req.headers.origin && req.headers.origin !== config.issuer)
            return res.sendStatus(403);
        res.set({ 'Cache-Control': 'no-store', 'Referrer-Policy': 'same-origin',
            'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
            // Empty script-src denies scripts; oidc-provider adds only the exact
            // hash of its account-switch auto-submit script when it renders it.
            'Content-Security-Policy': `default-src 'none'; script-src; style-src 'unsafe-inline'; form-action ${formAction}; frame-ancestors 'none'; base-uri 'none'` });
        if (canonical) res.set('Strict-Transport-Security', 'max-age=31536000');
        if (req.method === 'GET' && req.path === '/healthz') return next();
        let ip;
        try { ip = clientIdentity(req, canonical); } catch { return res.sendStatus(400); }
        try { limit(`http:${ip}`, 240); next(); } catch (error) { limited(req, res, error); }
    });
    app.get(['/', '/docs'], (_req, res) => res.type('html').send(serviceDocumentation(config)));
    app.get('/support', (_req, res) => res.type('html').send(page('Festapp support',
        '<p>Provider: Michael Bujnovský, IČO 06455361. Contact <a href="mailto:info@festapp.net">info@festapp.net</a> for MCP connection support. Include the client and a safe error/request ID. Never send passwords, access tokens or customer data. Event and order questions belong to the selected organizer.</p><p><a href="/docs">Documentation</a> · <a href="/privacy">Privacy</a> · <a href="/terms">Terms</a></p>', 'en')));
    for (const language of ['en', 'cs']) for (const kind of ['privacy', 'terms']) {
        const source = readFileSync(new URL(`../../../../automation/release/legal/mcp-${kind}.${language}.md`, import.meta.url), 'utf8');
        app.get(language === 'en' ? `/${kind}` : `/cs/${kind}`, (_req, res) => res.type('html').send(publicDocument(source, language)));
    }
    app.get('/healthz', (_req, res) => res.json({ ok: true }));
    app.get('/make/v1', (_req, res) => res.json(makeDocumentation(config,
        new Operations({ root: storage.root, orderSummaryOnly: true, allowedOperations: MAKE_READ_OPERATIONS }).catalog)));
    const metadata = { resource_documentation: config.issuer + '/docs', resource_name: config.regionalPortal?.name ?? 'Festapp', resource: config.resource, authorization_servers: [config.issuer], scopes_supported: DOMAIN_SCOPES };
    for (const route of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'])
        app.get(route, (_req, res) => res.set('Access-Control-Allow-Origin', '*').json(metadata));
    app.get('/auth', (req, _res, next) => {
        // This issuer always requires explicit consent. Tell the provider before
        // scope validation, otherwise it discards requested offline_access.
        const url = new URL(req.url, config.issuer);
        if (!url.searchParams.has('prompt')) {
            url.searchParams.set('prompt', 'consent');
            req.url = url.pathname + url.search;
        }
        next();
    });
    // OAuth metadata can be discovered without assuming OIDC URL conventions.
    app.get('/.well-known/oauth-authorization-server', (req, res) => {
        req.url = '/.well-known/openid-configuration';
        return provider.callback()(req, res);
    });
    const csrfCheck = (req, record) => check(req.headers.origin === config.issuer &&
        typeof req.body?.csrf === 'string' && req.body.csrf === record.csrf, 'FORBIDDEN');
    const details = async req => {
        const d = await provider.interactionDetails(req, req.res);
        check(d.uid === req.params.uid && clientPolicy(config, d.params.client_id), 'FORBIDDEN');
        const requested = String(d.params.scope ?? '').split(' ');
        check(requested.includes(READ_SCOPE) && clientAllowsScopes(config, d.params.client_id, requested), 'FORBIDDEN');
        return d;
    };
    const flow = (uid) => storage.get('Connect', uid);
    const flowConfig = uid => contextConfig(config, flow(uid)?.profileBinding ?? (!config.contexts ? config.profile.binding : undefined));
    const loginOwner = (uid, selectedConfig) => {
        const selected = selectedConfig ?? flowConfig(uid);
        return boundOwner(selected, storage, connectionBinding(selected.profile, uid), { fetchImpl });
    };
    // Upgrade existing selected-event delegations once without widening them.
    for (const previousGrant of storage.values('Delegation')) {
        if (previousGrant.access || !previousGrant.occasions) continue;
        const { occasions, ...grant } = previousGrant;
        storage.putUntil('Delegation', grant.id, { ...grant, access: { type: 'occasions', occasionIds: occasions } }, grant.expiresAt);
    }
    const availableAccess = async (owner, backend) => operatorAccess(backend, owner.profile);
    const canRequestCreate = d => String(d.params.scope ?? '').split(' ').includes(CREATE_SCOPE);
    const completeConsent = async (req, res, d, f, selection) => {
        const selectedConfig = flowConfig(d.uid);
        const consentOwner = loginOwner(d.uid);
        const access = await consentOwner.authorized(async backend =>
            verifySelection(selection, await availableAccess(consentOwner, backend), canRequestCreate(d)));
        const permissions = verifyPermissions(f.permissions, String(d.params.scope ?? '').split(' '));
        const scopes = [READ_SCOPE, ...(canCreateWithAccess(access) ? [CREATE_SCOPE] : []), ...permissions].join(' ');
        check(clientAllowsScopes(config, d.params.client_id, scopes.split(' ')), 'FORBIDDEN');
        const choice = verifyConnectionChoice(f.connection, storage, f.userId, d.params.client_id, selectedConfig.profile.binding);
        const durationSeconds = choice.durationDays * DAY_SECONDS;
        const createdAt = Date.now();
        const expiresAt = consentDeadline(choice.durationDays, createdAt);
        const pendingExpiresAt = Math.min(d.exp * 1000, expiresAt);
        const grant = new provider.Grant({ accountId: f.userId, clientId: d.params.client_id, expiresIn: durationSeconds });
        grant.addOIDCScope(`openid offline_access ${scopes}`);
        grant.addResourceScope(config.resource, scopes);
        // A narrower consent is a completed decision, not an unanswered prompt.
        // Without recording rejected scopes the provider starts consent again.
        const approved = new Set(['openid', 'offline_access', ...scopes.split(' ')]);
        const rejected = String(d.params.scope ?? '').split(' ').filter(s => s && !approved.has(s));
        grant.rejectOIDCScope(rejected.join(' '));
        grant.rejectResourceScope(config.resource, rejected.filter(s => s !== 'openid' && s !== 'offline_access').join(' '));
        const grantId = await grant.save();
        const sessionBinding = connectionBinding(selectedConfig.profile, d.uid);
        storage.putUntil('Delegation', grantId, { id: grantId, userId: f.userId, clientId: d.params.client_id,
            profileBinding: selectedConfig.profile.binding, interactionId: d.uid, binding: sessionBinding,
            access, permissions, ...choice, createdAt, expiresAt, lifecycle: 'pending', pendingExpiresAt, revoked: false }, pendingExpiresAt);
        storage.putUntil('Binding', sessionBinding, { id: grantId }, pendingExpiresAt);
        await storage.backendStore.write(sessionBinding, await storage.backendStore.read(sessionBinding));
        if (f.request) storage.put('TenantResult', digest(f.request), { grantId, userId: f.userId, uid: d.uid, profileBinding: selectedConfig.profile.binding }, 600);
        storage.remove('Connect', d.uid);
        audit({ event: 'consent', connection: digest(grantId), client: d.params.client_id });
        return provider.interactionFinished(req, res, { login: { accountId: f.userId }, consent: { grantId } }, { mergeWithLastSubmission: false });
    };
    tenantConnections(app, { config, storage, brokerSecret, owner: loginOwner, audit });
    const tenantRedirect = tenantBridge(app, { config, storage, brokerSecret,
        owner: loginOwner, flowConfig, available: availableAccess, canRequestCreate, complete: completeConsent, details, provider });
    const renderConnect = async (req, res, error = '') => {
        const d = await details(req);
        let f = flow(d.uid);
        if (!f) { f = { csrf: nonce() }; storage.put('Connect', d.uid, f, 600); }
        if (config.contexts && !f.profileBinding) return res.type('html').send(contextChoiceForm({
            csrf: f.csrf, action: `/connect/${d.uid}/context`, contexts: config.contexts }));
        if (tenantRedirect) return tenantRedirect(res, d, f);
        const client = clientPolicy(config, d.params.client_id).name;
        if (!f.userId) return res.type('html').send(loginForm({ csrf: f.csrf, client,
            action: `/connect/${d.uid}/login`, consent: true, error }));
        const consentOwner = loginOwner(d.uid);
        const available = await consentOwner.authorized((backend, context) =>
            availableAccess(consentOwner, backend, context.userId));
        check(available.occasions.length > 0 || available.units.length > 0, 'FORBIDDEN');
        f.available = available;
        f.permissions = MCP_SCOPES.filter(s => String(d.params.scope ?? '').split(' ').includes(s));
        storage.put('Connect', d.uid, f, 600);
        return res.type('html').send(consentForm({ csrf: f.csrf, client,
            connections: activeConnections(storage, f.userId, d.params.client_id, config.profile.binding), action: `/connect/${d.uid}/consent`, occasions: available.occasions, units: available.units, selectedTenant: config.profile.tenantId }));
    };
    app.post('/connect/:uid/context', form, async (req, res) => {
        const d = await details(req), f = flow(d.uid);
        check(config.contexts && f && !f.profileBinding && !f.request, 'FORBIDDEN');
        csrfCheck(req, f);
        const selected = contextConfig(config, req.body.context);
        storage.put('Connect', d.uid, { ...f, profileBinding: selected.profile.binding }, 600);
        return res.redirect(303, `/connect/${d.uid}`);
    });
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
        const selection = req.body.unit ? { type: 'unit', unitId: Number(req.body.unit), canCreateOccasions: req.body.consentVersion === '3'
            ? canRequestCreate(d) && f.available?.units.some(u => u.id === Number(req.body.unit) && u.canCreateOccasions) === true
            : req.body.create === '1' }
            : { type: 'occasions', occasionIds: [req.body.occasion].flat().map(Number) };
        // The standalone select also submits in New device mode. Validate every
        // supplied ID before discarding that unused, owned selection.
        if (req.body.connectionId !== undefined) verifyConnectionChoice({ mode: 'replace', connectionId: req.body.connectionId },
            storage, f.userId, d.params.client_id, config.profile.binding);
        if (req.body.durationDays !== undefined) check(CONNECTION_DURATION_DAYS.some(days => String(days) === req.body.durationDays), 'FORBIDDEN');
        const connection = req.body.mode === undefined && req.body.durationDays === undefined ? undefined : { mode: req.body.mode ?? 'new',
            ...(req.body.durationDays !== undefined ? { durationDays: Number(req.body.durationDays) } : {}),
            ...(req.body.mode === 'replace' ? { connectionId: req.body.connectionId } : {}), name: req.body.name };
        // Functions follow the validated OAuth request, not another user role matrix.
        // Honor narrower approvals from pages already open before this UI change.
        const permissions = verifyPermissions(req.body.consentVersion === '3' ? f.permissions
            : req.body.permission === undefined ? [] : [req.body.permission].flat(), String(d.params.scope ?? '').split(' '));
        return completeConsent(req, res, d, { ...f, permissions, connection }, selection);
    });
    const manage = (req, res) => {
        const value = req.headers.cookie?.split(';').map(s => s.trim()).find(s => s.startsWith(cookieName + '='))?.slice(cookieName.length + 1);
        let f = value && storage.get('Management', value);
        if (!f) {
            const id = nonce();
            f = { id, csrf: nonce() }; storage.put('Management', id, f, 600);
            res.cookie(cookieName, id, { httpOnly: true, secure: canonicalRemote(config), sameSite: 'strict', path: '/connections', maxAge: 600000 });
        }
        return f;
    };
    app.get('/connections', (req, res) => {
        if (config.contexts) return res.type('html').send(contextManagementPage(config));
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res);
        return res.type('html').send(f.userId ? connectionsPage(f.csrf,
            storage.values('Delegation').filter(g => g.userId === f.userId && connectionActive(g))
                .map(g => ({ ...g, expiresAt: connectionDeadline(g), clientName: clientPolicy(config, g.clientId)?.name })))
            : loginForm({ csrf: f.csrf, action: '/connections/login' }));
    });
    app.post('/connections/login', form, async (req, res) => {
        if (config.contexts) return res.type('html').send(contextManagementPage(config));
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
            res.cookie(cookieName, id, { httpOnly: true, secure: canonicalRemote(config), sameSite: 'strict', path: '/connections', maxAge: 600000 });
            return res.redirect(303, '/connections');
        } finally { await owner.logout(); }
    });
    app.post('/connections/revoke', form, (req, res) => {
        if (config.contexts) return res.type('html').send(contextManagementPage(config));
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res); csrfCheck(req, f);
        const g = typeof req.body.grant === 'string' && storage.get('Delegation', req.body.grant);
        check(f.userId && g?.userId === f.userId, 'FORBIDDEN');
        storage.revoke(g.id);
        audit({ event: 'revoked', connection: digest(g.id) });
        return res.redirect(303, '/connections');
    });
    app.post('/connections/logout', form, (req, res) => {
        if (config.contexts) return res.type('html').send(contextManagementPage(config));
        if (config.tenantOrigin) return res.redirect(303, `${config.tenantOrigin}/settings/connections`);
        const f = manage(req, res); csrfCheck(req, f);
        storage.remove('Management', f.id); res.clearCookie(cookieName, { path: '/connections' });
        return res.redirect(303, '/connections');
    });
    const challenge = res => res.status(401).set('WWW-Authenticate',
        authChallenge(config, { error: 'invalid_token', description: 'Connect your Festapp account.' })).json({ error: 'invalid_token' });
    app.post(['/mcp', '/make/v1/operations/:operation'], express.json({ limit: '48kb' }), async (req, res) => {
        const make = req.path !== '/mcp';
        let token, owner;
        try {
            const h = req.headers.authorization;
            if (typeof h !== 'string' || !/^Bearer [A-Za-z0-9_-]{20,512}$/.test(h)) return challenge(res);
            token = await provider.AccessToken.find(h.slice(7));
            if (!token) return challenge(res);
            owner = new DelegatedOwner(config, storage, token, { fetchImpl });
            const grant = owner.current();
            if (!grant.clientConnectedAt) storage.putUntil('Delegation', token.grantId,
                { ...grant, clientConnectedAt: Date.now() }, grant.expiresAt);
        } catch { return challenge(res); }
        if (make) {
            if (token.clientId !== MAKE_CLIENT_ID || !owner.orderSummaryOnly ||
                !MAKE_READ_OPERATIONS.includes(req.params.operation))
                return res.status(403).json({ ok: false, error: { code: 'FORBIDDEN', message: 'FORBIDDEN', retryable: false } });
            owner.allowedOperations = owner.allowedOperations.filter(id => MAKE_READ_OPERATIONS.includes(id));
        }
        const operations = new Operations(owner, {artifacts});
        if (make || req.body?.method === 'tools/call') {
            const id = make ? req.params.operation : operations.operationIdForTool(req.body.params?.name);
            if (id && !owner.permitsOperation(id)) {
                const challenge = owner.challengeFor('INSUFFICIENT_SCOPE', id);
                if (challenge) return res.status(403).set('WWW-Authenticate', challenge).json({ error: 'insufficient_scope' });
                return res.status(403).json({ error: 'access_denied' });
            }
        }
        const count = active.get(token.grantId) ?? 0;
        if (count >= 2 || totalActive >= 16) return limited(req, res);
        try { limit(`grant:${token.grantId}`, 60); } catch (error) { return limited(req, res, error); }
        active.set(token.grantId, count + 1); totalActive++;
        let handler;
        const requestId = randomUUID();
        try {
            if (owner.allowedOperations.some(id => ['ticket_layouts.save','ticket_layouts.pending','ticket_layouts.resume'].includes(id))) await operations.prepare();
            const invoke = operations.invoke.bind(operations);
            operations.invoke = async (id, args) => {
                const result = await invoke(id, args);
                audit({ event: 'operation', requestId: result.meta.requestId,
                    connection: digest(token.grantId), actor: digest(token.accountId),
                    client: token.clientId, tenant: owner.profile.tenantId,
                    operation: id, outcome: result.ok ? 'ok' : result.error.code });
                return result;
            };
            if (make) {
                const result = await operations.invoke(req.params.operation, req.body);
                try { validateMakePage(req.params.operation, req.body, result, req.headers); }
                catch (error) {
                    const safe = safeError(error);
                    audit({ event: 'request', requestId: result.meta.requestId, status: makeStatus({ ok: false, error: safe }) });
                    return res.status(safe.code === 'PAGINATION_LIMIT_EXCEEDED' ? 409 : makeStatus({ ok: false, error: safe }))
                        .json({ ok: false, error: safe });
                }
                const status = makeStatus(result);
                if (status === 401) res.set('WWW-Authenticate', authChallenge(config, { error: 'invalid_token' }));
                if (status === 429) res.set('Retry-After', '60');
                audit({ event: 'request', requestId: result.meta.requestId, status });
                return res.status(status).json(result);
            }
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
    app.all('/make/v1/operations/:operation', (_req, res) => res.status(405)
        .json({ ok: false, error: { code: 'METHOD_NOT_ALLOWED', message: 'Use POST.', retryable: false } }));
    // Serialize token exchanges in this single-process deployment. In addition
    // to atomic adapter consumption, this keeps library code/refresh replay
    // revocation ordered before the next exchange can issue credentials.
    let tokenQueue = Promise.resolve(), tokenWaiting = 0;
    app.post('/token', async (req, res) => {
        if (tokenWaiting >= 8) return limited(req, res);
        tokenWaiting++;
        const previous = tokenQueue;
        let release;
        tokenQueue = new Promise(resolve => { release = resolve; });
        await previous;
        try { return await provider.callback()(req, res); }
        finally { tokenWaiting--; release(); }
    });
    app.use(provider.callback());
    app.use((error, req, res, _next) => {
        if (res.headersSent) return res.end();
        const safe = safeError(error);
        if (safe.code === 'TEMPORARILY_LIMITED') return limited(req, res, error);
        res.status(safe.code === 'FORBIDDEN' ? 403 : safe.code === 'TEMPORARILY_LIMITED' ? 429 : 400)
            .type('html').send(page('Požadavek se nezdařil', '<p>Připojení vypršelo, bylo odmítnuto nebo se službou nelze spojit. Spusťte připojení znovu.</p>'));
    });
    return { app, provider };
}
