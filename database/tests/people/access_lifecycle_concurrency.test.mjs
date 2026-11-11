import assert from 'node:assert/strict';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import test from 'node:test';
import { assertDisposableDatabase, assertLocalDatabaseUrl } from '../../../web_client/tests/database/disposable_database.js';
const { Client } = createRequire(new URL('../../../web_client/package.json', import.meta.url))('pg');
const hash = value => createHash('sha256').update(value).digest('hex');
test('access lifecycle serializes acceptance, revocation, identity creation and credential retry on separate connections', { skip: !process.env.DATABASE_URL }, async t => {
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const connections = [new Client({ connectionString: process.env.DATABASE_URL, statement_timeout: 10000 }), new Client({ connectionString: process.env.DATABASE_URL, statement_timeout: 10000 })];
 const [a,b] = connections; let org, unit, occasion; const users=[];
 const identity = async (db, actor) => db.query("SELECT set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false)", [actor ?? '']);
 try {
  await Promise.all(connections.map(c=>c.connect())); await assertDisposableDatabase(a);
  ({rows:[{id:org}]}=await a.query("INSERT INTO public.organizations(title) VALUES('Access concurrency') RETURNING id"));
  ({rows:[{id:unit}]}=await a.query("INSERT INTO public.units(title,organization) VALUES('Access concurrency',$1) RETURNING id",[org]));
  ({rows:[{id:occasion}]}=await a.query("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Access concurrency',$1,$2,$3,now(),now()+interval '1 day') RETURNING id",[org,unit,randomUUID()]));
  for(const name of ['actor','member']) {
   const {rows:[{id}]}=await a.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id',[org,`${name}@example.invalid`,randomUUID(),'{}']); users.push(id);
  }
  const [actor,member]=users;
  await a.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[unit,actor]);
  await a.query('INSERT INTO public.occasion_users(occasion,"user",is_manager) VALUES($1,$2,true),($1,$3,false)',[occasion,actor,member]);
  const offer=async(email='member@example.invalid')=> {
   const token=randomBytes(32).toString('hex');
   const {rows:[{id}]}=await a.query("INSERT INTO public.access_invitations(scope_type,occasion,unit,organization,email,offered_roles,token_hash,created_by) VALUES('occasion',$1,$2,$3,$4,'{\"is_editor\":true,\"is_editor_view\":true}',$5,$6) RETURNING id",[occasion,unit,org,email,hash(token),actor]);
   return {id,token};
  };
  await t.test('simultaneous accept adds the offer once',async()=>{
   const i=await offer();await Promise.all(connections.map(c=>identity(c,member)));
   const results=await Promise.all(connections.map(c=>c.query('SELECT public.accept_access_invitation($1) result',[i.token])));
   assert.ok(results.every(r=>r.rows[0].result.accepted));
   assert.equal((await a.query("SELECT count(*) FROM public.client_commits WHERE occasion=$1 AND source='profile.team_invitation.accept'",[occasion])).rows[0].count,'1');
  });
  await t.test('revoke wins before blocked acceptance and cannot resurrect permissions',async()=>{
   const i=await offer();await identity(a,actor);await identity(b,member);
   await a.query('BEGIN');await a.query('SELECT public.revoke_access_invitation($1)',[i.id]);
   const accepting=assert.rejects(b.query('SELECT public.accept_access_invitation($1)',[i.token]),/invitation_revoked/);
   // Observe the actual transaction blocker before releasing the revoke.
   let blocked=false;for(let n=0;n<50;n++){
    const {rows:[{ids}]}=await a.query('SELECT pg_blocking_pids($1) ids',[b.processID]);
    if(ids.includes(a.processID)){blocked=true;break;}await a.query('SELECT pg_sleep(0.02)');
   }
   assert.ok(blocked);await a.query('COMMIT');await accepting;
  });
  await t.test('legacy membership teardown invalidates before a blocked acceptance',async()=>{
   const i=await offer();await identity(a,actor);await identity(b,member);
   await a.query('BEGIN');
   await a.query('SELECT 1 FROM public.occasion_users WHERE occasion=$1 AND "user"=$2 FOR UPDATE',[occasion,member]);
   await a.query('SELECT public.remove_occasion_user_domain_internal_v1($1,$2)',[occasion,member]);
   const accepting=assert.rejects(b.query('SELECT public.accept_access_invitation($1)',[i.token]),/invitation_revoked/);
   let blocked=false;for(let n=0;n<50;n++){
    const {rows:[{ids}]}=await a.query('SELECT pg_blocking_pids($1) ids',[b.processID]);
    if(ids.includes(a.processID)){blocked=true;break;}await a.query('SELECT pg_sleep(0.02)');
   }
   assert.ok(blocked);await a.query('COMMIT');await accepting;
   assert.equal((await a.query('SELECT count(*) FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[occasion,member])).rows[0].count,'0');
  });
  await t.test('identity create versus anonymous accept preserves a single canonical account',async()=>{
   const email=`new-${randomUUID()}@example.invalid`;const i=await offer(email);
   await identity(a,null);await identity(b,null);
   const results=await Promise.allSettled([
    a.query('SELECT public.accept_access_invitation($1,$2)',[i.token,'disposable-password']),
    b.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id',[org,email,'disposable-password','{}']),
   ]);
   assert.ok(results.some(r=>r.status==='fulfilled'));
   const {rows}=await a.query('SELECT id FROM public.user_info WHERE organization=$1 AND email_readonly=$2',[org,email]);assert.equal(rows.length,1);users.push(rows[0].id);
  });
  await t.test('concurrent participant retry joins the same credential intent',async()=>{
   const {rows:[{id}]}=await a.query('SELECT public.create_user_in_organization_with_data_pure($1,$2,$3,$4) id',[org,`participant-${randomUUID()}@example.invalid`,'before','{}']);users.push(id);
   await a.query('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$2)',[occasion,id]);
   await Promise.all(connections.map(c=>identity(c,actor)));const dedupe=`concurrent:${randomUUID()}`;
   const results=await Promise.all(connections.map(c=>c.query("SELECT public.reset_password_and_enqueue_email($1,'123456',$2,'{\"sealed\":\"fixture\"}',$3,$4,now()+interval '10 minutes') result",[id,occasion,'a'.repeat(64),dedupe])));
   assert.equal(results[0].rows[0].result.message_id,results[1].rows[0].result.message_id);
  });
 } finally {
  await Promise.all(connections.map(c=>c.query('ROLLBACK').catch(()=>{})));
  try {
   if(unit){
    await a.query('DELETE FROM public.access_invitations WHERE unit=$1',[unit]);
    await a.query('DELETE FROM public.email_messages WHERE unit=$1',[unit]);
    await a.query('DELETE FROM public.client_mutation_receipts WHERE unit=$1 OR occasion=$2',[unit,occasion]);
    for(const table of ['client_commit_components','client_commit_items'])await a.query(`DELETE FROM public.${table} WHERE commit_id IN(SELECT commit_id FROM public.client_commits WHERE unit=$1 OR occasion=$2)`,[unit,occasion]);
    await a.query('DELETE FROM public.client_commits WHERE unit=$1 OR occasion=$2',[unit,occasion]);
    await a.query('DELETE FROM public.occasion_users WHERE occasion=$1',[occasion]);
    await a.query('DELETE FROM public.unit_users WHERE unit=$1',[unit]);
    await a.query('DELETE FROM public.occasions WHERE id=$1',[occasion]);
    await a.query('DELETE FROM public.units WHERE id=$1',[unit]);
    await a.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])',[users]);
    await a.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])',[users]);
    await a.query('DELETE FROM public.organizations WHERE id=$1',[org]);
   }
  } finally {await Promise.all(connections.map(c=>c.end()));}
 }
});
