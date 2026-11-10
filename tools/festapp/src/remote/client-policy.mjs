import { isIP } from 'node:net';
import { DOMAIN_SCOPES, READ_SCOPE, MCP_SCOPES, validPermissions } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

export { DOMAIN_SCOPES } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

export function validScopeCeiling(scopes) {
    return scopes.includes(READ_SCOPE) && new Set(scopes).size === scopes.length &&
        scopes.every(s => DOMAIN_SCOPES.includes(s)) && validPermissions(scopes.filter(s => MCP_SCOPES.includes(s)));
}

export function validRedirect(uri, applicationType, local = false) {
    let u;
    try { u = new URL(uri); } catch { return false; }
    if (u.username || u.password || u.search || u.hash || /[\s\\]/u.test(uri)) return false;
    const loopback = u.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(u.hostname);
    return applicationType === 'native' ? loopback : u.protocol === 'https:' || (local && loopback);
}

export function validMetadataOrigin(origin) {
    let u;
    try { u = new URL(origin); } catch { return false; }
    return u.protocol === 'https:' && u.origin === origin && !isIP(u.hostname.replace(/^\[|\]$/g, '')) &&
        u.hostname !== 'localhost' && !u.hostname.endsWith('.localhost') && !u.hostname.endsWith('.local');
}

/** The SDK validates metadata identity, fetch safety, caching and exact callbacks.
 * This policy alone owns Festapp's trust, data projection and scope ceiling.
 * Resolve it again on every grant use, including after configuration changes. */
export function clientPolicy(config, clientId) {
    const registered = config.clients.find(c => c.id === clientId);
    if (registered) return registered;
    const policy = config.clientMetadataDocuments;
    if (!policy || typeof clientId !== 'string' || clientId.length > 200 || /[\s\\]/u.test(clientId)) return undefined;
    let url;
    try { url = new URL(clientId); } catch { return undefined; }
    if (url.protocol !== 'https:' || url.username || url.password || url.hash || url.pathname === '/' ||
        !policy.allowedOrigins.includes(url.origin)) return undefined;
    return { id: clientId, name: clientId, applicationType: 'native',
        dataProfile: policy.dataProfile, allowedScopes: policy.allowedScopes };
}

export function clientAllowsScopes(config, clientId, scopes) {
    const client = clientPolicy(config, clientId);
    return Boolean(client && scopes?.every(s => ['openid', 'offline_access'].includes(s) ||
        (DOMAIN_SCOPES.includes(s) && (!client.allowedScopes || client.allowedScopes.includes(s)))));
}

export function allowsMetadataFetch(config, clientId) {
    return !config.clients.some(c => c.id === clientId) && Boolean(clientPolicy(config, clientId));
}

export function allowsMetadataClient(config, client) {
    return allowsMetadataFetch(config, client.clientId) && client.applicationType === 'native' &&
        client.tokenEndpointAuthMethod === 'none' && client.responseTypes?.length === 1 && client.responseTypes[0] === 'code' &&
        client.grantTypes?.includes('authorization_code') && client.grantTypes.every(t => ['authorization_code', 'refresh_token'].includes(t)) &&
        client.redirectUris?.length > 0 && client.redirectUris.length <= 4 &&
        client.redirectUris.every(uri => validRedirect(uri, 'native')) &&
        (!client.scope || clientAllowsScopes(config, client.clientId, client.scope.split(' ')));
}
