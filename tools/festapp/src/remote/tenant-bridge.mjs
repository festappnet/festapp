import { contextConfig, remoteContexts } from './config.mjs';
import { clientPolicy } from './client-policy.mjs';
import { connectionActive, connectionIssuable } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { activeConnections, verifyConnectionChoice } from './connection-choice.mjs';
import { verifyConsent } from './consent.mjs';
import express from 'express';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { digest } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import { READ_SCOPE, MCP_SCOPES } from './config.mjs';

const nonce = () => randomBytes(32).toString('base64url');
const equal = (a, b) => typeof a === 'string' && typeof b === 'string' &&
    timingSafeEqual(Buffer.from(digest(a)), Buffer.from(digest(b)));

// Only the first-party Edge broker can exchange a live app proof for a separate
// downstream session. OAuth completion still requires the original issuer cookie.
export function tenantBridge(app, { config: serviceConfig, storage, brokerSecret, owner, flowConfig, available, canRequestCreate, complete, details, provider }) {
    if (!remoteContexts(serviceConfig).every(c => c.tenantOrigin)) return null;
    check(typeof brokerSecret === 'string' && brokerSecret.length >= 43, 'INVALID_BROKER_SECRET');
    const read = request => {
        check(typeof request === 'string' && /^[A-Za-z0-9_-]{43}$/.test(request), 'FORBIDDEN');
        const entry = storage.get('TenantRequest', digest(request));
        const flow = entry && storage.get('Connect', entry.uid);
        check(flow && flow.expiresAt > Date.now(), 'FORBIDDEN');
        return { uid: entry.uid, flow };
    };
    const save = (uid, flow) => storage.put('Connect', uid, flow, Math.max(1, (flow.expiresAt - Date.now()) / 1000));
    app.post('/tenant-connection', express.json({ limit: '24kb' }), async (req, res) => {
        check(equal(req.headers['x-festapp-mcp-broker'], brokerSecret), 'FORBIDDEN');
        const requestId = req.body?.request;
        const resultContext = typeof requestId === 'string' && storage.get('TenantResult', digest(requestId));
        const context = resultContext ? contextConfig(serviceConfig, resultContext.profileBinding ?? serviceConfig.profile?.binding)
            : flowConfig(read(requestId).uid);
        const config = context;
        check(req.body?.tenantId === config.profile.tenantId &&
            req.body?.organizationId === config.profile.organizationId &&
            req.body?.tenantOrigin === config.tenantOrigin, 'FORBIDDEN');
        const { request, operation, accessToken } = req.body ?? {};
        if (operation === 'status') {
            check(typeof request === 'string' && /^[A-Za-z0-9_-]{43}$/.test(request), 'FORBIDDEN');
            const result = storage.get('TenantResult', digest(request));
            const pending = !result && read(request);
            const uid = result?.uid ?? pending.uid;
            const userId = result?.userId ?? pending.flow.userId;
            await owner(uid, config).withAccessToken(accessToken, async (_backend, context) =>
                check(context.userId === userId, 'FORBIDDEN'));
            if (!result) return res.json({ status: 'pending' });
            const grant = storage.get('Delegation', result.grantId);
            if (connectionIssuable(grant)) return res.json({ status: 'pending' });
            if (!connectionActive(grant)) return res.json({ status: 'revoked' });
            return res.json({ status: grant.clientConnectedAt ? 'connected' : 'pending' });
        }
        const { uid, flow } = read(request);
        if (operation === 'cancel') {
            check(!['completing', 'approved', 'finishing'].includes(flow.state), 'FORBIDDEN');
            const resume = nonce();
            save(uid, { ...flow, state: 'denied', resumeHash: digest(resume) });
            return res.json({ resumeUrl: `${config.issuer}/connect/${uid}/finish?resume=${resume}` });
        }
        const userOwner = owner(uid, config);
        if (operation === 'check') {
            check(flow.state === 'preparing' && equal(req.body.lease, flow.lease), 'FORBIDDEN');
            return res.json({ valid: true, userId: flow.userId });
        }
        if (operation === 'complete') {
            check(flow.state === 'preparing' && equal(req.body.lease, flow.lease), 'FORBIDDEN');
            save(uid, { ...flow, state: 'completing' });
            await userOwner.adoptSession(req.body.session, flow.userId);
            const resume = nonce();
            save(uid, { ...flow, state: 'approved', lease: undefined, resumeHash: digest(resume) });
            return res.json({ resumeUrl: `${config.issuer}/connect/${uid}/finish?resume=${resume}` });
        }
        check(['details', 'prepare'].includes(operation) && flow.state === 'pending', 'FORBIDDEN');
        const proof = await userOwner.withAccessToken(accessToken, async (backend, context) => ({
            userId: context.userId, available: await available(userOwner, backend, context.userId),
        }));
        const client = clientPolicy(config, flow.clientId);
        check(client, 'FORBIDDEN');
        if (operation === 'details') return res.json({ client: client.name, scope: READ_SCOPE,
            ...(flow.api ? {api:flow.api} : {}), maxConsentDays:client.maxConsentDays ?? 365,
            ...(config.regionalPortal ? { regionalPortal: config.regionalPortal } : {}),
            connections: activeConnections(storage, proof.userId, flow.clientId, config.profile.binding, {resource:flow.api?.resource ?? serviceConfig.resource,legacyResource:serviceConfig.resource}), tenantOrigin: config.tenantOrigin, applicationType: client.applicationType, ...proof.available, canRequestCreate: flow.canRequestCreate === true, requestedPermissions: flow.requestedPermissions ?? [], expiresAt: flow.expiresAt });
        let access = req.body.access;
        if(flow.api){
            const review=access?.apiReview;
            check(review?.version===1&&review.resource===flow.api.resource&&review.dataProfile===flow.api.dataProfile&&
                Object.keys(review).every(key=>['version','resource','dataProfile'].includes(key))&&client.dataProfile===flow.api.dataProfile,'FORBIDDEN');
            const {apiReview,...consent}=access;access=consent;
        }
        const { selected, permissions, connection } = verifyConsent(access, proof.available, flow.canRequestCreate === true, flow.requestedPermissions ?? []);
        verifyConnectionChoice(connection, storage, proof.userId, flow.clientId, config.profile.binding, {resource:flow.api?.resource ?? serviceConfig.resource,legacyResource:serviceConfig.resource});
        // Re-read after remote authorization so concurrent approval cannot fork a mint.
        check(read(request).flow.state === 'pending', 'FORBIDDEN');
        const lease = nonce();
        save(uid, { ...flow, state: 'preparing', lease, userId: proof.userId,
            selected, permissions, connection });
        return res.json({ lease, userId: proof.userId, organizationId: config.profile.organizationId });
    });
    app.get('/connect/:uid/finish', async (req, res) => {
        const d = await details(req);
        const flow = storage.get('Connect', d.uid);
        check(flow && flow.expiresAt > Date.now() &&
            typeof req.query.resume === 'string' && digest(req.query.resume) === flow.resumeHash &&
            ['approved', 'denied'].includes(flow.state), 'FORBIDDEN');
        save(d.uid, { ...flow, state: 'finishing' });
        if (flow.state === 'denied') {
            storage.remove('Connect', d.uid);
            return provider.interactionFinished(req, res, { error: 'access_denied' }, { mergeWithLastSubmission: false });
        }
        return complete(req, res, d, flow, flow.selected);
    });
    return (res, d, flow) => {
        const config = flowConfig(d.uid);
        let request = flow.request;
        if (!request) {
            request = nonce();
            const pending = { ...flow, request, state: 'pending', clientId: d.params.client_id, canRequestCreate: canRequestCreate(d), ...(d.integrationEndpoint?.endpointId!=='mcp'?{api:{resource:d.integrationEndpoint.resource,dataProfile:clientPolicy(config,d.params.client_id).dataProfile}}:{}), requestedPermissions: MCP_SCOPES.filter(scope => String(d.params.scope ?? '').split(' ').includes(scope)), expiresAt: Date.now() + 600000 };
            save(d.uid, pending);
            storage.put('TenantRequest', digest(request), { uid: d.uid }, 600);
        }
        const target = new URL('/settings/mcp-connect', config.tenantOrigin);
        target.searchParams.set('request', request);
        if (serviceConfig.contexts) target.searchParams.set('issuer', serviceConfig.issuer);
        return res.redirect(303, target.href);
    };
}
