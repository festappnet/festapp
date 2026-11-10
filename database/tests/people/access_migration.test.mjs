import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import test from 'node:test';
import { assertDisposableDatabase, assertLocalDatabaseUrl } from '../../../web_client/tests/database/disposable_database.js';
const { Client } = createRequire(new URL('../../../web_client/package.json', import.meta.url))('pg');
const root = new URL('../../../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
test('legacy pending/accepted/expired invitations retain proofs, audit and messages through rename', { skip: !process.env.DATABASE_URL }, async () => {
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const db = new Client({ connectionString: process.env.DATABASE_URL });await db.connect();
 try {
  await assertDisposableDatabase(db);await db.query('BEGIN');
  // Reconstruct the installed table from immutable history inside rollback only.
  await db.query('ALTER TABLE public.access_invitations RENAME TO access_migration_archive');
  await db.query('DROP INDEX public.access_invitation_recipient');
  let history=read('supabase/migrations/20261019160000_occasion_setup_invitations.sql');
  history=history.slice(history.indexOf('CREATE TABLE IF NOT EXISTS'),history.indexOf('CREATE OR REPLACE FUNCTION'));
  // Existing indexes keep historical names after rename; free those names only
  // inside this rollback fixture so the old table can be recreated exactly.
  for(const index of ['occasion_team_invitations_pkey','occasion_team_invitations_token_hash_key']) {
   await db.query(`ALTER INDEX IF EXISTS public.${index} RENAME TO ${index}_fixture_archive`);
  }
  await db.query(history);
  const {rows:[{id:org}]}=await db.query("INSERT INTO public.organizations(title) VALUES('Access migration fixture') RETURNING id");
  const {rows:[{id:unit}]}=await db.query("INSERT INTO public.units(title,organization) VALUES('Access migration fixture',$1) RETURNING id",[org]);
  const {rows:[{id:occasion}]}=await db.query("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Access migration fixture',$1,$2,$3,now(),now()+interval '1 day') RETURNING id",[org,unit,randomUUID()]);
  const {rows:[{id:actor}]}=await db.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id',[org,'migration-actor@example.invalid','disposable-password','{}']);
  await db.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[unit,actor]);
  const ids=[];const drafts=[];
  for(const [n,state] of ['pending','accepted','expired'].entries()) {
   const draft=randomUUID();drafts.push(draft);const id=randomUUID();ids.push(id);
   await db.query("INSERT INTO public.occasion_setup_drafts(id,unit,organization,author,data) VALUES($1,$2,$3,$4,'{}')",[draft,unit,org,actor]);
   const {rows:[{queue}]}=await db.query("SELECT public.enqueue_email('custom',$1,$2,'{}',$3,'TEAM_INVITATION') queue",[{organization:org,occasion,unit},`${state}@example.invalid`,randomUUID()]);
   await db.query("INSERT INTO public.occasion_team_invitations(id,draft,occasion,unit,organization,email,role,token_hash,created_by,accepted_by,accepted_at,expires_at,message_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
    [id,draft,occasion,unit,org,`${state}@example.invalid`,n===1?'read_only':'editor',createHash('sha256').update(state).digest('hex'),actor,state==='accepted'?actor:null,state==='accepted'?new Date('2026-01-01'):null,state==='expired'?new Date('2020-01-01'):new Date('2030-01-01'),queue.message_id]);
  }
  const templateIds=[];
  for(const [label,organizationId,unitId,eventId] of [['global',null,null,null],['tenant',org,null,null],['unit',org,unit,null],['occasion',org,unit,occasion]]) {
   const {rows:[{id}]}=await db.query("INSERT INTO public.email_templates(code,organization,unit,occasion,subject,html) VALUES('TEAM_INVITATION',$1,$2,$3,$4,$5) RETURNING id",[organizationId,unitId,eventId,`Custom ${label}`,`<p>Custom ${label} {{occasionTitle}}</p>`]);templateIds.push(id);
  }
  const templateSnapshot=(await db.query('SELECT id,subject,html FROM public.email_templates WHERE id=ANY($1::bigint[]) ORDER BY id',[templateIds])).rows;
  const before=(await db.query('SELECT id,token_hash,accepted_at,accepted_by,message_id,expires_at FROM public.occasion_team_invitations ORDER BY id')).rows;
  const emailsBefore=(await db.query('SELECT count(*) FROM public.email_messages')).rows[0].count;
  await db.query(read('database/functions/people/access_schema.sql').split('-- A short-lived trusted render deposit')[0]);
  await db.query(read('database/functions/people/access_templates.sql'));
  assert.deepEqual((await db.query('SELECT id,subject,html FROM public.email_templates WHERE id=ANY($1::bigint[]) ORDER BY id',[templateIds])).rows,templateSnapshot);
  for(const [context,expected] of [[{},templateIds[0]],[{organization:org},templateIds[1]],[{organization:org,unit},templateIds[2]],[{organization:org,unit,occasion},templateIds[3]]]) {
   const {rows:[{template}]}=await db.query("SELECT public.get_resolved_email_template('TEAM_INVITATION',$1) template",[context]);assert.equal(String(template.id),String(expected));
  }
  const after=(await db.query('SELECT id,token_hash,accepted_at,accepted_by,message_id,expires_at FROM public.access_invitations ORDER BY id')).rows;
  assert.deepEqual(after,before);
  assert.equal((await db.query('SELECT count(*) FROM public.email_messages')).rows[0].count,emailsBefore);
  await db.query('DELETE FROM public.occasion_setup_drafts WHERE id=ANY($1::uuid[])',[drafts]);
  assert.equal((await db.query('SELECT count(*) FROM public.access_invitations WHERE id=ANY($1::uuid[]) AND draft IS NULL',[ids])).rows[0].count,'3');
  assert.equal((await db.query("SELECT offered_roles->>'is_editor' editor FROM public.access_invitations WHERE role='read_only'")).rows[0].editor,'false');
 } finally {await db.query('ROLLBACK');await db.end();}
});
