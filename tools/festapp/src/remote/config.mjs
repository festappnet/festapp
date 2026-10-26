import { check } from '../errors.mjs';
import { z } from 'zod';
import { parseProfile } from '../context/profile.mjs';

export { READ_SCOPE, CREATE_SCOPE, READ_OPERATIONS, MCP_PERMISSIONS, MCP_SCOPES, scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
import { READ_SCOPE, CREATE_SCOPE, MCP_SCOPES, validPermissions } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
export function verifyPermissions(raw, requested) {
    const parsed = z.array(z.enum(MCP_SCOPES)).max(MCP_SCOPES.length).safeParse(raw ?? []);
    check(parsed.success, 'FORBIDDEN');
    const permissions = [...new Set(parsed.data)];
    check(validPermissions(permissions) && permissions.every(p => requested.includes(p)), 'FORBIDDEN');
    return permissions;
}

export const DOMAIN_SCOPES = Object.freeze([READ_SCOPE, CREATE_SCOPE, ...MCP_SCOPES]);
export function clientAllowsScopes(config, clientId, scopes) {
    const client = config.clients.find(c => c.id === clientId);
    return Boolean(client && scopes?.every(s => ['openid', 'offline_access'].includes(s) ||
        (DOMAIN_SCOPES.includes(s) && (!client.allowedScopes || client.allowedScopes.includes(s)))));
}
const identifier = z.string().min(1).max(200);
const schema = z.strictObject({
    schemaVersion: z.literal(2),
    issuer: z.url(),
    profile: z.unknown(),
    tenantOrigin: z.url().optional(),
    regionalPortal: z.strictObject({ name: identifier, platform: identifier }).optional(),
    clients: z.array(z.strictObject({
        id: identifier,
        name: identifier,
        applicationType: z.enum(['web', 'native']).default('web'),
        redirectUris: z.array(z.url()).min(1).max(4),
        allowedScopes: z.array(z.enum(DOMAIN_SCOPES)).min(1).max(DOMAIN_SCOPES.length).optional(),
    })).min(1).max(10),

});

export function parseRemoteConfig(raw) {
    const config = schema.parse(raw);
    const profile = parseProfile(config.profile);
    const url = new URL(config.issuer);
    if (config.tenantOrigin) {
        const tenant = new URL(config.tenantOrigin);
        if (tenant.origin !== config.tenantOrigin || tenant.protocol !== 'https:')
            throw new Error('INVALID_TENANT_ORIGIN');
    }
    const local = profile.kind === 'disposable-local';
    const validOrigin = (u) => !u.username && !u.password && !u.search && !u.hash;
    if (!validOrigin(url) || url.pathname !== '/' ||
        (local ? url.protocol !== 'http:' || url.hostname !== '127.0.0.1' : url.protocol !== 'https:'))
        throw new Error('INVALID_REMOTE_ISSUER');
    if (new Set(config.clients.map(c => c.id)).size !== config.clients.length)
        throw new Error('DUPLICATE_REMOTE_IDENTITY');
    for (const client of config.clients) {
        if (client.allowedScopes && (!client.allowedScopes.includes(READ_SCOPE) ||
            new Set(client.allowedScopes).size !== client.allowedScopes.length ||
            !validPermissions(client.allowedScopes.filter(s => MCP_SCOPES.includes(s)))))
            throw new Error('INVALID_CLIENT_SCOPE_CEILING');
    }
    for (const client of config.clients) for (const uri of client.redirectUris) {
        const u = new URL(uri);
        const loopback = u.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(u.hostname);
        if (!validOrigin(u) || (client.applicationType === 'native'
            ? !loopback
            : u.protocol !== 'https:' && !(local && loopback)))
            throw new Error('INVALID_REMOTE_REDIRECT');
    }
    return Object.freeze({ ...config, profile, issuer: url.origin, resource: url.origin + '/mcp' });
}
