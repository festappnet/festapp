import { API_PREFIX } from './endpoints.mjs';
import { publicCatalog, readiness, API_COST_BUDGET } from './api-contract.mjs';
import { randomUUID } from 'node:crypto';
import { DelegatedOwner } from './delegation.mjs';
import { clientPolicy } from './client-policy.mjs';
import { createProofVerifier } from './proof.mjs';
import { Operations } from '../operations/catalog.mjs';
import { PreviewArtifacts } from '../operations/preview.mjs';
import { check, OperationError } from '../errors.mjs';
import { digest } from '../context/profile.mjs';

/** One admission budget, artifact owner and credential verifier for all hosted
 * adapters. Mutable owners and operation contexts live for one request only. */
const apiSupported = new Set(publicCatalog().filter(d => readiness(d).supported).map(d => d.id));
const documentOperations = new Set(publicCatalog().filter(d => d.costClass === 'document').map(d => d.id));

export function createHostedRunner({ config, storage, provider, fetchImpl, audit, limit }) {
    const active = new Map(), artifacts = new PreviewArtifacts();
    const verifyProof = createProofVerifier({ storage });
    let total = 0, documentCount = 0;
    const documentOrgs = new Set(), documentClients = new Set();
    return async function run(req, endpoint, transport, action) {
        const match = /^(Bearer|DPoP) ([A-Za-z0-9_-]{20,512})$/.exec(req.headers.authorization ?? '');
        check(match, 'AUTHENTICATION_REQUIRED');
        const token = await provider.AccessToken.find(match[2]);
        check(token, 'AUTHENTICATION_REQUIRED');
        const client = clientPolicy(config, token.clientId);
        check(client && token.aud === endpoint.resource, 'AUTHENTICATION_REQUIRED');
        req.integrationAuthScheme = token.jkt || client.proofProfile === 'dpop' ? 'DPoP' : 'Bearer';
        await verifyProof(req, token, match[2], endpoint, client);
        let owner;
        try { owner = new DelegatedOwner(config, storage, token, { fetchImpl, expectedResource: endpoint.resource, transport }); }
        catch { throw new OperationError('AUTHENTICATION_REQUIRED'); }
        const grant = owner.current();
        if (transport === 'api') owner.allowedOperations = owner.allowedOperations.filter(id => apiSupported.has(id));
        limit(`client:${client.id}:${owner.profile.organizationId}`, 120);
        limit(`organization:${owner.profile.organizationId}`, 240);
        check((client.transports ?? ['mcp']).includes(transport), 'FORBIDDEN');
        check((active.get(token.grantId) ?? 0) < 2 && total < 16, 'TEMPORARILY_LIMITED');
        limit(`grant:${token.grantId}`, 60);
        active.set(token.grantId, (active.get(token.grantId) ?? 0) + 1); total++;
        const pendingInvocations = new Set();
        const track = task => {
            let tracked;
            tracked = Promise.resolve(task).finally(() => pendingInvocations.delete(tracked));
            pendingInvocations.add(tracked);
            return tracked;
        };
        let documentAdmitted = false;
        const documentOrg = String(owner.profile.organizationId), documentClient = client.id + ':' + documentOrg;
        try {
            // Last-used is coarse management metadata, never authorization evidence.
            // Avoid an extra FULL SQLite fsync on every successful read.
            if (!grant.clientConnectedAt || !grant.lastUsedAt || Date.now() - grant.lastUsedAt >= 60000)
                storage.putUntil('Delegation', grant.id, { ...grant, clientConnectedAt: grant.clientConnectedAt ?? Date.now(), lastUsedAt: Date.now() }, grant.expiresAt);
            const operations = new Operations(owner, { artifacts });
            const id = transport === 'mcp' && req.body?.method === 'tools/call'
                ? operations.operationIdForTool(req.body.params?.name) : req.params?.operation;
            const document = (documentOperations.has(id) && owner.allowedOperations.includes(id)) || req.path === API_PREFIX + '/artifacts/read' ||
                (transport === 'mcp' && req.body?.method === 'resources/read');
            if (document) {
                if (documentCount >= API_COST_BUDGET.concurrentDocuments || documentOrgs.has(documentOrg) || documentClients.has(documentClient))
                    throw new OperationError('TEMPORARILY_LIMITED', true);
                limit(`documentOrg:${documentOrg}`, API_COST_BUDGET.documentPerOrgPerMinute);
                limit(`documentClient:${documentClient}`, API_COST_BUDGET.documentPerClientOrgPerMinute);
                documentCount++;documentOrgs.add(documentOrg);documentClients.add(documentClient);documentAdmitted = true;
            }
            const invoke = operations.invoke.bind(operations);
            const readArtifact = operations.readArtifact.bind(operations);
            operations.readArtifact = (...args) => track(readArtifact(...args));
            operations.invoke = (id, args) => track((async () => {
                const result = await invoke(id, args);
                audit({ event: 'operation', requestId: result.meta.requestId,
                    connection: digest(token.grantId), actor: digest(token.accountId), client: token.clientId,
                    tenant: owner.profile.tenantId, transport, resource: endpoint.resource,
                    operation: id, outcome: result.ok ? 'ok' : result.error.code });
                return result;
            })());
            return await action({ operations, owner, client, requestId: randomUUID() });
        } finally {
            // SDK transport closure does not prove the tool stopped. Keep the
            // same admission slots until all already-started work has settled.
            await Promise.allSettled([...pendingInvocations]);
            if (documentAdmitted) {documentCount--;documentOrgs.delete(documentOrg);documentClients.delete(documentClient);}
            const count = (active.get(token.grantId) ?? 1) - 1;
            if (count) active.set(token.grantId, count); else active.delete(token.grantId);
            total--;
        }
    };
}
