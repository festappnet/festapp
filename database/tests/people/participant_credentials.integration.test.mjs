// Real password login against an isolated GoTrue attached to the same disposable DB.
// Never run against production or an existing user's Auth server.
import assert from 'node:assert/strict';
import { randomInt, randomUUID, createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import test from 'node:test';
import { assertDisposableDatabase, assertLocalDatabaseUrl } from '../../../web_client/tests/database/disposable_database.js';
const require = createRequire(new URL('../../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const enabled = process.env.FESTAPP_ACCESS_AUTH_URL;

test('participant credentials remain reusable passwords, with atomic queue rollback and resend', { skip: !enabled }, async () => {
  assertLocalDatabaseUrl(process.env.DATABASE_URL);
  const origin = new URL(enabled);
  assert.ok(['127.0.0.1', 'localhost'].includes(origin.hostname));
  assert.equal(origin.protocol, 'http:');
  const db = new Client({ connectionString: process.env.DATABASE_URL });
  await db.connect();
  const stager = new Client({ connectionString: process.env.DATABASE_URL });
  await stager.connect();
  await stager.query("SELECT set_config('request.jwt.claim.role','service_role',false)");
  let organization;
  const users = [];
  let occasion, unit;
  const password = () => String(randomInt(1000000)).padStart(6, '0');
  const login = async (email, credential, expected = 200) => {
    const response = await fetch(new URL('/token?grant_type=password', origin), {
      signal: AbortSignal.timeout(10000), method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: credential }),
    });
    const result = await response.json();
    assert.equal(response.status, expected, `password login returned ${response.status}`);
    if (expected === 200) assert.ok(result.access_token && result.user?.id);
    return result;
  };
  try {
    await assertDisposableDatabase(db);
    const health = await fetch(new URL('/health', origin));
    assert.equal(health.status, 200);
    ({ rows: [{ id: organization }] } = await db.query("INSERT INTO public.organizations(title) VALUES('Disposable credential contract') RETURNING id"));
    ({ rows: [{ id: unit }] } = await db.query("INSERT INTO public.units(title,organization) VALUES('Disposable credential contract',$1) RETURNING id", [organization]));
    ({ rows: [{ id: occasion }] } = await db.query("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Disposable credential contract',$1,$2,$3,now(),now()+interval '1 day') RETURNING id", [organization, unit, randomUUID()]));
    for (const name of ['manager', 'new', 'existing']) {
      const { rows: [{ id }] } = await db.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id',
        [organization, `${name}-${randomUUID()}@example.invalid`, password(), '{}']);
      users.push(id);
      await db.query('INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES($1,$2,$3)', [occasion, id, name === 'manager']);
    }
    await db.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)", [users[0]]);
    for (const recipient of users.slice(1)) {
      const { rows: [{ email }] } = await db.query('SELECT email FROM auth.users WHERE id=$1', [recipient]);
      const credential = password();
      const dedupe = `credential-contract:${randomUUID()}`;
      const enqueue = async (value, key, sealed = { sealed: 'disposable fixture' }) => {
        const hex = createHash('md5').update(key).digest('hex');
        const commandId = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
        const request = { scope: { type: 'occasion', id: occasion }, operation: 'send_invitation', communication: 'participant_credentials', userId: recipient };
        const { rows: [{ preview }] } = await db.query('SELECT public.preview_member_access($1,$2) preview', [commandId, request]);
        if (preview.replay) return { message_id: preview.replay.data.communication.messageId };
        const { rows: [{ preparation }] } = await stager.query('SELECT public.stage_member_access_email($1,$2,$3,$4,$5,NULL,$6) preparation',
          [users[0], commandId, preview.intentHash, preview.previewHash, { p_sealed: sealed, p_content_hash: 'a'.repeat(64) }, value]);
        const { rows: [{ result }] } = await db.query('SELECT public.manage_member_access($1,$2,$3) result', [commandId, request, preparation]);
        return { message_id: result.data.communication.messageId };
      };
      await db.query('SET ROLE authenticated');
      const first = await enqueue(credential, dedupe);
      const replay = await enqueue(password(), dedupe);
      assert.equal(first.message_id, replay.message_id);
      await db.query('RESET ROLE');
      await login(email, credential);
      await login(email, credential); // A password is not consumed on use.
      await db.query("UPDATE public.email_messages SET expires_at=now()-interval '1 second',workflow_state='expired' WHERE message_id=$1", [first.message_id]);
      await login(email, credential); // Message expiry does not expire a password.
      await db.query('SET ROLE authenticated');
      await assert.rejects(enqueue(password(), `credential-failure:${randomUUID()}`, { sealed: 'x'.repeat(3 * 1024 * 1024) }));
      await db.query('RESET ROLE');
      await login(email, credential); // Enqueue failure rolls back password transition.
      // Model a resend after the recipient burst window, within this fixture only.
      await db.query("DELETE FROM public.abuse_budget_usage WHERE rule_key LIKE 'email.auth.recipient.%' AND scope_id=public.abuse_recipient_key_v1(public.get_user_delivery_email($1))", [recipient]);
      const nextCredential = password();
      await db.query('SET ROLE authenticated');
      const next = await enqueue(nextCredential, `credential-resend:${randomUUID()}`);
      await db.query('RESET ROLE');
      assert.notEqual(next.message_id, first.message_id);
      await login(email, nextCredential);
      await login(email, credential, 400);
    }
    const { rows: [{ count }] } = await db.query('SELECT count(*) FROM public.sign_in_codes WHERE user_id=ANY($1::uuid[])', [users]);
    assert.equal(count, '0');
  } finally {
    try {
    await db.query('RESET ROLE');
    if (organization) {
      await db.query('DELETE FROM public.client_mutation_receipts WHERE occasion=$1', [occasion]);
      await db.query('DELETE FROM public.email_messages WHERE organization=$1', [organization]);
      await db.query('DELETE FROM public.occasion_users WHERE occasion=$1', [occasion]);
      await db.query('DELETE FROM public.occasions WHERE id=$1', [occasion]);
      await db.query('DELETE FROM public.units WHERE id=$1', [unit]);
      await db.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])', [users]);
      await db.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])', [users]);
      await db.query('DELETE FROM public.organizations WHERE id=$1', [organization]);
    }
    } finally { await stager.end(); await db.end(); }
  }
});
