import { check } from '../errors.mjs';
import { z } from 'zod';
import { parseProfile } from '../context/profile.mjs';

export { READ_SCOPE, CREATE_SCOPE, READ_OPERATIONS, MCP_PERMISSIONS, MCP_SCOPES, scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
import { READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, validPermissions } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
import { DOMAIN_SCOPES, validScopeCeiling, validRedirect, validMetadataOrigin } from './client-policy.mjs';
export { DOMAIN_SCOPES, clientAllowsScopes } from './client-policy.mjs';
export function verifyPermissions(raw, requested) {
    const parsed = z.array(z.enum(MCP_SCOPES)).max(MCP_SCOPES.length).safeParse(raw ?? []);
    check(parsed.success, 'FORBIDDEN');
    const permissions = [...new Set(parsed.data)];
    check(validPermissions(permissions) && permissions.every(p => requested.includes(p)), 'FORBIDDEN');
    return permissions;
}

const identifier = z.string().min(1).max(200);
const schema = z.strictObject({
    schemaVersion: z.literal(2),
    issuer: z.url(),
    profile: z.unknown().optional(),
    contexts: z.array(z.strictObject({ name: identifier, profile: z.unknown(), tenantOrigin: z.url() })).min(2).max(100).optional(),
    tenantOrigin: z.url().optional(),
    regionalPortal: z.strictObject({ name: identifier, platform: identifier }).optional(),
    clientMetadataDocuments: z.strictObject({
        allowedOrigins: z.array(z.string().refine(validMetadataOrigin)).min(1).max(10),
        allowedScopes: z.array(z.enum(DOMAIN_SCOPES)).min(1).max(DOMAIN_SCOPES.length).optional(),
        dataProfile: z.enum(['operator', 'order-summary']),
    }).optional(),
    clients: z.array(z.strictObject({
        id: identifier,
        name: identifier,
        applicationType: z.enum(['web', 'native']).default('web'),
        dataProfile: z.enum(['operator', 'order-summary']).default('operator'),
        redirectUris: z.array(z.url()).min(1).max(4),
        allowedScopes: z.array(z.enum(DOMAIN_SCOPES)).min(1).max(DOMAIN_SCOPES.length).optional(),
    })).min(1).max(10),

});

export function parseRemoteConfig(raw) {
    const config = schema.parse(raw);
    if (config.contexts && (config.profile || config.tenantOrigin || config.regionalPortal))
        throw new Error('AMBIGUOUS_REMOTE_CONTEXT');
    const contexts = config.contexts?.map(c => Object.freeze({ ...c, profile: parseProfile(c.profile) }));
    const profile = contexts ? undefined : parseProfile(config.profile);
    if (contexts && (new Set(contexts.map(c => c.profile.binding)).size !== contexts.length ||
        new Set(contexts.map(c => c.profile.tenantId)).size !== contexts.length ||
        new Set(contexts.map(c => c.tenantOrigin)).size !== contexts.length ||
        new Set(contexts.map(c => c.profile.kind)).size !== 1)) throw new Error('DUPLICATE_REMOTE_CONTEXT');
    for (const context of contexts ?? []) {
        const origin = new URL(context.tenantOrigin);
        if (origin.origin !== context.tenantOrigin || origin.protocol !== 'https:') throw new Error('INVALID_TENANT_ORIGIN');
    }
    const url = new URL(config.issuer);
    if (config.tenantOrigin) {
        const tenant = new URL(config.tenantOrigin);
        if (tenant.origin !== config.tenantOrigin || tenant.protocol !== 'https:')
            throw new Error('INVALID_TENANT_ORIGIN');
    }
    const local = (profile ?? contexts[0].profile).kind === 'disposable-local';
    const validOrigin = (u) => !u.username && !u.password && !u.search && !u.hash;
    if (!validOrigin(url) || url.pathname !== '/' ||
        (local ? url.protocol !== 'http:' || url.hostname !== '127.0.0.1' : url.protocol !== 'https:'))
        throw new Error('INVALID_REMOTE_ISSUER');
    if (new Set(config.clients.map(c => c.id)).size !== config.clients.length)
        throw new Error('DUPLICATE_REMOTE_IDENTITY');
    if (config.clientMetadataDocuments && ((config.clientMetadataDocuments.allowedScopes && !validScopeCeiling(config.clientMetadataDocuments.allowedScopes)) ||
        new Set(config.clientMetadataDocuments.allowedOrigins).size !== config.clientMetadataDocuments.allowedOrigins.length))
        throw new Error('INVALID_METADATA_CLIENT_POLICY');
    for (const client of config.clients) {
        if (client.allowedScopes && !validScopeCeiling(client.allowedScopes))
            throw new Error('INVALID_CLIENT_SCOPE_CEILING');
    }
    for (const client of config.clients) for (const uri of client.redirectUris) {
        if (!validRedirect(uri, client.applicationType, local))
            throw new Error('INVALID_REMOTE_REDIRECT');
    }
    return Object.freeze({ ...config, profile, ...(contexts ? { contexts: Object.freeze(contexts) } : {}), issuer: url.origin, resource: url.origin + '/mcp' });
}

/** Only protected configuration defines contexts. A request may select an entry,
 * never provide a profile, origin, organization or backend destination. */
export const remoteContexts = config => config.contexts ?? [{ profile: config.profile, tenantOrigin: config.tenantOrigin, name: config.profile.tenantId }];
export function contextConfig(config, binding) {
    const context = remoteContexts(config).find(c => c.profile.binding === binding);
    check(context, 'FORBIDDEN');
    return Object.freeze({ ...config, profile: context.profile, tenantOrigin: context.tenantOrigin });
}
export const canonicalRemote = config => remoteContexts(config).every(c => c.profile.kind === 'canonical');
