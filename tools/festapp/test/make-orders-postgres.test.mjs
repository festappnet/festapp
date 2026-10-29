import { readFile } from 'node:fs/promises';
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
    await db.query('SET LOCAL ROLE postgres');
    await db.query(await readFile(new URL('../../../supabase/migrations/20261029180000_operator_order_summaries.sql', import.meta.url), 'utf8').then(s=>s.replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'')));
    await db.query('RESET ROLE');
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
            if (name === 'get_operator_order_summaries_v1') {
                query = 'select get_operator_order_summaries_v1($1,$2,$3,$4,$5,$6,$7,$8) value';
                values = [args.p_occasion,args.p_organization,args.p_unit,args.p_limit,args.p_before,args.p_state,args.p_symbol,args.p_order];
            } else {
                assert.equal(name, 'get_operator_order_report_v1');
                query = 'select get_operator_order_report_v1($1,$2,$3) value';
                values = [args.p_occasion,args.p_organization,args.p_unit];
            }
            const data = (await db.query(query, values)).rows[0].value;
            if (name === 'get_operator_order_summaries_v1') {
                const raw = JSON.stringify(data);
                for (const forbidden of ['customer','revision','createdAt','note','responses','variableSymbol','synthetic@example.invalid','PRIVATE_SQL_FIXTURE']) assert(!raw.includes(forbidden), forbidden);
            }
            await db.query('RELEASE SAVEPOINT make_read'); return { data, error: null };
        } catch (e) {
            await db.query('ROLLBACK TO SAVEPOINT make_read'); await db.query('RELEASE SAVEPOINT make_read');
            return { data: null, error: { code: e.code, status: e.code === '42501' ? 403 : 400 } };
        }
    } };
    assert((await db.query("select 1 from pg_constraint where conrelid='eshop.orders'::regclass and conname='orders_order_symbol_key' and contype='u'")).rowCount);
    for (const role of ['anon','authenticated','service_role']) {
        const rpc = 'public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint)';
        assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,rpc])).rows[0].allowed,role==='authenticated');
        for (const helper of ['operator_order_facts_internal_v1(bigint)','operator_order_summary_internal_v1(bigint)','operator_order_snapshot_internal_v1(bigint,boolean)'])
            assert.equal((await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,'public.'+helper])).rows[0].allowed,false);
    }
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
    assert.equal((await invoke('orders.inspect', { orderId: 9007199254740000 })).error.code, 'FORBIDDEN');
    // A real stored payment and duplicate product relationships share the same
    // safe fact owner as full administration, without recomputing money in JS.
    await db.query('RESET ROLE');
    const payment = (await db.query("insert into eshop.payment_info(amount,paid,returned,currency_code,variable_symbol,payment_method) values(123.45,67.89,1.23,'CZK',98765,'bank') returning id")).rows[0].id;
    const chosen = ids.at(-1);
    await db.query('update eshop.orders set payment_info=$2 where id=$1',[chosen,payment]);
    const productType = (await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Summary fixture','entry') returning id",[f.occasion])).rows[0].id;
    const valid = (await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,'ordered',gen_random_uuid()::text) returning id",[f.occasion])).rows[0].id;
    const cancelled = (await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,'storno',gen_random_uuid()::text) returning id",[f.occasion])).rows[0].id;
    for (let i=0;i<2;i++) {
        const product = (await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code,maximum) values($1,$2,'Safe fact fixture',10,'CZK',100) returning id",[f.occasion,productType])).rows[0].id;
        for (const ticket of [valid,cancelled]) await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[chosen,product,ticket]);
    }
    const symbol = (await db.query('select order_symbol from eshop.orders where id=$1',[chosen])).rows[0].order_symbol;
    // More than four old contact-search pages precede the exact symbol.
    for (let i=0;i<210;i++) await db.query(`insert into eshop.orders(occasion,form,state,price,currency_code,order_sequence,order_symbol,data)
        values($1,$2,'ordered',100,'CZK',next_order_sequence($1),generate_order_symbol(),jsonb_build_object('email',$3::text))`,[f.occasion,form,symbol]);
    await db.query('SET LOCAL ROLE authenticated');
    const exact = await invoke('orders.list',{search:symbol,limit:1});
    assert.equal(exact.ok,true,JSON.stringify(exact)); assert.deepEqual(exact.data.orders.map(o=>o.id),[chosen]); assert.equal(exact.data.nextCursor,null);
    const full = (await db.query('select get_operator_orders_v1($1,$2,$3,25,null,null,null,$4) value',[f.occasion,f.org,f.unit,chosen])).rows[0].value.orders[0];
    const safe = exact.data.orders[0];
    for (const key of ['ticketCount','price','currency']) assert.equal(safe[key],full[key]);
    assert.deepEqual(safe.payment,{amount:full.payment.amount,paid:full.payment.paid,returned:full.payment.returned});
    assert.equal(safe.ticketCount,1);
    assert.equal(safe.payment.amount,'123.45'); assert.equal(safe.payment.paid,'67.89'); assert.equal(safe.payment.returned,'1.23');
    const contactOnly = await invoke('orders.list',{search:'ABCDEFGHIJ'}); assert.deepEqual(contactOnly.data.orders,[]);
    for (const args of [{p_symbol:'invalid'}, {p_order:chosen,p_state:'ordered'}, {p_order:chosen,p_before:chosen}]) {
        const bad = await client.rpc('get_operator_order_summaries_v1',{p_occasion:f.occasion,p_organization:f.org,p_unit:f.unit,p_limit:25,...args});
        assert.equal(bad.error.code,'22023');
    }
    await db.query('RESET ROLE');
    const foreign = await fixture(db,2);
    await db.query('SET LOCAL ROLE authenticated');
    assert.equal((await invoke('orders.inspect',{orderId:chosen})).error.code,'FORBIDDEN');
    await db.query('RESET ROLE');
    await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);
    assert.equal((await ops.invoke('orders.inspect',{occasionId:foreign.occasion,orderId:chosen})).error.code,'FORBIDDEN');
    await db.query('update occasions set unit=$2 where id=$1',[f.occasion,foreign.unit]);
    await db.query('SET LOCAL ROLE authenticated');
    assert.equal((await invoke('orders.list')).error.code,'FORBIDDEN');
    await db.query('RESET ROLE');await db.query('update occasions set unit=$2 where id=$1',[f.occasion,f.unit]);await db.query('SET LOCAL ROLE authenticated');
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
    assert.equal((await invoke('orders.list')).error.code, 'FORBIDDEN');
    assert.equal((await invoke('orders.inspect',{orderId:chosen})).error.code, 'FORBIDDEN');
});
