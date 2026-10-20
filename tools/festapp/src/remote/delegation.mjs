import { SessionOwner } from '../auth/session.mjs';
import { digest } from '../context/profile.mjs';
import { check } from '../errors.mjs';
import { READ_OPERATIONS, READ_SCOPE } from './config.mjs';

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
        this.allowedOperations = READ_OPERATIONS;
        this.authChallenge = `Bearer resource_metadata="${config.issuer}/.well-known/oauth-protected-resource/mcp", scope="${READ_SCOPE}"`;
        this.securitySchemes = [{ type: 'oauth2', scopes: [READ_SCOPE] }];
    }
    current() {
        const t = this.token;
        const grant = this.storage.get('Delegation', t.grantId);
        const operator = this.config.operators.find(o => o.userId === grant?.userId);
        check(grant && !grant.revoked && grant.userId === t.accountId &&
            operator && this.config.clients.some(c => c.id === grant.clientId) &&
            grant.occasions.every(id => operator.occasions.includes(id)) &&
            grant.clientId === t.clientId && grant.profileBinding === this.config.profile.binding &&
            grant.expiresAt > Date.now() && t.exp * 1000 > Date.now() &&
            t.aud === this.config.resource && t.scope?.split(' ').includes(READ_SCOPE), 'FORBIDDEN');
        return grant;
    }
    authorizeOperation(id, args) {
        const grant = this.current();
        check(READ_OPERATIONS.includes(id), 'FORBIDDEN');
        if (id !== 'context.inspect') check(grant.occasions.includes(args.occasionId), 'FORBIDDEN');
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
