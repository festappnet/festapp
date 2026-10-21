import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseProfile, digest } from '../src/context/profile.mjs';
import { canonicalBackendProfileSha256 } from '../../../automation/lib/backend_activation_manifest.mjs';
import { SessionOwner } from '../src/auth/session.mjs';
export const actor = '00000000-0000-4000-8000-000000000001';
const claims = {
    sub: actor,
    role: 'authenticated',
    aal: 'aal1',
    amr: [],
    exp: 4102444800,
    iat: 1700000000,
};
export const token =
    'eyJhbGciOiJIUzI1NiJ9.' +
    Buffer.from(JSON.stringify(claims)).toString('base64url') +
    '.fixture';
export const activation = JSON.stringify({
    schemaVersion: 1,
    tenantId: 'fixture',
    generation: 1,
    backend: 'canonical',
});
export function profile(origin = 'http://127.0.0.1:54321', organizationId = 1) {
    return parseProfile({
        schemaVersion: 1,
        name: 'fixture',
        kind: 'disposable-local',
        tenantId: 'fixture',
        backendOrigin: origin,
        publicApiKey: 'fixture-public',
        organizationId,
        activationUrl: origin + '/backend-activation.json',
        activationSha256: digest(activation),
        generation: 1,
        canonicalProfileSha256: canonicalBackendProfileSha256({
            tenantId: 'fixture',
            canonicalOrigin: origin,
            canonicalAnonKey: 'fixture-public',
            canonicalOrganizationId: organizationId,
        }),
    });
}
export const reply = (data, status = 200) =>
    new Response(JSON.stringify(data), {
        status,
        headers: { 'content-type': 'application/json' },
    });
export function memoryStore() {
    let value = null;
    return {
        read: async () => value,
        write: async (_, next) => {
            value = next;
        },
        remove: async () => {
            value = null;
        },
        value: () => value,
    };
}
export async function fixture(
    t,
    { fetchImpl, profileValue = profile(), userId = actor } = {},
) {
    const root = await mkdtemp(join(tmpdir(), 'festapp-mcp-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const calls = [];
    const store = memoryStore();
    let rotation = 0;
    const owner = new SessionOwner(profileValue, {
        root,
        store,
        fetchImpl: async (input, init) => {
            const url = new URL(typeof input === 'string' ? input : input.url);
            calls.push({ url, init });
            if (fetchImpl) {
                const response = await fetchImpl(url, init);
                if (response) return response;
            }
            if (url.pathname === '/backend-activation.json')
                return new Response(activation);
            if (url.pathname === '/auth/v1/token')
                return reply({
                    access_token:
                        'eyJhbGciOiJIUzI1NiJ9.' +
                        Buffer.from(
                            JSON.stringify({ ...claims, sub: userId }),
                        ).toString('base64url') +
                        '.fixture',
                    refresh_token: 'rotated-' + ++rotation,
                    expires_in: 3600,
                    token_type: 'bearer',
                    user: {
                        id: userId,
                        factors: [],
                        app_metadata: {},
                        user_metadata: {},
                    },
                });
            if (url.pathname === '/auth/v1/user')
                return reply({
                    id: userId,
                    factors: [],
                    app_metadata: {},
                    user_metadata: {},
                });
            if (url.pathname === '/rest/v1/rpc/get_operator_access_v1')
                return reply({ units: [{ id: 3, title: 'Fixture organizer', canCreateOccasions: true }],
                    occasions: [{ id: 7, title: 'Fixture occasion', unitId: 3, capabilities: { 'ticket_layouts.read': true } }] });
            if (url.pathname === '/rest/v1/user_info')
                return reply({
                    id: userId,
                    organization: profileValue.organizationId,
                });
            if (
                url.pathname ===
                '/rest/v1/rpc/get_ticket_layout_write_contract_v1'
            )
                return reply({
                    family: 'ticket_layouts',
                    contractVersion: 1,
                    ready: true,
                });
            if (
                ['/rest/v1/rpc/get_ticket_layout_for_authoring_v1',
                 '/rest/v1/rpc/get_delegated_ticket_layout_for_authoring_v1'].includes(url.pathname)
            )
                return reply({
                    occasion: 7,
                    aggregate_version: 3,
                    schemaVersion: 3,
                    appearance: {},
                    images: [],
                });
            throw new Error('Unexpected fixture endpoint');
        },
    });
    return { owner, store, calls };
}
