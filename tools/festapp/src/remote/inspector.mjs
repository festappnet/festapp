import { check } from '../errors.mjs';
import { DOMAIN_SCOPES, validRedirect } from './client-policy.mjs';

/** Configuration output only. Does not register clients, log in or call tools. */
export function inspectorConfiguration(config, origin) {
    let url;
    try { url = new URL(origin); } catch { check(false, 'INVALID_INSPECTOR_ORIGIN'); }
    check(url.origin === origin && validRedirect(origin + '/oauth/callback', 'native'), 'INVALID_INSPECTOR_ORIGIN');
    const registration = { id: 'festapp-inspector', name: 'MCP Inspector', applicationType: 'native',
        dataProfile: 'operator', redirectUris: [origin + '/oauth/callback'] };
    return { registration, inspector: { mcpServers: { festapp: {
        type: 'streamable-http', url: config.resource,
        oauth: { clientId: registration.id, scopes: DOMAIN_SCOPES.join(' '), requestRefreshToken: true },
    } } } };
}
