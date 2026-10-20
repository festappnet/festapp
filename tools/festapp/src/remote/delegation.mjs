import { SessionOwner } from '../auth/session.mjs';
import { digest } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import { operatorAccess } from '../operations/access.mjs';
import { READ_OPERATIONS, READ_SCOPE, CREATE_SCOPE } from './config.mjs';

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
        this.allowedOperations = [...READ_OPERATIONS, ...(grant.access.type === 'unit' && grant.access.canCreateOccasions && token.scope?.split(' ').includes(CREATE_SCOPE) ? ['occasions.create'] : [])];
        this.authChallenge = `Bearer resource_metadata="${config.issuer}/.well-known/oauth-protected-resource/mcp", scope="${READ_SCOPE}"`;
        this.securitySchemes = [{ type: 'oauth2', scopes: [READ_SCOPE] }];
    }
    securitySchemesFor(id) {
        return [{ type: 'oauth2', scopes: id === 'occasions.create' ? [READ_SCOPE, CREATE_SCOPE] : [READ_SCOPE] }];
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
        const access = this.current().access;
        check(this.allowedOperations.includes(id), 'FORBIDDEN');
        if (['context.inspect', 'access.inspect'].includes(id)) return;
        if (id === 'occasions.create') {
            check(access.type === 'unit' && access.canCreateOccasions && access.unitId === args.unitId, 'FORBIDDEN');
        } else if (access.type === 'occasions') {
            check(access.occasionIds.includes(args.occasionId), 'FORBIDDEN');
        }
    }
    async authorizeContext(id, args, client) {
        const access = this.current().access;
        if (['context.inspect', 'access.inspect'].includes(id) || access.type === 'occasions') return;
        const live = await operatorAccess(client, this.config.profile,
            { unitId: access.unitId, occasionId: args.occasionId });
        const unit = live.units.find(u => u.id === access.unitId);
        check(unit, 'FORBIDDEN');
        if (id === 'occasions.create') check(unit.canCreateOccasions, 'FORBIDDEN');
        else check(live.occasions.some(o => o.id === args.occasionId && o.unitId === access.unitId), 'FORBIDDEN');
    }
    async listAccess(client) {
        const access = this.current().access;
        const live = await operatorAccess(client, this.config.profile,
            access.type === 'unit' ? { unitId: access.unitId } : {});
        if (access.type === 'occasions') return {
            units: [], occasions: live.occasions.filter(o => access.occasionIds.includes(o.id)),
        };
        check(live.units.some(u => u.id === access.unitId), 'FORBIDDEN');
        return { units: live.units.map(u => ({ ...u, canCreateOccasions:
            u.canCreateOccasions && this.allowedOperations.includes('occasions.create') })),
            occasions: live.occasions };
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
