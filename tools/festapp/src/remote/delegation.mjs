import { grantEndpoint, clientForResource, resourceEndpoint } from './endpoints.mjs';
import { contextConfig } from './config.mjs';
import { clientPolicy } from './client-policy.mjs';
import { authorizeApiAuthentication } from '../auth/operation-policy.mjs';
import { connectionActive } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { rejectLegacyLock } from '../auth/process-lock.mjs';
import { join } from 'node:path';
import { SessionOwner } from '../auth/session.mjs';
import { digest } from '../context/profile.mjs';
import { check, OperationError } from '../errors.mjs';
import { authChallenge } from '../mcp/protocol.mjs';
import { operatorAccess, accessSelection, canCreateWithAccess } from '../operations/access.mjs';
import { DELEGATED_OPERATIONS, READ_SCOPE, CREATE_SCOPE, scopesForOperation, clientAllowsScopes } from './config.mjs';

export function boundOwner(config, storage, binding, options = {}) {
    return new SessionOwner(Object.freeze({ ...config.profile, binding }), {
        ...options, root: storage.root, store: storage.backendStore,
        lockStrategy: async action => {
            await rejectLegacyLock(join(storage.root, 'locks', binding));
            return storage.runSessionExclusive(binding, action);
        },
    });
}

export class DelegatedOwner {
    constructor(config, storage, token, options = {}) {
        this.config = config;
        this.storage = storage;
        this.token = token;
        this.expectedResource = options.expectedResource ?? config.resource;
        this.transport = options.transport ?? 'mcp';
        this.orderSummaryOnly = clientPolicy(config, token.clientId)?.dataProfile === 'order-summary';
        const grant = this.current();
        this.config = contextConfig(config, grant.profileBinding);
        this.session = boundOwner(this.config, storage, grant.binding, options);
        this.imageUploadFetch = options.fetchImpl;
        this.profile = this.session.profile;
        this.layoutProfile = this.config.profile;
        this.root = storage.root;
        this.allowedOperations = DELEGATED_OPERATIONS.filter(id => this.permitsOperation(id, grant));
        this.securitySchemes = [{ type: 'oauth2', scopes: [READ_SCOPE] }];
    }
    operationDenial(id, grant) {
        const current = grant ?? this.current();
        const scopes = scopesForOperation(id);
        if (!this.clientPermitsOperation(id, scopes)) return 'FORBIDDEN';
        if (current.operationAllowlist && !current.operationAllowlist.includes(id))
            return 'INSUFFICIENT_SCOPE';
        const tokenScopes = this.token.scope?.split(' ') ?? [];
        return scopes.every(scope => tokenScopes.includes(scope) && (scope === READ_SCOPE ||
            (scope === CREATE_SCOPE ? canCreateWithAccess(current.access) : current.permissions?.includes(scope))))
            ? null : 'INSUFFICIENT_SCOPE';
    }
    permitsOperation(id, grant) {
        return this.operationDenial(id, grant) === null;
    }
    requireOperation(id, grant) {
        const denial = this.operationDenial(id, grant);
        if (denial) throw new OperationError(denial);
    }
    securitySchemesFor(id) {
        const scopes = scopesForOperation(id);
        check(scopes, 'FORBIDDEN');
        return [{ type: 'oauth2', scopes }];
    }
    // The client registration decides what any connection may ever obtain. Outside it, reconnecting
    // cannot help, so callers report FORBIDDEN rather than a scope gap or a scope challenge.
    clientPermitsOperation(id, scopes = scopesForOperation(id)) {
        const allowedOperations = clientPolicy(this.config, this.token.clientId)?.allowedOperations;
        return (!allowedOperations || allowedOperations.includes(id)) &&
            clientAllowsScopes(this.config, this.token.clientId, scopes);
    }
    challengeFor(code, id) {
        if (['AUTHENTICATION_REQUIRED', 'MFA_REQUIRED'].includes(code))
            return authChallenge(this.config, { scheme: this.token.jkt ? 'DPoP' : 'Bearer', error: 'invalid_token', description: 'Reconnect your Festapp account to continue.' });
        if (code === 'INSUFFICIENT_SCOPE' && this.clientPermitsOperation(id)) {
            const endpoint = this.transport === 'api' && resourceEndpoint(this.config, this.expectedResource);
            const resourceMetadata = endpoint
                ? new URL('/.well-known/oauth-protected-resource/integrations', endpoint.publicBase).href
                : undefined;
            return authChallenge(this.config, { scheme: this.token.jkt ? 'DPoP' : 'Bearer', error: 'insufficient_scope',
                description: 'Authorize all required operation scopes.', scopes: scopesForOperation(id), resourceMetadata });
        }
    }
    current() {
        const t = this.token;
        const grant = this.storage.get('Delegation', t.grantId);
        check(connectionActive(grant) && grant.userId === t.accountId &&
            clientPolicy(this.config, grant.clientId) &&
            grant.clientId === t.clientId &&
            (!grant.dataProfile || grant.dataProfile === clientPolicy(this.config, t.clientId)?.dataProfile) &&
            (!this.session || (this.session.profile.binding === grant.binding && this.config.profile.binding === grant.profileBinding)) &&
            connectionContext(this.config, grant) &&
            t.exp * 1000 > Date.now() &&
            t.aud === this.expectedResource &&
            grantEndpoint(this.config, grant).resource === this.expectedResource &&
            (grant.proofProfile ?? 'bearer') === (t.jkt ? 'dpop' : 'bearer') &&
            clientForResource(this.config, t.clientId, this.expectedResource) && t.scope?.split(' ').includes(READ_SCOPE) &&
            clientAllowsScopes(this.config, t.clientId, [READ_SCOPE]), 'AUTHENTICATION_REQUIRED');
        return grant;
    }
    authorizeOperation(id, args) {
        const grant = this.current();
        this.requireOperation(id, grant);
        check(this.allowedOperations.includes(id), 'FORBIDDEN');
        const access = accessSelection(grant.access);
        this.operationId = id;
        if (['context.inspect', 'access.inspect'].includes(id)) return;
        if (['occasions.create','occasions.copy','occasions.setup.finalize'].includes(id)) {
            check(access.units.some(u => u.unitId === (id==='occasions.copy'?args.targetUnitId:args.unitId) && u.canCreateOccasions), 'FORBIDDEN');
        } else if (['units.settings.','units.websiteConsent.','units.measurementApproval.','units.metaCapiApproval.'].some(prefix => id.startsWith(prefix))) {
            check(access.units.some(u => u.unitId === args.unitId), 'ORGANIZER_CONSENT_REQUIRED');
        } else if (id.startsWith('email_templates.') && args.entityType === 'unit') {
            check(access.units.some(u => u.unitId === args.entityId), 'FORBIDDEN');
        } else if (!access.units.length) {
            check(access.occasionIds.includes(args.occasionId ?? (args.entityType === 'occasion' ? args.entityId : undefined)), 'FORBIDDEN');
        }
    }
    // Domain SQL checks the live binding atomically; this only projects the
    // consent's narrowing constraints into that same request.
    async delegatedContext(client, occasionId) {
        const access = this.current().access;
        const selection = accessSelection(access);
        let unitId = access.type === 'unit' ? access.unitId : null;
        if (access.type === 'selection' && !selection.occasionIds.includes(occasionId)) {
            // Resolve the current organizer, then bind that same organizer in
            // the atomic SQL read so moving an occasion cannot widen a grant.
            const live = await operatorAccess(client, this.profile, { occasionId });
            unitId = live.occasions.find(o => o.id === occasionId)?.unitId;
            check(selection.units.some(u => u.unitId === unitId), 'FORBIDDEN');
        }
        return { organizationId: this.config.profile.organizationId,
            unitId };
    }
    async delegatedUnitContext(client, unitId) {
        const selection = accessSelection(this.current().access);
        check(selection.units.some(u => u.unitId === unitId), 'ORGANIZER_CONSENT_REQUIRED');
        return { organizationId: this.config.profile.organizationId, unitId };
    }
    async listAccess(client) {
        const access = accessSelection(this.current().access);
        const live = await operatorAccess(client, this.config.profile);
        const units = live.units.filter(u => access.units.some(g => g.unitId === u.id));
        return { units: units.map(u => ({ ...u, canCreateOccasions:
            u.canCreateOccasions && access.units.some(g => g.unitId === u.id && g.canCreateOccasions) && this.allowedOperations.includes('occasions.create') })),
            occasions: live.occasions.filter(o => access.occasionIds.includes(o.id) || units.some(u => u.id === o.unitId)) };
    }
    async authorized(action) {
        const grant = this.current();
        const isLayout = this.operationId?.startsWith('ticket_layouts.');
        const execute = () => this.session.authorized(async (client, context) => {
            check(context.userId === grant.userId, 'FORBIDDEN');
            this.current();
            if (this.transport === 'api' && this.operationId) authorizeApiAuthentication(this.operationId, {
                token: this.token, client: clientPolicy(this.config, this.token.clientId),
                userId: context.userId, authentication: context.authentication,
            });
            const result = await action(client, isLayout ? { ...context, profile: this.layoutProfile } : context);
            // Read revocation discards an in-flight private result before return.
            const liveGrant = this.current();
            if (this.operationId) this.requireOperation(this.operationId, liveGrant);
            return result;
        });
        try {
            // Reconnects share artwork recovery state, while credentials retain
            // their independent per-connection locks and refresh tokens.
            return await (isLayout ? this.storage.runSessionExclusive(
                digest(JSON.stringify(['layout', this.layoutProfile.binding, grant.userId])), execute) : execute());
        } catch (error) {
            const current = this.storage.get('Delegation', this.token.grantId);
            if (!connectionActive(current) || this.token.exp * 1000 <= Date.now())
                error = new OperationError('AUTHENTICATION_REQUIRED');
            const reason = error.code === 'COMMITTED_READBACK_FAILED' ? error.cause?.code : error.code;
            if (reason === 'AUTHENTICATION_REQUIRED' || reason === 'MFA_REQUIRED')
                this.storage.revoke(this.token.grantId);
            throw error;
        }
    }
}

export const connectionBinding = (profile, interaction) =>
    digest(JSON.stringify(['remote', profile.binding, interaction]));

/** OAuth credentials and requests share this immutable connection identity check.
 * Historical regional grants keep their supported stored binding. Global grants
 * always carry an interaction and may never adopt those historical sessions. */
export function connectionContext(config, grant) {
    const selected = contextConfig(config, grant?.profileBinding);
    check(grant.interactionId ? grant.binding === connectionBinding(selected.profile, grant.interactionId)
        : !config.contexts, 'AUTHENTICATION_REQUIRED');
    return selected;
}
