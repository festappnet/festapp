import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fixture, reply, profile } from './fixture.mjs';
import { canonicalPreview } from './render-fixture.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { Client as McpClient } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createServer } from '../src/mcp/server.mjs';
const connection = process.env.FESTAPP_MCP_TEST_DATABASE_URL;
test(
    'MCP preview/save/replay/conflict uses the real canonical PostgreSQL owner as authenticated',
    { skip: !connection },
    async (t) => {
        const url = new URL(connection);
        assert.equal(url.hostname, '127.0.0.1');
        assert.equal(url.port, '55432');
        const pg = createRequire(
            new URL('../../../web_client/package.json', import.meta.url),
        )('pg');
        const db = new pg.Client({ connectionString: connection });
        await db.connect();
        t.after(async () => {
            await db.query('ROLLBACK');
            await db.end();
        });
        assert.equal(
            (
                await db.query(
                    'select project from festapp_test_support.disposable_environment',
                )
            ).rows[0].project,
            'festapp-db-tests-pg15',
        );
        await db.query('BEGIN');
        await db.query(
            "select public.create_user_for_test('mcp-e1-node','mcp-e1-node@example.invalid')",
        );
        const userId = (
            await db.query("select public.get_user_id('mcp-e1-node') id")
        ).rows[0].id;
        const org = Number(
            (
                await db.query(
                    "insert into public.organizations(title,data) values('MCP E1 fixture','{}') returning id",
                )
            ).rows[0].id,
        );
        const unit = Number(
            (
                await db.query(
                    "insert into public.units(title,organization) values('MCP E1 fixture',$1) returning id",
                    [org],
                )
            ).rows[0].id,
        );
        await db.query(
            'update public.user_info set organization=$1 where id=$2',
            [org, userId],
        );
        await db.query(
            'insert into public.unit_users(unit,"user",is_editor) values($1,$2,true)',
            [unit, userId],
        );
        const oc = Number(
            (
                await db.query(
                    `insert into public.occasions(title,link,organization,unit,start_time,end_time,features,data)
 values('Synthetic MCP Preview',gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day',
 '[{"code":"ticket","is_enabled":true,"show_hidden_note":true},{"code":"form","is_enabled":true}]','{"preserve":"settings"}') returning id`,
                    [org, unit],
                )
            ).rows[0].id,
        );
        await db.query(
            "select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",
            [userId],
        );
        await db.query('SET LOCAL ROLE authenticated');
        const rendered = await canonicalPreview();
        let loseResponse = true;
        const sent = [];
        const f = await fixture(t, {
            profileValue: profile('http://127.0.0.1:54321', org),
            userId,
            fetchImpl: async (url, init) => {
                if (url.pathname === '/functions/v1/preview-ticket-layout')
                    return reply(rendered[JSON.parse(init.body).mode]);
                if (!url.pathname.startsWith('/rest/v1/rpc/')) return;
                const body = JSON.parse(init.body);
                await db.query('SAVEPOINT mcp_rpc');
                try {
                    let data;
                    if (
                        url.pathname.endsWith(
                            '/get_ticket_layout_write_contract_v1',
                        )
                    )
                        data = (
                            await db.query(
                                'select public.get_ticket_layout_write_contract_v1() value',
                            )
                        ).rows[0].value;
                    else if (
                        url.pathname.endsWith(
                            '/get_ticket_layout_for_authoring_v1',
                        )
                    )
                        data = (
                            await db.query(
                                'select public.get_ticket_layout_for_authoring_v1($1) value',
                                [body.p_occasion],
                            )
                        ).rows[0].value;
                    else {
                        assert(
                            url.pathname.endsWith(
                                '/save_occasion_client_sync_v1',
                            ),
                        );
                        sent.push(body);
                        data = (
                            await db.query(
                                'select public.save_occasion_client_sync_v1($1,$2,$3,$4::jsonb) value',
                                [
                                    body.p_occasion,
                                    body.p_command_id,
                                    body.p_expected_version,
                                    JSON.stringify(body.p_config),
                                ],
                            )
                        ).rows[0].value;
                    }
                    await db.query('RELEASE SAVEPOINT mcp_rpc');
                    if (body.p_command_id && loseResponse) {
                        loseResponse = false;
                        throw new Error('lost after domain commit');
                    }
                    return reply(data);
                } catch (error) {
                    if (error.code) {
                        await db.query('ROLLBACK TO SAVEPOINT mcp_rpc');
                        await db.query('RELEASE SAVEPOINT mcp_rpc');
                        return reply(
                            {
                                code: error.code,
                                message: 'fixture domain rejection',
                            },
                            error.code === '42501' ? 403 : 400,
                        );
                    }
                    throw error;
                }
            },
        });
        await f.owner.login('fixture@example.invalid', 'test');
        const ops = new Operations(f.owner);
        await ops.prepare();
        const client = new McpClient({ name: 'E1-postgres', version: '1' }),
            server = createServer(ops),
            [a, b] = InMemoryTransport.createLinkedPair();
        await server.connect(a);
        await client.connect(b);
        t.after(async () => {
            await client.close();
            await server.close();
        });
        const preview = await client.callTool({
            name: 'festapp_ticket_layouts_preview',
            arguments: { occasionId: oc, type: 'named' },
        });
        assert.equal(preview.structuredContent.ok, true);
        const input = preview.structuredContent.data.saveRequest;
        assert.equal(input.expectedVersion, 0);
        assert.equal(input.expectedLayout, null);
        const lost = await client.callTool({
            name: 'festapp_ticket_layouts_save',
            arguments: input,
        });
        assert.equal(lost.isError, true);
        const pending = await client.callTool({
            name: 'festapp_ticket_layouts_pending',
            arguments: { occasionId: oc },
        });
        const intent = pending.structuredContent.data.intent;
        assert(intent);
        const replay = await client.callTool({
            name: 'festapp_ticket_layouts_resume',
            arguments: { occasionId: oc, commandId: intent.commandId },
        });
        assert.equal(replay.structuredContent.data.status, 'applied');
        // The canonical SQL owner replays its stored envelope verbatim, including
        // the original replayed flag. Verify identity/version/receipt instead.
        assert.equal(replay.structuredContent.data.commandId, intent.commandId);
        assert.equal(replay.structuredContent.data.version, 1);
        assert.deepEqual(sent[0], sent[1]);
        // Same reviewed baseline is stale after the first confirmed mutation, not rebased.
        const conflict = await client.callTool({
            name: 'festapp_ticket_layouts_save',
            arguments: input,
        });
        assert.equal(conflict.structuredContent.data.status, 'conflict');
        const saved = (
            await db.query(
                'select public.get_ticket_layout_for_authoring_v1($1) value',
                [oc],
            )
        ).rows[0].value;
        assert.deepEqual(saved.appearance.layout, input.nextLayout);
        assert.equal(Number(saved.aggregate_version), 1);
        await db.query('RESET ROLE');
        const stored = (
            await db.query(
                'select title,data,features from public.occasions where id=$1',
                [oc],
            )
        ).rows[0];
        assert.equal(stored.title, 'Synthetic MCP Preview');
        assert.deepEqual(stored.data, { preserve: 'settings' });
        assert.equal(
            stored.features.find((f) => f.code === 'ticket').show_hidden_note,
            true,
        );
        assert(stored.features.find((f) => f.code === 'form'));
        assert.equal(
            Number(
                (
                    await db.query(
                        'select count(*) count from public.client_mutation_receipts where command_id=$1',
                        [intent.commandId],
                    )
                ).rows[0].count,
            ),
            1,
        );
    },
);
