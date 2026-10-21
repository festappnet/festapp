import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(new URL('../../web_client/package.json', import.meta.url));
const connectionString = process.env.FESTAPP_AUTHORIZATION_POLICY_DATABASE_URL;
const source = readFileSync(new URL('../../database/functions/user_permissions/operation_policies.sql', import.meta.url), 'utf8');
const statement = source.match(/DO \$authorization_context_read_phase\$[\s\S]*?END \$authorization_context_read_phase\$;/)?.[0];
assert.ok(statement, 'The actual generated read-phase transition is required');

async function within(body) {
  const target = new URL(connectionString);
  assert.equal(target.hostname, '127.0.0.1');
  assert.ok(target.port);
  const {Client} = require('pg');
  const db = new Client({connectionString});
  await db.connect();
  try {
    assert.match((await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0].project, /^festapp[-_]/);
    assert.equal((await db.query('SHOW cron.launch_active_jobs')).rows[0]['cron.launch_active_jobs'], 'off');
    await db.query('BEGIN');
    await body(db);
  } finally {
    await db.query('ROLLBACK');
    await db.end();
  }
}
const options = {skip: !connectionString};
const policy = 'data_security_occasion_context_read';
const catalog = "SELECT polname,polcmd,polpermissive,polroles::text,pg_get_expr(polqual,polrelid) AS qual FROM pg_policy WHERE polrelid='public.occasions'::regclass ORDER BY polname";

test('installed read phase delegates to the canonical context operation', options, () => within(async db => {
  await db.query('ALTER POLICY data_security_occasion_context_read ON public.occasions USING(false)');
  await db.query(statement);
  const row = (await db.query(catalog)).rows.find(row => row.polname === policy);
  assert.match(row.qual, /can_read_occasion_context_row\(id\)/);
}));

test('deferred read phase preserves the existing policies and grants', options, () => within(async db => {
  await db.query("DELETE FROM supabase_migrations.schema_migrations WHERE version='20261018102000'");
  await db.query('DROP POLICY data_security_occasion_context_read ON public.occasions');
  const before = (await db.query(catalog)).rows;
  const acl = (await db.query("SELECT relacl::text FROM pg_class WHERE oid='public.occasions'::regclass")).rows;
  await db.query(statement);
  assert.deepEqual((await db.query(catalog)).rows, before);
  assert.deepEqual((await db.query("SELECT relacl::text FROM pg_class WHERE oid='public.occasions'::regclass")).rows, acl);
}));

test('recorded read phase with a missing policy is rejected', options, () => within(async db => {
  assert.equal((await db.query("SELECT count(*)::int n FROM supabase_migrations.schema_migrations WHERE version='20261018102000'")).rows[0].n, 1);
  await db.query('DROP POLICY data_security_occasion_context_read ON public.occasions');
  await assert.rejects(db.query(statement), /Read-ACL phase is recorded but its context policy is missing/);
}));

test('unexpected read-policy roles are rejected', options, () => within(async db => {
  await db.query('ALTER POLICY data_security_occasion_context_read ON public.occasions TO anon');
  await assert.rejects(db.query(statement), /Unexpected occasion context read-policy contract/);
}));
