import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { createOccasion } from '../src/operations/occasion-create.mjs';
import { operatorAccess } from '../src/operations/access.mjs';

const connection = process.env.FESTAPP_MCP_TEST_DATABASE_URL;
test('real organizer rights, hidden creation, exact replay, future occasions and revoked rights',
    { skip: !connection }, async t => {
    const url = new URL(connection);
    assert.equal(url.hostname, '127.0.0.1');
    assert.equal(url.port, '55432');
    const { Client } = createRequire(new URL('../../../web_client/package.json', import.meta.url))('pg');
    const db = new Client({ connectionString: connection });
    await db.connect();
    t.after(async () => { await db.query('ROLLBACK'); await db.end(); });
    assert.equal((await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project,
        'festapp-db-tests-pg15');
    await db.query('BEGIN');
    await db.query(await readFile(new URL('../../../database/functions/others/get_operator_access_v1.sql', import.meta.url), 'utf8'));
    await db.query("select public.create_user_for_test('mcp-organizer-node','mcp-organizer-node@example.invalid')");
    const actor = (await db.query("select public.get_user_id('mcp-organizer-node') id")).rows[0].id;
    const org = Number((await db.query("insert into public.organizations(title,data) values('MCP organizer fixture','{}') returning id")).rows[0].id);
    const unit = Number((await db.query("insert into public.units(title,organization) values('MCP organizer fixture',$1) returning id", [org])).rows[0].id);
    const other = Number((await db.query("insert into public.units(title,organization) values('MCP excluded fixture',$1) returning id", [org])).rows[0].id);
    await db.query('update public.user_info set organization=$1 where id=$2', [org, actor]);
    await db.query('insert into public.unit_users(unit,"user",is_editor,is_manager) values($1,$2,true,true)', [unit, actor]);
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)", [actor]);
    await db.query('SET LOCAL ROLE authenticated');
    const client = { rpc: async (name, args) => {
        await db.query('SAVEPOINT rpc');
        try {
            let data;
            if (name === 'get_operator_access_v1') data = (await db.query('select public.get_operator_access_v1($1,$2,$3) value',
                [args.p_organization, args.p_unit, args.p_occasion])).rows[0].value;
            else {
                assert.equal(name, 'create_occasion_client_sync_v1');
                data = (await db.query('select public.create_occasion_client_sync_v1($1,$2) value',
                    [args.p_command_id, args.p_config])).rows[0].value;
            }
            await db.query('RELEASE SAVEPOINT rpc');
            return { data, error: null };
        } catch (error) {
            await db.query('ROLLBACK TO SAVEPOINT rpc');
            return { data: null, error: { code: error.code, status: error.code === '42501' ? 403 : 400 } };
        }
    } };
    const profile = { organizationId: org };
    const before = await operatorAccess(client, profile);
    assert.deepEqual(before.units.map(u => u.id), [unit]);
    const request = { commandId: randomUUID(), unitId: unit, title: 'Created through MCP',
        start: '2027-01-01T18:00:00Z', end: '2027-01-02T02:00:00Z', description: '' };
    const created = await createOccasion(client, profile, request);
    assert.equal(created.hidden, true);
    assert.equal(created.salesOpen, false);
    const replay = await createOccasion(client, profile, request);
    assert.equal(replay.occasionId, created.occasionId);
    assert.deepEqual(replay, created);
    await assert.rejects(createOccasion(client, profile, { ...request, title: 'Changed uncertain request' }));
    const after = await operatorAccess(client, profile, { unitId: unit, occasionId: created.occasionId });
    assert.deepEqual(after.occasions.map(o => o.id), [created.occasionId]);
    await assert.rejects(createOccasion(client, profile, { ...request, commandId: randomUUID(), unitId: other }), /FORBIDDEN/);
    await assert.rejects(operatorAccess(client, { organizationId: org + 999999 }), /FORBIDDEN/);
    await db.query('RESET ROLE');
    await db.query('update public.unit_users set is_editor=false,is_manager=false where unit=$1 and "user"=$2', [unit, actor]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.deepEqual((await operatorAccess(client, profile)).units, []);
    await db.query('RESET ROLE');
    await db.query('update public.unit_users set is_editor_view=true where unit=$1 and "user"=$2', [unit, actor]);
    await db.query('SET LOCAL ROLE authenticated');
    const viewer = await operatorAccess(client, profile);
    assert.equal(viewer.units[0].canCreateOccasions, false);
    assert(viewer.occasions.some(o => o.id === created.occasionId));
    await assert.rejects(createOccasion(client, profile, { ...request, commandId: randomUUID() }), /FORBIDDEN/);
});
