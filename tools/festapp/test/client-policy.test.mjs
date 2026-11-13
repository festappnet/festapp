import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { profile } from './fixture.mjs';
import { parseRemoteConfig, READ_SCOPE } from '../src/remote/config.mjs';
import { DOMAIN_SCOPES, clientPolicy, clientAllowsScopes } from '../src/remote/client-policy.mjs';
import { inspectorConfiguration } from '../src/remote/inspector.mjs';
import { MCP_PERMISSIONS, MCP_SCOPES, READ_OPERATIONS, scopesForOperation, permissionsForConsent, validPermissions } from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import { Operations } from '../src/operations/catalog.mjs';

function configuration(extra = {}) {
    const { binding, ...raw } = profile();
    return parseRemoteConfig({ schemaVersion: 2, issuer: 'http://127.0.0.1:3399', profile: raw,
        clients: [{ id: 'public-fixture', name: 'Public fixture', dataProfile: 'order-summary',
            redirectUris: ['https://public.fixture.test/callback'], allowedScopes: [READ_SCOPE] }], ...extra });
}

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
