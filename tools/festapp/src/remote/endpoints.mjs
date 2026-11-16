import publicFacades from '../../../../packages/festapp_contracts/api-facades.json' with { type: 'json' };
import { clientPolicy, API_SUMMARY_OPERATIONS } from './client-policy.mjs';
import { z } from 'zod';
import { check } from '../errors.mjs';
import { READ_SCOPE, DELEGATED_OPERATIONS, scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

export const API_DATA_PROFILES = Object.freeze(['operator','order-summary']);
export const API_PROOF_PROFILES = Object.freeze(['bearer','dpop']);
export const apiProjectionDirectory = (endpointId, dataProfile, proofProfile = 'bearer') => endpointId +
    (dataProfile === 'operator' ? '' : '/profiles/order-summary') + (proofProfile === 'dpop' ? '/proofs/dpop' : '');

export const API_PREFIX = '/integrations/v1';
export const PUBLIC_API_FACADES = Object.freeze(publicFacades.map(facade => Object.freeze(facade)));
export const endpointSchema = z.strictObject({
    endpointId: z.enum(['global-api', 'regional-api']),
    publicBase: z.url(), resource: z.url(), issuer: z.url(),
    brand: z.enum(['Festapp', 'vstupenky.online']),
    profilePolicy: z.discriminatedUnion('type', [
        z.strictObject({ type: z.literal('selected') }),
        z.strictObject({ type: z.literal('fixed'), profileBinding: z.string().regex(/^[a-f0-9]{64}$/) }),
    ]),
    allowedClients: z.array(z.string().min(1).max(200)).min(1).max(10),
});
export const profiles = config => config.contexts ?? [{ profile: config.profile, tenantOrigin: config.tenantOrigin }];
export function normalizeEndpoints(config) {
    const endpoints = config.endpoints ?? [];
    check(!endpoints.length || config.schemaVersion === 3, 'API_CONFIG_VERSION_REQUIRED');
    check(new Set(endpoints.map(e => e.endpointId)).size === endpoints.length &&
        new Set(endpoints.map(e => e.resource)).size === endpoints.length &&
        new Set(endpoints.map(e => e.publicBase)).size === endpoints.length, 'DUPLICATE_API_ENDPOINT');
    for (const e of endpoints) {
        const base = new URL(e.publicBase);
        const published = PUBLIC_API_FACADES.find(f => f.endpointId === e.endpointId);
        check(e.publicBase === published.publicBase && e.resource === published.resource && e.brand === published.brand &&
            (config.issuer === published.issuer || profiles(config).every(c => c.profile.kind === 'disposable-local')), 'API_RELEASE_BINDING_MISMATCH');
        check(base.protocol === 'https:' && !base.username && !base.password && !base.search && !base.hash &&
            base.pathname === API_PREFIX && e.resource === base.origin + '/integrations' &&
            e.issuer === config.issuer && e.resource !== config.resource, 'INVALID_API_ENDPOINT');
        check(e.endpointId === 'regional-api' ? e.brand === 'vstupenky.online' && e.profilePolicy.type === 'fixed'
            : e.brand === 'Festapp' && e.profilePolicy.type === 'selected', 'INVALID_API_PROFILE_POLICY');
        if (e.profilePolicy.type === 'fixed') check(profiles(config).some(c => c.profile.binding === e.profilePolicy.profileBinding), 'INVALID_API_PROFILE_POLICY');
        check(e.allowedClients.every(id => config.clients.some(c => c.id === id)), 'UNKNOWN_API_CLIENT');
    }
    return Object.freeze(endpoints.map(e => Object.freeze(e)));
}
export function normalizeClient(client, config, endpoints) {
    const legacy = !client.transports;
    check(!(config.schemaVersion === 3 && legacy), 'EXPLICIT_CLIENT_POLICY_REQUIRED');
    const policy = { ...client,
        transports: client.transports ?? (client.id === 'festapp-make' ? ['legacy-make'] : ['mcp']),
        resources: client.resources ?? [config.resource],
        proofProfile: client.proofProfile ?? 'bearer',
        requirePar: client.requirePar ?? false,
        maxConsentDays: client.maxConsentDays ?? (client.transports?.includes('api') ? 7 : 365),
        tokenEndpointAuthMethod: client.tokenEndpointAuthMethod ?? 'none',
    };
    const api = policy.transports.includes('api');
    check(new Set(policy.transports).size === policy.transports.length && new Set(policy.resources).size === policy.resources.length, 'DUPLICATE_CLIENT_POLICY');
    if (client.allowedOperations) {
        const known = new Set(DELEGATED_OPERATIONS);
        check(new Set(client.allowedOperations).size === client.allowedOperations.length && client.allowedOperations.every(id => known.has(id)), 'INVALID_CLIENT_OPERATIONS');
        if (api) check(client.allowedOperations.every(id => scopesForOperation(id).every(scope => client.allowedScopes?.includes(scope))), 'INVALID_CLIENT_OPERATION_SCOPES');
    }
    if (api && client.dataProfile === 'order-summary') check(client.allowedOperations?.every(id =>
        API_SUMMARY_OPERATIONS.includes(id)) &&
        client.allowedScopes?.every(scope => [READ_SCOPE,'festapp:orders:read'].includes(scope)), 'INVALID_SUMMARY_CLIENT_POLICY');
    if (api && client.id === 'festapp-make') check(client.dataProfile === 'order-summary' && policy.proofProfile === 'bearer' &&
        policy.tokenEndpointAuthMethod === 'none' && client.redirectUris.length === 1 && client.redirectUris[0] === 'https://www.make.com/oauth/cb/app' &&
        policy.resources.some(resource => endpoints.some(e => e.endpointId === 'regional-api' && e.resource === resource)) &&
        policy.resources.every(resource => endpoints.some(e => e.endpointId === 'regional-api' && e.resource === resource) ||
            resource === config.resource && policy.transports.includes('legacy-make')), 'INVALID_MAKE_API_POLICY');
    if (api) check(config.schemaVersion === 3 && client.allowedScopes?.includes(READ_SCOPE) &&
        client.allowedOperations?.length && client.resources?.length && client.proofProfile && client.tokenEndpointAuthMethod,
        'EXPLICIT_API_POLICY_REQUIRED');
    for (const resource of policy.resources) {
        if (resource === config.resource) check(policy.transports.some(t => t !== 'api'), 'INVALID_CLIENT_RESOURCE');
        else check(api && endpoints.some(e => e.resource === resource && e.allowedClients.includes(client.id)), 'INVALID_CLIENT_RESOURCE');
    }
    if (policy.tokenEndpointAuthMethod === 'private_key_jwt') {
        check(client.applicationType === 'web' && client.jwks?.keys.every(k =>
            ['RSA', 'EC', 'OKP'].includes(k.kty) && typeof k.kid === 'string' && !['d', 'p', 'q', 'k'].some(key => key in k)), 'INVALID_CLIENT_KEYS');
    } else check(!client.jwks, 'UNEXPECTED_CLIENT_KEYS');
    return Object.freeze(policy);
}
export function resourceEndpoint(config, resource) {
    if (resource === config.resource) return { endpointId: 'mcp', resource, issuer: config.issuer,
        publicBase: config.issuer + '/mcp', profilePolicy: { type: 'selected' } };
    return config.endpoints?.find(e => e.resource === resource);
}
export function grantEndpoint(config, grant) {
    const resource = grant?.resource ?? config.resource;
    const endpoint = resourceEndpoint(config, resource);
    check(endpoint && (grant?.endpointId ? endpoint.endpointId === grant.endpointId : resource === config.resource), 'AUTHENTICATION_REQUIRED');
    if (endpoint.profilePolicy.type === 'fixed') check(grant.profileBinding === endpoint.profilePolicy.profileBinding, 'AUTHENTICATION_REQUIRED');
    return endpoint;
}
export function clientForResource(config, id, resource) {
    const client = clientPolicy(config, id);
    const endpoint = resourceEndpoint(config, resource);
    return client && endpoint && (client.resources ?? [config.resource]).includes(resource) &&
        (endpoint.endpointId === 'mcp' || endpoint.allowedClients.includes(id)) ? client : undefined;
}

/** The listener is private. The ingress strips incoming destination/forwarded
 * headers and supplies this exact tuple. Host alone never selects a tenant. */
export function ingressEndpoint(config, req) {
    const host = req.headers.host;
    const apiPath = req.path === API_PREFIX || req.path.startsWith(API_PREFIX + '/') || req.path === '/.well-known/oauth-protected-resource/integrations';
    if (!apiPath) return undefined;
    const endpoint = config.endpoints?.find(e => new URL(e.publicBase).host === host);
    check(endpoint && req.headers['x-festapp-endpoint'] === endpoint.endpointId &&
        req.headers['x-forwarded-proto'] === 'https' && req.headers['x-forwarded-host'] === host &&
        !req.headers.forwarded, 'INVALID_INGRESS');
    return endpoint;
}
