import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';

const options = { skip: !process.env.FESTAPP_MCP_TEST_DATABASE_URL };
const command = (f, old, next) => ({ resource_id: f.resource, resource_slot_id: f.slot,
    inventory_context_id: f.context, old_spot_id: old, new_spot_id: next });
const success = result => { assert.equal(result.ok, true, JSON.stringify(result)); return result.data; };

async function transaction(t) {
    const db = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    await db.query('BEGIN');
    t.after(async () => { await db.query('ROLLBACK'); await db.end(); });
    const f = await fixture(db, 2);
    const one = async (sql, values) => Number((await db.query(sql, values)).rows[0].id);
    f.other = await one('select id from occasions where organization=$1 and id<>$2 limit 1', [f.org, f.occasion]);
    f.pool = await one("insert into inventory_pools(occasion,title) values($1,'Pokoje') returning id", [f.occasion]);
    f.context = await one("insert into inventory_contexts(inventory_pool,title) values($1,'Sobota') returning id", [f.pool]);
    f.resource = await one("insert into resources(occasion,inventory_pool,title,capacity) values($1,$2,'Pokoj',2) returning id", [f.occasion, f.pool]);
    f.slot = await one("insert into resource_slots(resource,title) values($1,'Lůžko') returning id", [f.resource]);
    const spots = (await db.query("insert into eshop.spots(occasion,inventory_context,title) values($1,$2,'A'),($1,$2,'B'),($1,$2,'C') returning id", [f.occasion, f.context])).rows.map(r => Number(r.id));
    [f.a, f.b, f.c] = spots;
    await db.query('update eshop.spots set resource=$1,resource_slot=$2 where id=$3', [f.resource, f.slot, f.a]);
    f.secret = randomUUID();
    await db.query("update eshop.spots set secret=$1,secret_expiration_time=now()+interval '1 hour' where id=$2", [f.secret, f.c]);
    await db.query('SET LOCAL ROLE authenticated');
    const stats = { lose: false, receipts: [] };
    const owner = { root: '/tmp/inventory-assignment-fixture', profile: { organizationId: f.org, tenantId: 'fixture' },
        allowedOperations: ['inventory.spots.list', 'inventory.slots.list', 'inventory.assignments.save'],
        delegatedContext: async () => ({ organizationId: f.org, unitId: f.unit }),
        authorized: action => action({ rpc: async (name, args) => {
            await db.query('SAVEPOINT rpc');
            try {
                const prefix = [args.p_occasion, args.p_organization, args.p_unit];
                let data;
                if (name === 'manage_inventory_assignments') {
                    data = (await db.query('select manage_inventory_assignments($1,$2,$3,$4,$5) value', [...prefix, JSON.stringify(args.p_changes), args.p_command_id])).rows[0].value;
                    stats.receipts.push(data);
                } else if (name === 'get_inventory_spot_page') {
                    data = (await db.query('select get_inventory_spot_page($1,$2,$3,$4,$5,$6) value', [...prefix, args.p_pool, args.p_after, args.p_limit])).rows[0].value;
                } else {
                    assert.equal(name, 'get_inventory_resource_slot_page');
                    data = (await db.query('select get_inventory_resource_slot_page($1,$2,$3,$4,$5,$6) value', [...prefix, args.p_resource, args.p_after, args.p_limit])).rows[0].value;
                }
                await db.query('RELEASE SAVEPOINT rpc');
                if (name === 'manage_inventory_assignments' && stats.lose) { stats.lose = false; return { error: { status: 503 } }; }
                return { data, error: null };
            } catch (error) {
                t.diagnostic('SQL ' + error.code + ': ' + error.message);
                await db.query('ROLLBACK TO SAVEPOINT rpc'); await db.query('RELEASE SAVEPOINT rpc');
                return { error: { code: error.code, message: error.message, status: error.code === '42501' ? 403 : 400 } };
            }
        } }, { userId: f.actor }) };
    const ops = new Operations(owner);
    return { db, f, stats, invoke: (id, args) => ops.invoke(id, { occasionId: f.occasion, ...args }),
        save: (changes, commandId = randomUUID()) => ops.invoke('inventory.assignments.save', { occasionId: f.occasion, changes, commandId }) };
}

test('inventory assignments use the exact UI receipt after a lost response and reject stale or partial batches', options, async t => {
    const { db, f, stats, invoke, save } = await transaction(t);
    const changes = [command(f, f.a, f.b)], id = randomUUID();
    stats.lose = true;
    assert.equal((await save(changes, id)).ok, false);
    const applied = success(await save(changes, id));
    assert.equal(applied.changedCount, 1);
    assert.deepEqual(success(await save(changes, id)), applied);
    const ui = (await db.query('select update_spot_assignments_client_sync_v1($1,$2) value', [JSON.stringify(changes), id])).rows[0].value;
    const { sync, ...compact } = ui;
    assert.deepEqual(stats.receipts[0], compact);
    assert.equal(ui.mutation.commandId, id);
    assert.equal((await save(changes)).error.code, 'INVENTORY_ASSIGNMENT_CHANGED_RELOAD_REQUIRED');
    await db.query('RESET ROLE');
    await db.query("update eshop.spots set secret_expiration_time=now()-interval '1 hour' where id=$1", [f.c]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.equal((await save([command(f, f.b, f.a), command(f, null, f.c)])).error.code, 'INVENTORY_INTENTION_REJECTED');
    await db.query('RESET ROLE');
    await db.query("update eshop.spots set secret_expiration_time=now()+interval '1 hour' where id=$1", [f.c]);
    await db.query('SET LOCAL ROLE authenticated');
    const stored = success(await invoke('inventory.spots.list', { poolId: f.pool }));
    assert.equal(stored.spots.find(s => s.id === f.a).resourceId, null);
    assert.equal(stored.spots.find(s => s.id === f.b).resourceId, f.resource);
    assert.equal(stored.spots.find(s => s.id === f.c).held, true);
    assert(!JSON.stringify(stored).includes(f.secret));
    await db.query('RESET ROLE');
    assert.equal(Number((await db.query("select count(*) from client_mutation_receipts where actor_id=$1 and command_name='inventory.spots.assign'", [f.actor])).rows[0].count), 1);
    await db.query('update eshop.spots set resource=NULL,resource_slot=NULL where resource=$1', [f.resource]);
    await db.query('delete from resource_slots where resource=$1', [f.resource]);
    await db.query('delete from resources where id=$1', [f.resource]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.deepEqual(success(await save(changes, id)), applied, 'The original receipt remains valid after the target resource is deleted');
});

test('bounded stock reads and stored scope fences reject foreign resources and receipt replay', options, async t => {
    const { db, f, invoke, save } = await transaction(t);
    const first = success(await invoke('inventory.spots.list', { poolId: f.pool, limit: 1 }));
    assert.equal(first.spots.length, 1); assert.equal(first.nextCursor, f.a);
    const rest = success(await invoke('inventory.spots.list', { poolId: f.pool, after: first.nextCursor, limit: 100 }));
    assert.deepEqual(rest.spots.map(s => s.id), [f.b, f.c]); assert.equal(rest.nextCursor, null);
    assert.deepEqual(success(await invoke('inventory.slots.list', { resourceId: f.resource })).slots, [{ id: f.slot, resourceId: f.resource, title: 'Lůžko' }]);
    assert.equal((await invoke('inventory.spots.list', { occasionId: f.other, poolId: f.pool })).error.code, 'FORBIDDEN');
    assert.equal((await invoke('inventory.slots.list', { occasionId: f.other, resourceId: f.resource })).error.code, 'FORBIDDEN');
    const id = randomUUID(), changes = [command(f, f.a, f.b)];
    success(await save(changes, id));
    assert.equal((await invoke('inventory.assignments.save', { occasionId: f.other, changes, commandId: id })).error.code, 'FORBIDDEN');
    await db.query('RESET ROLE');
    await db.query('update unit_users set is_manager=false,is_editor=false,is_editor_view=false where unit=$1 and "user"=$2', [f.unit, f.actor]);
    await db.query('update occasion_users set is_manager=false,is_editor=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2', [f.occasion, f.actor]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.equal((await save(changes, id)).error.code, 'FORBIDDEN');
});

test('inventory delegation entry points preserve private helper and service-role restrictions', options, async t => {
    const { db } = await transaction(t);
    await db.query('RESET ROLE');
    for (const signature of ['get_inventory_spot_page(bigint,bigint,bigint,bigint,bigint,integer)',
        'get_inventory_resource_slot_page(bigint,bigint,bigint,bigint,bigint,integer)',
        'manage_inventory_assignments(bigint,bigint,bigint,jsonb,uuid)']) {
        assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') allowed", [signature])).rows[0].allowed, true);
        for (const role of ['anon', 'service_role'])
            assert.equal((await db.query('select has_function_privilege($1,$2,\'execute\') allowed', [role, signature])).rows[0].allowed, false);
    }
    assert.equal((await db.query("select has_function_privilege('authenticated','check_inventory_assignment_entities_internal(bigint,bigint[],bigint[])','execute') allowed")).rows[0].allowed, false);
});

test('concurrent UI and delegated processing of the same command retain receipt-before-parent lock order', options, async t => {
    // This fixture must commit so two ordinary sessions can observe it. The
    // canonical runtime lease drops the entire marked database after the batch.
    assert(process.env.FESTAPP_DB_RUN_ID, 'Run committed concurrency fixtures through automation/local_db/runtime.py exec');
    const admin = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    const ui = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    const mcp = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    t.after(async () => { for (const db of [ui, mcp, admin]) { await db.query('ROLLBACK'); await db.end(); } });
    await admin.query('BEGIN');
    const f = await fixture(admin, 1);
    const pool = Number((await admin.query("insert into inventory_pools(occasion,title) values($1,'Concurrent rooms') returning id", [f.occasion])).rows[0].id);
    const context = Number((await admin.query('insert into inventory_contexts(inventory_pool) values($1) returning id', [pool])).rows[0].id);
    const resource = Number((await admin.query("insert into resources(occasion,inventory_pool,capacity,title) values($1,$2,1,'Concurrent room') returning id", [f.occasion, pool])).rows[0].id);
    const spot = Number((await admin.query('insert into eshop.spots(occasion,inventory_context) values($1,$2) returning id', [f.occasion, context])).rows[0].id);
    await admin.query('COMMIT');
    const id = randomUUID(), changes = JSON.stringify([{ old_spot_id: null, new_spot_id: spot,
        resource_id: resource, resource_slot_id: null, inventory_context_id: context }]);
    for (const db of [ui, mcp]) {
        await db.query('BEGIN');
        await db.query("set local statement_timeout='5s'");
        await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)", [f.actor]);
    }
    await ui.query('SET LOCAL ROLE authenticated');
    await mcp.query('SET LOCAL ROLE authenticated');
    // A real parent-row barrier lets MCP enter first, then the ordinary UI
    // command contend for the same UUID. Neither production path is replaced.
    await admin.query('BEGIN');
    await admin.query('select id from resources where id=$1 for update', [resource]);
    const run = (db, sql, values) => db.query(sql, values).then(async result => {
        await db.query('COMMIT'); return { result };
    }, async error => { await db.query('ROLLBACK'); return { error }; });
    const waitForLock = async db => {
        for (let i = 0; i < 100; i++) {
            if ((await admin.query('select wait_event_type from pg_stat_activity where pid=$1', [db.processID])).rows[0]?.wait_event_type === 'Lock') return;
            await admin.query('select pg_stat_clear_snapshot()');
            await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.fail('Both real commands must reach the controlled lock contention');
    };
    const delegated = run(mcp, 'select manage_inventory_assignments($1,$2,$3,$4,$5) value', [f.occasion, f.org, f.unit, changes, id]);
    await waitForLock(mcp);
    const ordinary = run(ui, 'select update_spot_assignments_client_sync_v1($1,$2) value', [changes, id]);
    await waitForLock(ui);
    await admin.query('COMMIT');
    const [replay, applied] = await Promise.all([delegated, ordinary]);
    assert.equal(replay.error, undefined, replay.error?.message);
    assert.equal(applied.error, undefined, applied.error?.message);
    const { sync, ...compact } = applied.result.rows[0].value;
    assert.deepEqual(replay.result.rows[0].value, compact);
    assert.equal(Number((await admin.query('select count(*) from client_mutation_receipts where command_id=$1', [id])).rows[0].count), 1);
    assert.equal(Number((await admin.query('select resource from eshop.spots where id=$1', [spot])).rows[0].resource), resource);
});
