import { SessionOwner } from '../auth/session.mjs';
import { digest } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import { operatorAccess, accessSelection, canCreateWithAccess } from '../operations/access.mjs';
import { READ_OPERATIONS, READ_SCOPE, CREATE_SCOPE, MCP_PERMISSIONS, scopesForOperation } from './config.mjs';

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
        this.allowedOperations = [...READ_OPERATIONS, ...(canCreateWithAccess(grant.access) && token.scope?.split(' ').includes(CREATE_SCOPE) ? ['occasions.create'] : [])];
        for (const permission of Object.values(MCP_PERMISSIONS)) for (const operation of permission.operations) {
            if (scopesForOperation(operation).every(scope => grant.permissions?.includes(scope) && token.scope?.split(' ').includes(scope))) this.allowedOperations.push(operation);
        }
        this.authChallenge = `Bearer resource_metadata="${config.issuer}/.well-known/oauth-protected-resource/mcp", scope="${READ_SCOPE}"`;
        this.securitySchemes = [{ type: 'oauth2', scopes: [READ_SCOPE] }];
    }
    securitySchemesFor(id) {
        return [{ type: 'oauth2', scopes: id === 'occasions.create' ? [READ_SCOPE, CREATE_SCOPE] : [READ_SCOPE, ...scopesForOperation(id)] }];
    }
    current() {
        const t = this.token;
        const grant = this.storage.get('Delegation', t.grantId);
        check(grant && !grant.revoked && grant.userId === t.accountId &&
            this.config.clients.some(c => c.id === grant.clientId) &&
            grant.clientId === t.clientId && grant.profileBinding === this.config.profile.binding &&
            grant.expiresAt > Date.now() && t.exp * 1000 > Date.now() &&
            t.aud === this.config.resource && t.scope?.split(' ').includes(READ_SCOPE), 'FORBIDDEN');
        return grant;
    }
    authorizeOperation(id, args) {
        const access = accessSelection(this.current().access);
        check(this.allowedOperations.includes(id), 'FORBIDDEN');
        if (['context.inspect', 'access.inspect'].includes(id)) return;
        if (id === 'occasions.create') {
            check(access.units.some(u => u.unitId === args.unitId && u.canCreateOccasions), 'FORBIDDEN');
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
            return result;
        }); } catch (error) {
            if (error.code === 'AUTHENTICATION_REQUIRED' || error.code === 'MFA_REQUIRED')
                this.storage.revoke(this.token.grantId);
            throw error;
        }
    }
}

export const connectionBinding = (profile, interaction) =>
    digest(JSON.stringify(['remote', profile.binding, interaction]));
