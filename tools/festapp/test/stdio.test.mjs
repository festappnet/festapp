import { createServer as createHttpServer } from 'node:http';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';
import { Client as LegacyClient } from 'mcp-sdk-legacy/client/index.js';
import { StdioClientTransport as LegacyStdioClientTransport } from 'mcp-sdk-legacy/client/stdio.js';
import { profile } from './fixture.mjs';
for (const modern of [true, false]) test(`real CLI subprocess interoperates over ${modern ? '2026-07-28' : 'legacy'} stdio without login tools or stdout noise`, async (t) => {
    const root = await mkdtemp(join(tmpdir(), 'festapp-stdio-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    await mkdir(join(root, 'profiles'));
    const endpoint = createHttpServer((_, response) => {
        response.end('{}');
    });
    await new Promise((resolve) => endpoint.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise((resolve) => endpoint.close(resolve)));
    const { binding, ...data } = profile(
        'http://127.0.0.1:' + endpoint.address().port,
    );
    await writeFile(
        join(root, 'profiles', 'fixture.json'),
        JSON.stringify(data),
    );
    const transport = new (modern ? StdioClientTransport : LegacyStdioClientTransport)({
        command: process.execPath,
        args: [
            fileURLToPath(new URL('../src/cli/main.mjs', import.meta.url)),
            'mcp',
            'serve',
            '--profile',
            'fixture',
        ],
        env: { ...process.env, FESTAPP_OPERATOR_HOME: root },
        stderr: 'pipe',
    });
    const client = new (modern ? Client : LegacyClient)({ name: 'stdio-fixture', version: '1' }, modern ? { versionNegotiation: { mode: { pin: '2026-07-28' } } } : {});
    await client.connect(transport);
    if (modern) assert.equal(client.getProtocolEra(), 'modern');
    t.after(() => client.close());
    const tools = await client.listTools();
    assert.equal(tools.tools.length, 4);
    assert(
        !tools.tools.some((tool) =>
            /login|execute|sql|shell|save/.test(tool.name),
        ),
    );
    const result = await client.callTool({
        name: 'festapp_context_inspect',
        arguments: { profile: 'other' },
    });
    assert.equal(result.isError, true);
});
