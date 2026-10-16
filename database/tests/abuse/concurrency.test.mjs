import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
const require = createRequire(new URL('../../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const connectionString = process.env.DATABASE_URL;
if (!connectionString || new URL(connectionString).hostname !== '127.0.0.1' || new URL(connectionString).port !== '55672') {
  throw new Error('Use the dedicated abuse disposable DB on 127.0.0.1:55672');
}
async function connect() { const c = new Client({ connectionString }); await c.connect(); return c; }

test('two real connections cannot consume the final create slot twice', async () => {
  const setup = await connect();
  const clients = await Promise.all([connect(), connect()]);
  let original;
  try {
    const { rows: [context] } = await setup.query(`SELECT ui.id AS actor,ui.organization AS org,uu.unit
      FROM public.user_info ui JOIN public.unit_users uu ON uu."user"=ui.id WHERE uu.is_manager LIMIT 1`);
    ({ rows: [original] } = await setup.query(`SELECT base_limit FROM public.abuse_policy_rules WHERE rule_key='occasion.create.actor.day'`));
    const { rows: [prior] } = await setup.query(`SELECT coalesce(sum(amount),0)::int AS used FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=$1`, [context.actor]);
    await setup.query(`UPDATE public.abuse_policy_rules SET base_limit=$1 WHERE rule_key='occasion.create.actor.day'`, [prior.used + 1]);
    const config = { unit: Number(context.unit), organization: Number(context.org), title: 'Concurrent admission fixture', start_time: new Date().toISOString(), end_time: new Date(Date.now() + 86400000).toISOString() };
    const attempt = async (client) => {
      await client.query('BEGIN');
      try {
        await client.query(`SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)`, [context.actor]);
        await client.query('SET LOCAL ROLE authenticated');
        const { rows: [row] } = await client.query('SELECT public.create_occasion_client_sync_v1(gen_random_uuid(),$1::jsonb) AS result', [JSON.stringify(config)]);
        await client.query('COMMIT');
        return row.result;
      } catch (e) { await client.query('ROLLBACK'); throw e; }
    };
    const results = await Promise.allSettled(clients.map(attempt));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1, JSON.stringify(results.map(r => r.status === 'rejected' ? { code: r.reason.code, message: r.reason.message } : 'applied')));
    assert.equal(results.filter(r => r.status === 'rejected' && r.reason.code === 'PT429').length, 1);
    const { rows: [usage] } = await setup.query(`SELECT sum(amount)::int AS n FROM public.abuse_budget_usage
      WHERE rule_key='occasion.create.actor.day' AND scope_id=$1`, [context.actor]);
    assert.equal(usage.n, prior.used + 1);
  } finally {
    if (original) await setup.query(`UPDATE public.abuse_policy_rules SET base_limit=$1 WHERE rule_key='occasion.create.actor.day'`, [original.base_limit]);
    await Promise.all([...clients, setup].map(c => c.end()));
  }
});

test('duplicate and draft finalize compete for the same remaining actor slot', async () => {
  const setup = await connect();
  const clients = await Promise.all([connect(), connect()]);
  let original;
  try {
    const { rows: [context] } = await setup.query(`SELECT ui.id AS actor,ui.organization AS org,uu.unit,
      (SELECT id FROM public.occasions WHERE title='Concurrent admission fixture' LIMIT 1) AS source,
      gen_random_uuid() AS draft FROM public.user_info ui JOIN public.unit_users uu ON uu."user"=ui.id WHERE uu.is_manager LIMIT 1`);
    await setup.query('BEGIN');
    await setup.query(`SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)`, [context.actor]);
    await setup.query('SET LOCAL ROLE authenticated');
    await setup.query('SELECT public.create_occasion_setup_draft($1,$2)', [context.draft, context.unit]);
    await setup.query(`SELECT public.save_occasion_setup_draft($1,1,jsonb_build_object('title','Concurrent finalization',
      'reviewConfirmed',true,'start',now(),'end',now()+interval '1 day','formEnabled',false),6)`, [context.draft]);
    await setup.query('COMMIT');
    ({ rows: [original] } = await setup.query(`SELECT base_limit FROM public.abuse_policy_rules WHERE rule_key='occasion.create.actor.day'`));
    const { rows: [before] } = await setup.query('SELECT count(*)::int AS n FROM public.occasions');
    const { rows: [prior] } = await setup.query(`SELECT coalesce(sum(amount),0)::int AS used FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=$1`, [context.actor]);
    await setup.query(`UPDATE public.abuse_policy_rules SET base_limit=$1 WHERE rule_key='occasion.create.actor.day'`, [prior.used + 1]);
    const results = await Promise.allSettled(clients.map(async (client, index) => {
      await client.query('BEGIN');
      try {
        await client.query(`SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)`, [context.actor]);
        await client.query('SET LOCAL ROLE authenticated');
        const result = index === 0
          ? await client.query('SELECT public.duplicate_occasion_client_sync_v1($1,gen_random_uuid())', [context.source])
          : await client.query('SELECT public.finalize_occasion_setup_draft($1,2,gen_random_uuid())', [context.draft]);
        await client.query('COMMIT');
        return result.rows[0];
      } catch (e) { await client.query('ROLLBACK'); throw e; }
    }));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1, JSON.stringify(results.map(r => r.status === 'rejected' ? { code: r.reason.code, message: r.reason.message } : 'applied')));
    assert.equal(results.filter(r => r.status === 'rejected' && r.reason.code === 'PT429').length, 1);
    const { rows: [after] } = await setup.query(`SELECT (SELECT count(*)::int FROM public.occasions) AS n,
      (SELECT sum(amount)::int FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=$1) AS used`, [context.actor]);
    assert.equal(after.n, before.n + 1);
    assert.equal(after.used, prior.used + 1);
  } finally {
    await setup.query('ROLLBACK');
    if (original) await setup.query(`UPDATE public.abuse_policy_rules SET base_limit=$1 WHERE rule_key='occasion.create.actor.day'`, [original.base_limit]);
    await Promise.all([...clients, setup].map(c => c.end()));
  }
});

test('live legacy Auth counters are adopted without resetting attempt budgets', async () => {
  const c = await connect();
  try {
    await c.query('BEGIN');
    await c.query(`CREATE TABLE public.password_reset_rate_limits(key_hash text PRIMARY KEY,window_started_at timestamptz,attempts integer);
      CREATE TABLE public.external_login_rate_limits(key_hash text PRIMARY KEY,window_start timestamptz,hits integer);
      INSERT INTO public.password_reset_rate_limits VALUES(repeat('a',64),now(),3);
      INSERT INTO public.external_login_rate_limits VALUES(repeat('b',64),now(),100)`);
    await c.query(await readFile(new URL('../../functions/abuse/auth.sql', import.meta.url), 'utf8'));
    await c.query(`SELECT set_config('request.jwt.claim.role','service_role',true)`);
    const { rows: [r] } = await c.query(`SELECT public.consume_auth_abuse_v1('reset.account',repeat('a',64)) AS reset,
      public.consume_auth_abuse_v1('google.global',repeat('b',64)) AS google`);
    assert.deepEqual(r, { reset: false, google: false });
    const { rows: [n] } = await c.query(`SELECT sum(amount)::int AS n FROM public.abuse_budget_usage
      WHERE rule_key='reset.account' AND scope_id=public.abuse_recipient_key_v1(repeat('a',64))`);
    assert.equal(n.n, 4);
  } finally { await c.query('ROLLBACK'); await c.end(); }
});
