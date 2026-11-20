import test from 'node:test';
import { Provider } from 'oidc-provider';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { profile } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { DOMAIN_SCOPES, clientPolicy, clientAllowsScopes, validRedirect, allowsMetadataClient } from '../src/remote/client-policy.mjs';
import { inspectorConfiguration } from '../src/remote/inspector.mjs';
import { MCP_PERMISSIONS, MCP_SCOPES, READ_OPERATIONS, scopesForOperation, permissionsForConsent, validPermissions } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import { Operations } from '../src/operations/catalog.mjs';

function configuration(extra = {}) {
    const { binding, ...raw } = profile();
    return parseRemoteConfig({ schemaVersion: 2, issuer: 'http://127.0.0.1:3399', profile: raw,
        clients: [{ id: 'public-fixture', name: 'Public fixture', dataProfile: 'order-summary',
            redirectUris: ['https://public.fixture.test/callback'], allowedScopes: [READ_SCOPE] }], ...extra });
}

test('only public native registrations may use exact localhost HTTP callbacks', () => {
    for (const uri of ['http://localhost/callback', 'http://localhost:51789/callback', 'http://localhost:65535/callback']) {
        assert(!validRedirect(uri, 'native'));
        for (const local of [false, true]) assert(!validRedirect(uri, 'web', { local, allowLocalhost: true }));
        const client = { id: 'festapp-claude-code', name: 'Claude Code', applicationType: 'native', redirectUris: [uri] };
        const explicitPublic = { ...client, tokenEndpointAuthMethod: 'none' };
        assert.equal(configuration({ clients: [client] }).clients[0].tokenEndpointAuthMethod, 'none');
        assert.deepEqual(configuration({ clients: [explicitPublic] }).clients[0].redirectUris, [uri]);
        assert.throws(() => configuration({ clients: [{ ...client, tokenEndpointAuthMethod: 'private_key_jwt' }] }), /INVALID_CLIENT_KEYS/);
    }
    for (const uri of ['http://app.localhost/callback', 'http://localhost./callback', 'http://app.local/callback',
        'https://localhost/callback', 'http://user@localhost/callback', 'http://localhost/callback?q=1',
        'http://localhost/callback#fragment', 'http://localhost/callback#', 'http://localhost/callback?',
        'http://@localhost/callback', 'http://:@localhost/callback', 'http://localhost/path@other',
        'http://LOCALHOST/callback', 'HTTP://localhost/callback', 'http://localhost:80/callback',
        'http://localhost/a/../callback', 'http://localhost:051789/callback', 'http://localhost', 'http://localhost/call\\back']) {
        assert(!validRedirect(uri, 'native', { allowLocalhost: true }), uri);
        assert.throws(() => configuration({ clients: [{ id: 'invalid', name: 'Invalid', applicationType: 'native', redirectUris: [uri] }] }), uri);
    }
    // The configuration schema trims surrounding whitespace before the canonical check.
    assert(!validRedirect('http://localhost/callback\n', 'native', { allowLocalhost: true }));
    assert.deepEqual(configuration({ clients: [{ id: 'trimmed', name: 'Trimmed', applicationType: 'native',
        redirectUris: ['http://localhost/callback\n'] }] }).clients[0].redirectUris, ['http://localhost/callback']);
});

test('static web and IP loopback registrations keep their existing redirect URIs', () => {
    const clients = [
        { id: 'web', name: 'Web', redirectUris: ['https://WEB.fixture.test:443/callback@v2'] },
        { id: 'native', name: 'Native', applicationType: 'native',
            redirectUris: ['http://127.0.0.1:80/callback@v2', 'http://[::1]:51789/callback'] },
    ];
    assert.deepEqual(configuration({ clients }).clients.map(client => client.redirectUris),
        clients.map(client => client.redirectUris));
});

test('maintained provider matches registered localhost with any port and exact host/path', async () => {
    const provider = new Provider('https://issuer.fixture.test', { clients: [{ client_id: 'festapp-claude-code',
        application_type: 'native', token_endpoint_auth_method: 'none',
        redirect_uris: ['http://localhost/callback'], response_types: ['code'], grant_types: ['authorization_code'] }],
        features: { devInteractions: { enabled: false } } });
    const client = await provider.Client.find('festapp-claude-code');
    for (const port of ['', ':80', ':51789', ':65535']) assert(client.redirectUriAllowed(`http://localhost${port}/callback`));
    for (const uri of ['http://localhost:51789/other', 'http://localhost:51789/callback/',
        'http://app.localhost:51789/callback', 'http://localhost.:51789/callback', 'http://app.local:51789/callback',
        'http://127.0.0.1:51789/callback', 'https://localhost:51789/callback',
        'http://localhost:51789/callback?q=1', 'http://localhost:51789/callback#fragment'])
        assert(!client.redirectUriAllowed(uri), uri);
});

test('trusted metadata accepts only IP callbacks and keeps public-native scope ceilings', () => {
    const config = configuration({ clientMetadataDocuments: { allowedOrigins: ['https://desktop.fixture.test'],
        dataProfile: 'operator', allowedScopes: [READ_SCOPE] } });
    const client = { clientId: 'https://desktop.fixture.test/client.json', applicationType: 'native',
        tokenEndpointAuthMethod: 'none', responseTypes: ['code'], grantTypes: ['authorization_code'],
        redirectUris: ['http://127.0.0.1/callback'], scope: READ_SCOPE };
    assert(allowsMetadataClient(config, client));
    assert(allowsMetadataClient(config, { ...client, redirectUris: ['http://127.0.0.1:80/callback@v2'] }));
    assert(allowsMetadataClient(config, { ...client, redirectUris: ['http://[::1]:51789/callback'] }));
    for (const uri of ['http://localhost/callback', 'http://localhost:51789/callback'])
        assert(!allowsMetadataClient(config, { ...client, redirectUris: [uri] }), uri);
    assert(!allowsMetadataClient(config, { ...client, redirectUris: ['http://127.0.0.1/callback', 'http://localhost/callback'] }));
    assert(!allowsMetadataClient(config, { ...client, tokenEndpointAuthMethod: 'private_key_jwt' }));
    assert(!allowsMetadataClient(config, { ...client, scope: READ_SCOPE + ' festapp:forms:read' }));
});

test('consent presets only narrow requested functions and classify every read as domain read-only', () => {
    assert.deepEqual(permissionsForConsent(MCP_SCOPES), MCP_SCOPES);
    assert.deepEqual(permissionsForConsent(MCP_SCOPES, 'basic'), []);
    const reads = permissionsForConsent(MCP_SCOPES, 'read-only');
    assert(reads.length > 0 && reads.length < MCP_SCOPES.length);
    assert(validPermissions(reads));
    const ids = [...READ_OPERATIONS, 'occasions.create', ...Object.values(MCP_PERMISSIONS).flatMap(p => p.operations)];
    const ops = new Operations({ root: '/consent-contract-only', allowedOperations: ids });
    ops.setWriteReady(true);
    const catalog = new Map(ops.catalog.map(tool => [tool.id, tool]));
    for (const scope of reads) for (const operation of MCP_PERMISSIONS[scope].operations)
        assert.equal(catalog.get(operation).domainReadOnly, true, operation);
    assert.deepEqual(permissionsForConsent(['festapp:orders:read'], 'read-only'), ['festapp:orders:read']);
    assert.throws(() => permissionsForConsent(MCP_SCOPES, 'arbitrary'));
    assert.throws(() => permissionsForConsent(['unknown'], 'basic'));
});

test('Inspector setup CLI emits only public configuration and never edits its input', async t => {
    const root = await mkdtemp(join(tmpdir(), 'festapp-inspector-config-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const { binding, ...raw } = profile();
    const input = JSON.stringify({ schemaVersion: 2, issuer: 'http://127.0.0.1:3399', profile: raw,
        clients: [{ id: 'existing', name: 'Existing client', redirectUris: ['https://existing.fixture.test/callback'] }] });
    const path = join(root, 'config.json');
    await writeFile(path, input, { mode: 0o600 });
    const { stdout } = await promisify(execFile)(process.execPath,
        [fileURLToPath(new URL('../src/remote/main.mjs', import.meta.url)), 'client', 'inspector', path, '--origin', 'http://127.0.0.1:6274'], { cwd: root });
    const output = JSON.parse(stdout);
    assert.equal(output.registration.id, 'festapp-inspector');
    assert.equal(output.inspector.mcpServers.festapp.oauth.scopes.split(' ').length, DOMAIN_SCOPES.length);
    assert(!stdout.includes('fixture-public'));
    assert.equal(await readFile(path, 'utf8'), input);
});

test('general Inspector configuration exposes every registered operation without an artificial client ceiling', async () => {
    const config = configuration();
    const before = JSON.stringify(config);
    const setup = inspectorConfiguration(config, 'http://127.0.0.1:6274');
    assert.equal(JSON.stringify(config), before);
    assert.deepEqual(setup.registration.redirectUris, ['http://127.0.0.1:6274/oauth/callback']);
    assert.equal(setup.registration.allowedScopes, undefined);
    assert.equal(setup.inspector.mcpServers.festapp.url, config.resource);
    const scopes = setup.inspector.mcpServers.festapp.oauth.scopes.split(' ');
    assert.deepEqual(new Set(scopes), new Set(DOMAIN_SCOPES));
    const general = { ...config, clients: [...config.clients, setup.registration] };
    const ids = [...READ_OPERATIONS, 'occasions.create', ...Object.values(MCP_PERMISSIONS).flatMap(p => p.operations)];
    assert(ids.every(id => clientAllowsScopes(general, setup.registration.id, scopesForOperation(id))));
    const operations = new Operations({ root: '/catalog-only', allowedOperations: ids });
    operations.setWriteReady(true);
    const catalog = operations.catalog;
    assert.equal(catalog.length, new Set(ids).size);
    const inventory = JSON.parse(await readFile(new URL('../../../docs/reports/admin-capabilities-2026-10-23.json', import.meta.url)));
    assert.deepEqual(inventory.actions.filter(a => !a.mcp.length).map(a => a.id), ['action-003', 'action-004'],
        'Only account connection management and Google login stay outside occasion MCP operations');
    for (const action of inventory.actions) for (const id of action.mcp)
        assert(catalog.some(d => d.id === id), `Administration action lacks an MCP operation: ${action.id} / ${id}`);
    assert.equal(clientAllowsScopes(general, 'public-fixture', ['festapp:forms:write']), false);
});

test('Inspector origin must exactly match a literal loopback HTTP origin', () => {
    for (const origin of ['http://localhost:6274', 'https://127.0.0.1:6274', 'http://127.0.0.1:6274/path',
        'http://127.0.0.1:6274/', 'http://user@127.0.0.1:6274', 'http://127.0.0.1:6274?x=1', 'not-a-url'])
        assert.throws(() => inspectorConfiguration(configuration(), origin), /INVALID_INSPECTOR_ORIGIN/);
    assert.equal(inspectorConfiguration(configuration(), 'http://[::1]:6274').registration.redirectUris[0], 'http://[::1]:6274/oauth/callback');
});

test('native metadata policy supports the full catalog, explicit ceilings and static precedence', () => {
    const id = 'https://desktop.fixture.test/client.json';
    const metadata = { allowedOrigins: ['https://desktop.fixture.test'], dataProfile: 'operator' };
    const config = configuration({ clientMetadataDocuments: metadata });
    assert(clientAllowsScopes(config, id, DOMAIN_SCOPES));
    assert.equal(clientPolicy(config, id).applicationType, 'native');
    for (const candidate of ['https://other.fixture.test/client.json', 'https://desktop.fixture.test/',
        'https://user@desktop.fixture.test/client.json', 'https://desktop.fixture.test/client.json#fragment',
        'https://desktop.fixture.test/client.json\n', 'http://desktop.fixture.test/client.json'])
        assert.equal(clientPolicy(config, candidate), undefined);
    config.clientMetadataDocuments.allowedScopes = [READ_SCOPE];
    assert(!clientAllowsScopes(config, id, ['festapp:forms:read']));
    config.clients.push({ id, name: 'Static registration', dataProfile: 'order-summary', allowedScopes: [READ_SCOPE] });
    assert.equal(clientPolicy(config, id).dataProfile, 'order-summary');
    config.clientMetadataDocuments.allowedOrigins.length = 0;
    assert(clientPolicy(config, id)); // Removing metadata trust cannot override a static registration.
});

test('invalid trust origins and invalid dependency ceilings cannot activate metadata discovery', () => {
    for (const origin of ['http://desktop.fixture.test', 'https://desktop.fixture.test/path', 'https://127.0.0.1',
        'https://[::1]', 'https://localhost', 'https://internal.local', 'https://user@desktop.fixture.test'])
        assert.throws(() => configuration({ clientMetadataDocuments: { allowedOrigins: [origin], dataProfile: 'operator' } }));
    for (const policy of [{ allowedOrigins: ['https://desktop.fixture.test', 'https://desktop.fixture.test'], dataProfile: 'operator' },
        { allowedOrigins: ['https://desktop.fixture.test'], dataProfile: 'operator', allowedScopes: [READ_SCOPE, 'festapp:forms:write'] },
        { allowedOrigins: ['https://desktop.fixture.test'] }])
        assert.throws(() => configuration({ clientMetadataDocuments: policy }));
});
