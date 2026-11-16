import {createWebhookWorker} from './webhook-worker.mjs';
import { createHostedRunner } from './hosted-runner.mjs';
import { resourceEndpoint, clientForResource, grantEndpoint, ingressEndpoint, API_PREFIX } from './endpoints.mjs';
import { installApi, sendProblem } from './api-transport.mjs';
import { readFileSync } from 'node:fs';
import { connectionActive, connectionIssuable, connectionRefreshSeconds, connectionDeadline, consentDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { CONNECTION_DURATION_DAYS, MAX_CONNECTION_DURATION_DAYS, DAY_SECONDS } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { activeConnections, verifyConnectionChoice, installConnectionActivation } from './connection-choice.mjs';
import { createRateLimiter, clientIdentity } from './rate-limit.mjs';
import { MAKE_CLIENT_ID, MAKE_READ_OPERATIONS } from './make-contract.mjs';
import express from 'express';
import { tenantConnections } from './management.mjs';
import { tenantBridge } from './tenant-bridge.mjs';
import { Provider, errors } from 'oidc-provider';
import { randomBytes, randomUUID } from 'node:crypto';
import { createMcpHandler } from '@modelcontextprotocol/server';
import { toNodeHandler } from '@modelcontextprotocol/node';
import { Operations } from '../operations/catalog.mjs';
import { createServer } from '../mcp/server.mjs';
import { REFRESH_REPLAY_LIMITS } from './storage.mjs';
import { authChallenge } from '../mcp/protocol.mjs';
import { check, safeError } from '../errors.mjs';
import { digest } from '../context/profile.mjs';
import { operatorAccess, verifySelection, canCreateWithAccess } from '../operations/access.mjs';
import { contextConfig, remoteContexts, canonicalRemote, READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, verifyPermissions, clientAllowsScopes } from './config.mjs';
import { DOMAIN_SCOPES, clientPolicy, allowsMetadataFetch, allowsMetadataClient } from './client-policy.mjs';
import { MCP_CONSENT_MODES, permissionsForConsent } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
import { boundOwner, connectionBinding, connectionContext } from './delegation.mjs';
import { loginForm, consentForm, contextChoiceForm, contextManagementPage, publicDocument, serviceDocumentation, connectionsPage, page, oauthFailure } from './views.mjs';
import { makeStatus, validateMakePage, makeDocumentation } from './make-transport.mjs';

const nonce = () => randomBytes(32).toString('base64url');
const cookieName = 'festapp_mcp_management';

export function createRemoteApp(config, storage, { cookieKeys, jwks, brokerSecret, fetchImpl = fetch, audit = () => {}, rateLimiter = createRateLimiter(), metadataFetch = fetch } = {}) {
    check(cookieKeys?.length >= 2 && cookieKeys.every(k => typeof k === 'string' && k.length >= 32), 'INVALID_COOKIE_KEYS');
    check(jwks?.keys?.length > 0, 'INVALID_ISSUER_KEYS');
    // Browsers enforce form-action across redirects too: context selection
    // reaches first-party consent, and account switching reaches the callback.
    // Derive destinations only from protected configuration, never request data.
    // Native registrations deliberately permit an ephemeral loopback port.
    const formDestinations = [...new Set([
        ...remoteContexts(config).flatMap(c => c.tenantOrigin ? [new URL('/settings/mcp-connect', c.tenantOrigin).href] : []),
        ...config.clients.flatMap(c => c.redirectUris.map(value => {
            const u = new URL(value);
            return c.applicationType === 'native' ? `${u.protocol}//${u.hostname}:*${u.pathname}` : u.href;
        })),
    ].map(value => value.replace(/;/g, '%3B').replace(/'/g, '%27')))].sort();
    const formAction = ["'self'", ...formDestinations].join(' ');
    const binding = digest(JSON.stringify(config.contexts ? ['global-contexts', config.issuer] : [config.issuer, config.profile.binding]));
    // During the bounded Make cutover, one registered client ID may retain its
    // original MCP grants alongside newly consented regional API grants. Only
    // a stored original-resource source may use the legacy missing-resource flow.
    const legacyMakeSource = ctx => {
        const client=clientPolicy(config,ctx.oidc.client?.clientId);
        const source=ctx.oidc.entities.RefreshToken??ctx.oidc.entities.AuthorizationCode;
        const grant=source&&storage.get('Delegation',source.grantId);
        return client?.id===MAKE_CLIENT_ID&&client.transports?.includes('legacy-make')&&grant&&grantEndpoint(config,grant).endpointId==='mcp';
    };
    const boundGrant = grant => { try { connectionContext(config, grant); grantEndpoint(config, grant); return true; } catch { return false; } };
    const previous = storage.get('Metadata', 'deployment');
    check(!previous || previous.binding === binding, 'REMOTE_STORAGE_TARGET_MISMATCH');
    storage.put('Metadata', 'deployment', { binding }, 86400 * 3650);
    const provider = new Provider(config.issuer, {
        adapter: model => storage.adapter(model),
        clients: config.clients.map(c => ({ client_id: c.id, client_name: c.name,
            application_type: c.applicationType,
            ...(c.allowedScopes ? { scope: ['openid', 'offline_access', ...c.allowedScopes].join(' ') } : {}),
            redirect_uris: c.redirectUris, response_types: ['code'],
            grant_types: ['authorization_code', 'refresh_token'], token_endpoint_auth_method: c.tokenEndpointAuthMethod ?? 'none',
            ...(c.jwks ? { jwks: c.jwks } : {}),
            dpop_bound_access_tokens: c.proofProfile === 'dpop',
            require_pushed_authorization_requests: c.requirePar === true, })),
        cookies: { keys: cookieKeys }, jwks,
        fetch: metadataFetch,
        scopes: ['openid', 'offline_access', ...DOMAIN_SCOPES], responseTypes: ['code'],
        pkce: { required: () => true },
        features: {
            devInteractions: { enabled: false },
            registration: { enabled: false },
            clientCredentials: { enabled: false },
            dPoP: { enabled: config.clients.some(c => c.proofProfile === 'dpop'), requireNonce: () => false },
            pushedAuthorizationRequests: { enabled: config.clients.some(c => c.requirePar) },
            clientIdMetadataDocument: { enabled: Boolean(config.clientMetadataDocuments), ack: 'draft-02',
                allowFetch: (_ctx, id) => allowsMetadataFetch(config, id),
                allowClient: (_ctx, client) => allowsMetadataClient(config, client) },
            revocation: { enabled: true },
            resourceIndicators: { enabled: true,
                defaultResource: ctx => {
                    const resources = [ctx.oidc.params.resource].flat().filter(Boolean);
                    if (resources.length && new Set(resources).size === 1) return resources[0];
                    const client = clientPolicy(config, ctx.oidc.client?.clientId);
                    if (client?.transports?.includes('api')&&!legacyMakeSource(ctx)) throw new errors.InvalidTarget('explicit resource required');
                    return config.resource;
                },
                useGrantedResource: ctx => {
                    if (clientPolicy(config, ctx.oidc.client?.clientId)?.transports?.includes('api') && !legacyMakeSource(ctx) && !ctx.oidc.params.resource) throw new errors.InvalidTarget('explicit resource required');
                    return true;
                },
                // Owns resource validation before consent and token issuance.
                // The provider invokes this for every indicator, including repeats.
                getResourceServerInfo: async (ctx, resource) => {
                    const indicators = [ctx.oidc.params.resource].flat().filter(Boolean);
                    const client = clientPolicy(config, ctx.oidc.client?.clientId);
                    if (new Set(indicators).size > 1 || !resourceEndpoint(config, resource) ||
                        !clientForResource(config, client?.id, resource)) throw new errors.InvalidTarget();
                    const source = ctx.oidc.entities.RefreshToken ?? ctx.oidc.entities.AuthorizationCode;
                    if (source) {
                        const grant = storage.get('Delegation', source.grantId);
                        if (!grant || grantEndpoint(config, grant).resource !== resource) throw new errors.InvalidTarget();
                    }
                    return { scope: (clientPolicy(config, ctx.oidc.client?.clientId)?.allowedScopes ?? DOMAIN_SCOPES).join(' '), audience: resource, accessTokenTTL: 300, accessTokenFormat: 'opaque' };
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
            if (!boundGrant(grant) || !clientForResource(config, client.clientId, grant.resource ?? config.resource)) return false;
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
            // oidc-provider 9.12.2 resolves resources AFTER consuming/rotating
            // refresh. Reject invalid API targets here, before that irreversible
            // step, rather than losing a valid family on a malformed request.
            const client = clientPolicy(config, ctx.oidc.client.clientId);
            const requested = [ctx.oidc.params.resource].flat().filter(Boolean);
            if (client?.transports?.includes('api') && (legacyMakeSource(ctx)
                ? requested.length>0&&(new Set(requested).size!==1||requested[0]!==config.resource)
                : new Set(requested).size !== 1 || requested[0] !== grant?.resource))
                throw new errors.InvalidTarget('refresh resource is immutable');
            if (!boundGrant(grant) || !connectionActive(grant) || grant.clientId !== ctx.oidc.client.clientId)
                throw new errors.InvalidGrant('connection expired or revoked');
            try { limit('refresh:'+grant.id,REFRESH_REPLAY_LIMITS.refreshPerMinute); }
            catch { const error=new errors.TemporarilyUnavailable('refresh admission budget exhausted');error.status=error.statusCode=503;ctx.set('Retry-After','60');throw error; }
            if (storage.stats().records >= 19990) {
                const error = new errors.TemporarilyUnavailable('authorization storage is at capacity');
                error.status = error.statusCode = 503;
                throw error;
            }
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
    const limit = (bucket, max) => {
        const at = bucket.indexOf(':');
        const type = bucket.slice(0, at);
        try { rateLimiter(type, bucket.slice(at + 1), max); }
        catch (error) { audit({ event: 'rate_limit', bucket: type, outcome: 'rejected' }); throw error; }
    };
    const limited = (req, res, error) => {
        if (req.path.startsWith(API_PREFIX)) return sendProblem(res, error ?? { code: 'TEMPORARILY_LIMITED' });
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
        let endpoint;
        try { endpoint = ingressEndpoint(config, req); } catch { return sendProblem(res, { code: 'INVALID_INGRESS' }); }
        req.integrationEndpoint = endpoint;
        if (!loopback || (!endpoint && req.headers.host !== expected.host) ||
            (canonical && req.headers['x-forwarded-proto'] !== 'https')) return res.sendStatus(400);
        if ((endpoint || req.path === '/mcp' || req.path.startsWith('/make/v1/')) && req.headers.origin && req.headers.origin !== (endpoint ? new URL(endpoint.publicBase).origin : config.issuer))
            return endpoint ? sendProblem(res, { code: 'FORBIDDEN' }, { endpoint, outcome: 'rejected' }) : res.sendStatus(403);
        res.set({ 'Cache-Control': 'no-store', 'Referrer-Policy': 'same-origin',
            'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY',
            // Empty script-src denies scripts; oidc-provider adds only the exact
            // hash of its account-switch auto-submit script when it renders it.
            'Content-Security-Policy': `default-src 'none'; script-src; style-src 'unsafe-inline'; form-action ${formAction}; frame-ancestors 'none'; base-uri 'none'` });
        if (canonical) res.set('Strict-Transport-Security', 'max-age=31536000');
        if (req.method === 'GET' && req.path === '/healthz') return next();
        let ip;
        try { ip = clientIdentity(req, canonical); } catch { return endpoint ? sendProblem(res, { code: 'INVALID_INGRESS' }, { outcome: 'rejected' }) : res.sendStatus(400); }
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
    const run = createHostedRunner({ config, storage, provider, fetchImpl, audit, limit });
    installApi(app, { config, run });
    const legacyMake = config.clients.some(c => c.transports?.includes('legacy-make'));
    // Retirement requires accepted Make review and verified consumer migration.
    // A calendar deadline must never disable the connector during its review.
    if (legacyMake) app.get('/make/v1', (_req, res) => res.json(makeDocumentation(config,
        new Operations({ root: storage.root, orderSummaryOnly: true, allowedOperations: MAKE_READ_OPERATIONS }).catalog)));
    const metadata = { resource_documentation: config.issuer + '/docs', resource_name: config.regionalPortal?.name ?? 'Festapp', resource: config.resource, authorization_servers: [config.issuer], scopes_supported: DOMAIN_SCOPES };
    for (const route of ['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'])
        app.get(route, (_req, res) => res.set('Access-Control-Allow-Origin', '*').json(metadata));
    app.get('/auth', (req, _res, next) => {
        // This issuer always requires explicit consent. Tell the provider before
        // scope validation, otherwise it discards requested offline_access.
        const url = new URL(req.url, config.issuer);
        if (!url.searchParams.has('prompt') && !url.searchParams.has('request_uri')) {
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
        const resources = [d.params.resource ?? config.resource].flat();
        check(new Set(resources).size === 1 && resourceEndpoint(config, resources[0]), 'FORBIDDEN');
        d.integrationEndpoint = resourceEndpoint(config, resources[0]);
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
        if (!previousGrant.resource) storage.putUntil('Delegation', previousGrant.id, { ...previousGrant,
            resource: config.resource, endpointId: 'mcp', proofProfile: 'bearer', dataProfile: clientPolicy(config, previousGrant.clientId)?.dataProfile ?? 'operator' }, previousGrant.expiresAt);
        if (previousGrant.access || !previousGrant.occasions) continue;
        const { occasions, ...grant } = previousGrant;
        storage.putUntil('Delegation', grant.id, { ...storage.get('Delegation', grant.id), access: { type: 'occasions', occasionIds: occasions } }, grant.expiresAt);
    }
    const availableAccess = async (owner, backend) => operatorAccess(backend, owner.profile);
    const canRequestCreate = d => String(d.params.scope ?? '').split(' ').includes(CREATE_SCOPE);
    const completeConsent = async (req, res, d, f, selection) => {
        const selectedConfig = flowConfig(d.uid);
        const endpoint = d.integrationEndpoint;
        check(!f.api || f.api.resource===endpoint.resource&&f.api.dataProfile===clientPolicy(config,d.params.client_id).dataProfile,'FORBIDDEN');
        check(endpoint.profilePolicy.type !== 'fixed' || endpoint.profilePolicy.profileBinding === selectedConfig.profile.binding, 'FORBIDDEN');
        const consentOwner = loginOwner(d.uid);
        const access = await consentOwner.authorized(async backend =>
            verifySelection(selection, await availableAccess(consentOwner, backend), canRequestCreate(d)));
        const permissions = verifyPermissions(f.permissions, String(d.params.scope ?? '').split(' '));
        const scopes = [READ_SCOPE, ...(canCreateWithAccess(access) ? [CREATE_SCOPE] : []), ...permissions].join(' ');
        check(clientAllowsScopes(config, d.params.client_id, scopes.split(' ')), 'FORBIDDEN');
        const choice = verifyConnectionChoice(f.connection, storage, f.userId, d.params.client_id, selectedConfig.profile.binding, {resource:endpoint.resource,legacyResource:config.resource});
        if (choice.replaces) check(grantEndpoint(config, storage.get('Delegation', choice.replaces)).resource === endpoint.resource, 'FORBIDDEN');
        check(choice.durationDays <= (clientPolicy(config, d.params.client_id).maxConsentDays ?? 365), 'FORBIDDEN');
        const durationSeconds = choice.durationDays * DAY_SECONDS;
        const createdAt = Date.now();
        const expiresAt = consentDeadline(choice.durationDays, createdAt);
        const pendingExpiresAt = Math.min(d.exp * 1000, expiresAt);
        const grant = new provider.Grant({ accountId: f.userId, clientId: d.params.client_id, expiresIn: durationSeconds });
        grant.addOIDCScope(`openid offline_access ${scopes}`);
        grant.addResourceScope(endpoint.resource, scopes);
        // A narrower consent is a completed decision, not an unanswered prompt.
        // Without recording rejected scopes the provider starts consent again.
        const approved = new Set(['openid', 'offline_access', ...scopes.split(' ')]);
        const rejected = String(d.params.scope ?? '').split(' ').filter(s => s && !approved.has(s));
        grant.rejectOIDCScope(rejected.join(' '));
        grant.rejectResourceScope(endpoint.resource, rejected.filter(s => s !== 'openid' && s !== 'offline_access').join(' '));
        const grantId = await grant.save();
        {
            // Spent opaque credentials occupy capped encrypted replay buckets,
            // rather than a new main-store row per exchange. Reserve live-token
            // and consent headroom; never evict valid evidence to admit a grant.
            const capacity=storage.stats();
            if (capacity.records > 18000 || capacity.replayBytes > 24*1024*1024 || storage.values('Delegation').filter(g=>connectionActive(g)||connectionIssuable(g)).length >= REFRESH_REPLAY_LIMITS.admittedConnections) {
                await grant.destroy();
                check(false, 'TEMPORARILY_LIMITED');
            }
        }
        const sessionBinding = connectionBinding(selectedConfig.profile, d.uid);
        storage.putUntil('Delegation', grantId, { id: grantId, userId: f.userId, clientId: d.params.client_id,
            resource: endpoint.resource, endpointId: endpoint.endpointId, proofProfile: clientPolicy(config, d.params.client_id).proofProfile ?? 'bearer',
            dataProfile: clientPolicy(config, d.params.client_id).dataProfile,
            operationAllowlist: clientPolicy(config, d.params.client_id).allowedOperations,
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
        if (!f) { f = { csrf: nonce() }; }
        if (d.integrationEndpoint.profilePolicy.type === 'fixed') {
            check(!f.profileBinding || f.profileBinding === d.integrationEndpoint.profilePolicy.profileBinding, 'FORBIDDEN');
            f.profileBinding = d.integrationEndpoint.profilePolicy.profileBinding;
        }
        storage.put('Connect', d.uid, f, 600);
        if ((config.contexts || d.integrationEndpoint.endpointId === 'global-api') && !f.profileBinding) return res.type('html').send(contextChoiceForm({
            csrf: f.csrf, action: `/connect/${d.uid}/context`, contexts: remoteContexts(config) }));
        if (tenantRedirect) return tenantRedirect(res, d, f);
        const client = clientPolicy(config, d.params.client_id).name;
        if (!f.userId) return res.type('html').send(loginForm({ csrf: f.csrf, client,
            action: `/connect/${d.uid}/login`, consent: true, error }));
        const consentOwner = loginOwner(d.uid);
        const available = await consentOwner.authorized((backend, context) =>
            availableAccess(consentOwner, backend, context.userId));
        check(available.occasions.length > 0 || available.units.length > 0, 'FORBIDDEN');
        f.available = available;
        if(d.integrationEndpoint.endpointId!=='mcp') f.api={resource:d.integrationEndpoint.resource,dataProfile:clientPolicy(config,d.params.client_id).dataProfile};
        f.permissions = MCP_SCOPES.filter(s => String(d.params.scope ?? '').split(' ').includes(s));
        storage.put('Connect', d.uid, f, 600);
        return res.type('html').send(consentForm({ csrf: f.csrf, client, permissions:f.permissions, canCreate:canRequestCreate(d), api:f.api, maxConsentDays:clientPolicy(config,d.params.client_id).maxConsentDays,
            connections: activeConnections(storage, f.userId, d.params.client_id, consentOwner.config?.profile?.binding ?? flowConfig(d.uid).profile.binding, {resource:d.integrationEndpoint.resource,legacyResource:config.resource}), action: `/connect/${d.uid}/consent`, occasions: available.occasions, units: available.units, selectedTenant: flowConfig(d.uid).profile.tenantId }));
    };
    app.post('/connect/:uid/context', form, async (req, res) => {
        const d = await details(req), f = flow(d.uid);
        check((config.contexts || d.integrationEndpoint.endpointId === 'global-api') && f && !f.profileBinding && !f.request, 'FORBIDDEN');
        csrfCheck(req, f);
        check(d.integrationEndpoint.profilePolicy.type === 'selected', 'FORBIDDEN');
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
            storage.put('Connect', d.uid, { ...f, csrf: nonce(), userId }, 600);
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
        const permissionMode = req.body.permissionMode ?? 'requested';
        check(MCP_CONSENT_MODES.includes(permissionMode), 'FORBIDDEN');
        const requestedPermissions = verifyPermissions(req.body.consentVersion === '3' ? f.permissions ?? []
            : req.body.permission === undefined ? [] : [req.body.permission].flat(), String(d.params.scope ?? '').split(' '));
        const permissions = permissionsForConsent(requestedPermissions, permissionMode);
        const selection = req.body.unit ? { type: 'unit', unitId: Number(req.body.unit), canCreateOccasions: permissionMode === 'requested' && (req.body.consentVersion === '3'
            ? canRequestCreate(d) && f.available?.units.some(u => u.id === Number(req.body.unit) && u.canCreateOccasions) === true
            : req.body.create === '1') }
            : { type: 'occasions', occasionIds: [req.body.occasion].flat().map(Number) };
        // The standalone select also submits in New device mode. Validate every
        // supplied ID before discarding that unused, owned selection.
        if (req.body.connectionId !== undefined) verifyConnectionChoice({ mode: 'replace', connectionId: req.body.connectionId },
            storage, f.userId, d.params.client_id, config.profile.binding);
        if (req.body.durationDays !== undefined) check(CONNECTION_DURATION_DAYS.some(days => String(days) === req.body.durationDays), 'FORBIDDEN');
        const connection = req.body.mode === undefined && req.body.durationDays === undefined ? undefined : { mode: req.body.mode ?? 'new',
            ...(req.body.durationDays !== undefined ? { durationDays: Number(req.body.durationDays) } : {}),
            ...(req.body.mode === 'replace' ? { connectionId: req.body.connectionId } : {}), name: req.body.name };
        // Both UI adapters use the same narrowing contract. Older open pages
        // retain their explicit permission approvals and default requested mode.
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
    const challenge = (res, scheme) => res.status(401).set('WWW-Authenticate',
        authChallenge(config, { scheme, error: 'invalid_token', description: 'Connect your Festapp account.' })).json({ error: 'invalid_token' });
    app.post(['/mcp', ...(legacyMake ? ['/make/v1/operations/:operation'] : [])], express.json({ limit: '48kb' }), async (req, res) => {
        const make = req.path !== '/mcp';
        try { return await run(req, resourceEndpoint(config, config.resource), make ? 'legacy-make' : 'mcp', async ({ operations, owner, client, requestId }) => {
            if (make) {
                check(client.id === MAKE_CLIENT_ID && owner.orderSummaryOnly && MAKE_READ_OPERATIONS.includes(req.params.operation), 'FORBIDDEN');
                owner.allowedOperations = owner.allowedOperations.filter(id => MAKE_READ_OPERATIONS.includes(id));
            }
            const id = make ? req.params.operation : req.body?.method === 'tools/call' ? operations.operationIdForTool(req.body.params?.name) : undefined;
            if (id && !owner.permitsOperation(id)) {
                const challenge = owner.challengeFor('INSUFFICIENT_SCOPE', id);
                if (challenge) return res.status(403).set('WWW-Authenticate', challenge).json({ error: 'insufficient_scope' });
                return res.status(403).json({ error: 'access_denied' });
            }
            if (owner.allowedOperations.some(id => ['ticket_layouts.save','ticket_layouts.pending','ticket_layouts.resume'].includes(id))) await operations.prepare();
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
            const handler = createMcpHandler(() => createServer(operations));
            try {
                await toNodeHandler(handler)(req, res, req.body);
                audit({ event: 'request', requestId, status: res.statusCode });
            } finally { await handler.close(); }
        }); } catch (error) {
            if (error.code === 'TEMPORARILY_LIMITED') return limited(req, res, error);
            if (error.code === 'FORBIDDEN') return res.status(403).json({ error: 'access_denied' });
            return challenge(res, req.integrationAuthScheme);
        }
    });
    app.all('/mcp', (_req, res) => res.sendStatus(405));
    if (legacyMake) app.all('/make/v1/operations/:operation', (_req, res) => res.status(405)
        .json({ ok: false, error: { code: 'METHOD_NOT_ALLOWED', message: 'Use POST.', retryable: false } }));
    // Serialize token exchanges in this single-process deployment. In addition
    // to atomic adapter consumption, this keeps library code/refresh replay
    // revocation ordered before the next exchange can issue credentials.
    let tokenQueue = Promise.resolve(), tokenWaiting = 0;
    let tokenWindowAt = performance.now(), tokenWindow = {exchanges:0,rejected:0,totalMs:0,maxMs:0};
    app.post('/token', async (req, res) => {
        if (tokenWaiting >= 8) return limited(req, res);
        const started = performance.now();
        tokenWaiting++;
        const previous = tokenQueue;
        let release;
        tokenQueue = new Promise(resolve => { release = resolve; });
        await previous;
        try { return await provider.callback()(req, res); }
        finally {
            tokenWaiting--; release();
            const elapsed = performance.now()-started;
            tokenWindow.exchanges++;tokenWindow.rejected+=Number(res.statusCode>=400);tokenWindow.totalMs+=elapsed;tokenWindow.maxMs=Math.max(tokenWindow.maxMs,elapsed);
            if(performance.now()-tokenWindowAt>=60000){
                try { const capacity=storage.stats();audit({event:'token_window',...tokenWindow,queued:tokenWaiting,records:capacity.records,capacity:capacity.capacity,replayBytes:capacity.replayBytes,activeConnections:storage.values('Delegation').filter(g=>connectionActive(g)).length}); } catch { /* Metrics cannot undo issuance. */ }
                tokenWindowAt=performance.now();tokenWindow={exchanges:0,rejected:0,totalMs:0,maxMs:0};
            }
        }
    });
    app.use(provider.callback());
    app.use((error, req, res, _next) => {
        if (res.headersSent) return res.end();
        const safe = safeError(error);
        if (safe.code === 'TEMPORARILY_LIMITED') return limited(req, res, error);
        res.status(safe.code === 'FORBIDDEN' ? 403 : safe.code === 'TEMPORARILY_LIMITED' ? 429 : 400)
            .type('html').send(page('Požadavek se nezdařil', '<p>Připojení vypršelo, bylo odmítnuto nebo se službou nelze spojit. Spusťte připojení znovu.</p>'));
    });
    const webhooks = createWebhookWorker({config, storage, fetchImpl, audit});
    return { app, provider, webhooks };
}
