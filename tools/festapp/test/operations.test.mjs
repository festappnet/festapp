import { canonicalPreview } from './render-fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { fixture, reply, actor } from './fixture.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { createServer } from '../src/mcp/server.mjs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
test('SDK client sees only fixed schemas, shares CLI result, renders canonical PDF and reauthorizes resources', async (t) => {
    const generated = await canonicalPreview();
    const f = await fixture(t, {
        fetchImpl: async (url, init) => {
            if (url.pathname === '/functions/v1/preview-ticket-layout') {
                const body = JSON.parse(init.body);
                assert(!('ticketId' in body));
                assert(!('requestSecret' in body));
                return reply(generated[body.mode]);
            }
        },
    });
    await f.owner.login('fixture@example.invalid', 'test');
    const ops = new Operations(f.owner);
    await ops.prepare();
    const server = createServer(ops),
        client = new Client({ name: 'fixture', version: '1' });
    const [a, b] = InMemoryTransport.createLinkedPair();
    await server.connect(a);
    await client.connect(b);
    t.after(async () => {
        await client.close();
        await server.close();
    });
    const tools = await client.listTools();
    assert.deepEqual(
        tools.tools.map((tool) => tool.name),
        [
            'festapp_access_inspect',
            'festapp_context_inspect',
            'festapp_ticket_layouts_inspect',
            'festapp_ticket_layouts_preview',
            'festapp_ticket_layouts_save',
            'festapp_ticket_layouts_pending',
            'festapp_ticket_layouts_resume',
        ],
    );
    assert.equal(tools.tools.find(t => t.name === 'festapp_ticket_layouts_preview').annotations.readOnlyHint, false);
    const direct = await ops.invoke('context.inspect', {}),
        through = await client.callTool({
            name: 'festapp_context_inspect',
            arguments: {},
        });
    assert.deepEqual(through.structuredContent.data, direct.data);
    const inspected = await client.callTool({
        name: 'festapp_ticket_layouts_inspect',
        arguments: { occasionId: 7 },
    });
    assert(inspected.structuredContent.ok);
    assert(inspected.structuredContent.data.presets);
    assert(!JSON.stringify(inspected).includes('"font":'));
    const preview = await client.callTool({
        name: 'festapp_ticket_layouts_preview',
        arguments: { occasionId: 7, type: 'named' },
    });
    assert.equal(preview.isError, undefined);
    const image = preview.content.find((block) => block.type === 'image');
    assert(image);
    const png = Buffer.from(image.data, 'base64');
    assert.equal(png.subarray(1, 4).toString(), 'PNG');
    await writeFile('/tmp/festapp-mcp-e0-preview.png', png);
    const { draftFingerprint, pdf } = preview.structuredContent.data;
    assert.match(draftFingerprint, /^[a-f0-9]{64}$/);
    const artifact = await client.readResource({ uri: pdf.uri });
    assert.equal(
        Buffer.from(artifact.contents[0].blob, 'base64')
            .subarray(0, 5)
            .toString(),
        '%PDF-',
    );
    await f.owner.logout();
    await assert.rejects(client.readResource({ uri: pdf.uri }));
});
test('foreign occasion is denied before renderer invocation and backend errors are sanitized', async (t) => {
    const f = await fixture(t, {
        fetchImpl: async (url) =>
            url.pathname.includes('/rpc/')
                ? reply(
                      {
                          code: '42501',
                          message: 'secret SQL and customer data',
                      },
                      403,
                  )
                : undefined,
    });
    await f.owner.login('fixture@example.invalid', 'test');
    const ops = new Operations(f.owner);
    const result = await ops.invoke('ticket_layouts.preview', {
        occasionId: 8,
        type: 'named',
    });
    assert.equal(result.error.code, 'FORBIDDEN');
    assert(!JSON.stringify(result).includes('secret SQL'));
    assert(!f.calls.some((c) => c.url.pathname.includes('/functions/')));
});
test('strict input refuses endpoint, profile, real-ticket and oversized-layout injection', async (t) => {
    const f = await fixture(t);
    const ops = new Operations(f.owner);
    for (const extra of [
        { profile: 'production' },
        { endpoint: 'arbitrary' },
        { ticketId: 5 },
        { requestSecret: 'secret' },
    ]) {
        const result = await ops.invoke('ticket_layouts.preview', {
            occasionId: 7,
            type: 'named',
            ...extra,
        });
        assert.equal(result.error.code, 'INVALID_INPUT');
    }
    assert.equal(f.calls.length, 0);
    await f.owner.login('fixture@example.invalid', 'test');
    const huge = await ops.invoke('ticket_layouts.preview', {
        occasionId: 7,
        type: 'named',
        layout: { x: 'x'.repeat(40001) },
    });
    assert.equal(huge.error.code, 'INVALID_INPUT');
    assert(!f.calls.some((c) => c.url.pathname.includes('/functions/')));
});
test('preview artifact cannot cross authenticated users', async (t) => {
    const f = await fixture(t);
    await f.owner.login('fixture@example.invalid', 'test');
    const ops = new Operations(f.owner);
    const uri = ops.artifacts.put('a'.repeat(64), {
        userId: 'different-user',
        occasionId: 7,
        pdf: Buffer.from('%PDF-'),
    });
    await assert.rejects(ops.readArtifact(uri), { code: 'FORBIDDEN' });
});
