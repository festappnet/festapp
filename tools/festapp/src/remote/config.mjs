import { z } from 'zod';
import { parseProfile } from '../context/profile.mjs';

export const READ_SCOPE = 'festapp:ticket-layouts:read';
export const CREATE_SCOPE = 'festapp:occasions:create';
export const READ_OPERATIONS = Object.freeze(['context.inspect', 'access.inspect', 'ticket_layouts.inspect']);
const identifier = z.string().min(1).max(200);
const schema = z.strictObject({
    schemaVersion: z.literal(2),
    issuer: z.url(),
    profile: z.unknown(),
    tenantOrigin: z.url().optional(),
    clients: z.array(z.strictObject({
        id: identifier,
        name: identifier,
        applicationType: z.enum(['web', 'native']).default('web'),
        redirectUris: z.array(z.url()).min(1).max(4),
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
