import { SessionOwner } from '../auth/session.mjs';
import { digest } from '../context/profile.mjs';
import { check, OperationError } from '../errors.mjs';
import { authChallenge } from '../mcp/protocol.mjs';
import { operatorAccess, accessSelection, canCreateWithAccess } from '../operations/access.mjs';
import { READ_OPERATIONS, READ_SCOPE, CREATE_SCOPE, MCP_PERMISSIONS, scopesForOperation, clientAllowsScopes } from './config.mjs';

export function boundOwner(config, storage, binding, options = {}) {
    return new SessionOwner(Object.freeze({ ...config.profile, binding }), {
        ...options, root: storage.root, store: storage.backendStore,
    });
}

export class DelegatedOwner {
    constructor(config, storage, token, options = {}) {
        this.config = config;
        this.storage = storage;
        this.token = token;
        const grant = this.current();
        this.session = boundOwner(config, storage, grant.binding, options);
        this.profile = this.session.profile;
        this.root = storage.root;
        this.allowedOperations = [...READ_OPERATIONS, 'occasions.create',
            ...Object.values(MCP_PERMISSIONS).flatMap(p => p.operations)].filter(id => this.permitsOperation(id, grant));
        this.securitySchemes = [{ type: 'oauth2', scopes: [READ_SCOPE] }];
    }
    permitsOperation(id, grant = this.current()) {
        const scopes = scopesForOperation(id);
        return clientAllowsScopes(this.config, this.token.clientId, scopes) && scopes.every(s =>
            this.token.scope?.split(' ').includes(s) && (s === READ_SCOPE ||
                (s === CREATE_SCOPE ? canCreateWithAccess(grant.access) : grant.permissions?.includes(s))));
    }
    securitySchemesFor(id) {
        const scopes = scopesForOperation(id);
        check(scopes, 'FORBIDDEN');
        return [{ type: 'oauth2', scopes }];
    }
    challengeFor(code, id) {
        if (['AUTHENTICATION_REQUIRED', 'MFA_REQUIRED'].includes(code))
            return authChallenge(this.config, { error: 'invalid_token', description: 'Reconnect your Festapp account to continue.' });
        if (code === 'INSUFFICIENT_SCOPE' && clientAllowsScopes(this.config, this.token.clientId, scopesForOperation(id)))
            return authChallenge(this.config, { error: 'insufficient_scope', description: 'Authorize all required operation scopes.', scopes: scopesForOperation(id) });
    }
    current() {
        const t = this.token;
        const grant = this.storage.get('Delegation', t.grantId);
        check(grant && !grant.revoked && grant.userId === t.accountId &&
            this.config.clients.some(c => c.id === grant.clientId) &&
            grant.clientId === t.clientId && grant.profileBinding === this.config.profile.binding &&
            grant.expiresAt > Date.now() && t.exp * 1000 > Date.now() &&
            t.aud === this.config.resource && t.scope?.split(' ').includes(READ_SCOPE) &&
            clientAllowsScopes(this.config, t.clientId, [READ_SCOPE]), 'AUTHENTICATION_REQUIRED');
        return grant;
    }
    authorizeOperation(id, args) {
        const access = accessSelection(this.current().access);
        check(clientAllowsScopes(this.config, this.token.clientId, scopesForOperation(id)), 'FORBIDDEN');
        check(this.allowedOperations.includes(id) && this.permitsOperation(id), 'INSUFFICIENT_SCOPE');
        this.operationId = id;
        if (['context.inspect', 'access.inspect'].includes(id)) return;
        if (id === 'occasions.create') {
            check(access.units.some(u => u.unitId === args.unitId && u.canCreateOccasions), 'FORBIDDEN');
        } else if (id.startsWith('units.settings.')) {
            check(access.units.some(u => u.unitId === args.unitId), 'FORBIDDEN');
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
        check(selection.units.some(u => u.unitId === unitId), 'FORBIDDEN');
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
        try { return await this.session.authorized(async (client, context) => {
            check(context.userId === grant.userId, 'FORBIDDEN');
            this.current();
            const result = await action(client, context);
            // Read revocation discards an in-flight private result before return.
            this.current();
            if (this.operationId) check(this.permitsOperation(this.operationId), 'INSUFFICIENT_SCOPE');
            return result;
        }); } catch (error) {
            const current = this.storage.get('Delegation', this.token.grantId);
            if (!current || current.revoked || current.expiresAt <= Date.now() || this.token.exp * 1000 <= Date.now())
                error = new OperationError('AUTHENTICATION_REQUIRED');
            if (error.code === 'AUTHENTICATION_REQUIRED' || error.code === 'MFA_REQUIRED')
                this.storage.revoke(this.token.grantId);
            throw error;
        }
    }
}

export const connectionBinding = (profile, interaction) =>
    digest(JSON.stringify(['remote', profile.binding, interaction]));
