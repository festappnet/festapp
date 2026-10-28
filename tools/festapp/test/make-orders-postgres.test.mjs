import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';

test('Make order-summary reads use real SQL scope and paginate 52 stable synthetic orders',
    { skip: !process.env.FESTAPP_MCP_TEST_DATABASE_URL }, async t => {
    const db = await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
    await db.query('BEGIN');
    t.after(async () => { await db.query('ROLLBACK'); await db.end(); });
    assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe, true);
    const f = await fixture(db, 1);
    const form = Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Make isolated SQL fixture',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id", [f.occasion])).rows[0].id);
    const ids = [];
    for (let i = 0; i < 52; i++) {
        const r = await db.query(`insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data,note_hidden)
            values($1,$2,'ordered',100,'CZK',next_order_sequence($1),generate_order_symbol(),
            '{"email":"synthetic@example.invalid","name":"Do not expose","tickets":[]}', 'PRIVATE_SQL_FIXTURE') returning id`, [f.occasion, form]);
        ids.push(Number(r.rows[0].id));
    }
    await db.query('SET LOCAL ROLE authenticated');
    const client = { rpc: async (name, args) => {
        await db.query('SAVEPOINT make_read');
        try {
            let query, values;
            if (name === 'get_operator_orders_v1') {
                query = 'select get_operator_orders_v1($1,$2,$3,$4,$5,$6,$7,$8) value';
                values = [args.p_occasion,args.p_organization,args.p_unit,args.p_limit,args.p_before,args.p_state,args.p_search,args.p_order];
            } else {
                assert.equal(name, 'get_operator_order_report_v1');
                query = 'select get_operator_order_report_v1($1,$2,$3) value';
                values = [args.p_occasion,args.p_organization,args.p_unit];
            }
            const data = (await db.query(query, values)).rows[0].value;
            await db.query('RELEASE SAVEPOINT make_read'); return { data, error: null };
        } catch (e) {
            await db.query('ROLLBACK TO SAVEPOINT make_read'); await db.query('RELEASE SAVEPOINT make_read');
            return { data: null, error: { code: e.code, status: e.code === '42501' ? 403 : 400 } };
        }
    } };
    let scope = { organizationId: f.org, unitId: f.unit };
    const owner = { root: '/tmp/festapp-make-sql-fixture', orderSummaryOnly: true,
        profile: { organizationId: f.org, tenantId: 'fixture', name: 'make-sql-fixture' },
        allowedOperations: ['orders.report','orders.list','orders.inspect'],
        authorized: action => action(client, { userId: f.actor }), delegatedContext: async () => scope };
    const ops = new Operations(owner);
    const invoke = (operation, args = {}) => ops.invoke(operation, { occasionId: f.occasion, ...args });
    const first = await invoke('orders.list', { limit: 50 }); assert.equal(first.ok, true, JSON.stringify(first)); assert.equal(first.data.orders.length, 50);
    const last = await invoke('orders.list', { limit: 50, before: first.data.nextCursor }); assert.equal(last.ok, true, JSON.stringify(last)); assert.equal(last.data.orders.length, 2); assert.equal(last.data.nextCursor, null);
    assert.deepEqual([...first.data.orders,...last.data.orders].map(r => r.id), ids.reverse());
    assert(!JSON.stringify(first).includes('PRIVATE_SQL_FIXTURE')); assert(!JSON.stringify(first).includes('synthetic@example.invalid'));
    const detail = await invoke('orders.inspect', { orderId: ids[0] }); assert.equal(detail.ok, true, JSON.stringify(detail)); assert.equal(detail.data.orders[0].id, ids[0]);
    const report = await invoke('orders.report'); assert.equal(report.ok, true, JSON.stringify(report)); assert.equal(report.data.report.schema_version, 1);
    scope = { organizationId: f.org, unitId: f.unit + 999999 };
    assert.equal((await invoke('orders.inspect', { orderId: ids[0] })).error.code, 'FORBIDDEN');
    scope = { organizationId: f.org + 999999, unitId: null };
    assert.equal((await invoke('orders.list')).error.code, 'FORBIDDEN');
    scope = { organizationId: f.org, unitId: f.unit };
    await db.query('RESET ROLE');
    await db.query('delete from occasion_users where "user"=$1', [f.actor]);
    await db.query('delete from unit_users where "user"=$1', [f.actor]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.equal((await invoke('orders.report')).error.code, 'FORBIDDEN');
});
