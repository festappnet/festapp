import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, profile, reply } from './fixture.mjs';
import { parseProfile } from '../src/context/profile.mjs';
import { canonicalBackendProfileSha256 } from '../../../automation/lib/backend_activation_manifest.mjs';
import { request, receipt } from './layout-fixture.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { createServer } from '../src/mcp/server.mjs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
function canonicalProfile() {
    const { binding, ...value } = profile();
    Object.assign(value, {
        kind: 'canonical',
        backendOrigin: 'https://api.example.invalid',
        publicApiKey: 'sb_publishable_fixture',
        activationUrl: 'https://tenant.example.invalid/backend-activation.json',
    });
    value.canonicalProfileSha256 = canonicalBackendProfileSha256({
        tenantId: value.tenantId,
        canonicalOrigin: value.backendOrigin,
        canonicalAnonKey: value.publicApiKey,
        canonicalOrganizationId: value.organizationId,
    });
    return parseProfile(value);
}
test('verified canonical contract enables writes; rollback disables SDK exposure before admission', async (t) => {
    let ready = true,
        writes = 0;
    const f = await fixture(t, {
        profileValue: canonicalProfile(),
        fetchImpl: async (url, init) => {
            if (url.pathname.endsWith('/get_ticket_layout_write_contract_v1'))
                return reply({
                    family: 'ticket_layouts',
                    contractVersion: 1,
                    ready,
                });
            if (url.pathname.endsWith('/save_occasion_client_sync_v1')) {
                writes++;
                return reply(receipt(JSON.parse(init.body).p_command_id));
            }
        },
    });
    await f.owner.login('fixture@example.invalid', 'test');
    const ops = new Operations(f.owner);
    await ops.prepare();
    assert.equal(ops.catalog.length, 6);
    const server = createServer(ops),
        client = new Client({ name: 'readiness-fixture', version: '1' }),
        [a, b] = InMemoryTransport.createLinkedPair();
    await server.connect(a);
    await client.connect(b);
    t.after(async () => {
        await client.close();
        await server.close();
    });
    const saved = await client.callTool({
        name: 'festapp_ticket_layouts_save',
        arguments: request(f.owner.profile),
    });
    assert.equal(saved.structuredContent.data.status, 'applied');
    assert.equal(writes, 1);
    ready = false;
    const blocked = await client.callTool({
        name: 'festapp_ticket_layouts_save',
        arguments: request(f.owner.profile, { expectedVersion: 4 }),
    });
    assert.equal(blocked.structuredContent.error.code, 'FAMILY_NOT_READY');
    assert.equal(writes, 1);
    assert.equal((await client.listTools()).tools.length, 3);
});
for (const invalid of [
    null,
    { family: 'ticket_layouts', contractVersion: 2, ready: true },
    { family: 'ticket_layouts', contractVersion: 1, ready: false },
])
    test(`absent or unready backend contract keeps canonical read-only (${JSON.stringify(invalid)})`, async (t) => {
        const f = await fixture(t, {
            profileValue: canonicalProfile(),
            fetchImpl: async (url) =>
                url.pathname.endsWith('/get_ticket_layout_write_contract_v1')
                    ? reply(invalid, invalid ? 200 : 404)
                    : undefined,
        });
        await f.owner.login('fixture@example.invalid', 'test');
        const ops = new Operations(f.owner);
        await ops.prepare();
        assert.equal(ops.catalog.length, 3);
        assert.equal(
            (await ops.invoke('ticket_layouts.save', request(f.owner.profile)))
                .error.code,
            'FAMILY_NOT_READY',
        );
        assert(
            !f.calls.some((call) =>
                call.url.pathname.endsWith('/save_occasion_client_sync_v1'),
            ),
        );
    });
