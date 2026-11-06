import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {options,setup,create,connection} from './form-fixtures.mjs';
import {openDisposableDatabase} from './postgres.mjs';
const migration=await readFile(new URL('../../../supabase/migrations/20261106100000_form_measurement_policy.sql',import.meta.url),'utf8');

test('actual migration blocks concurrent scope/config writes while public reads remain available, and rollback releases locks',options,async t=>{
 const {db,f}=await setup(t);const made=await create(db,f);
 const second=await openDisposableDatabase(connection);t.after(()=>second.end());
 await db.query('SAVEPOINT migration_lock');await db.query(migration);
 await second.query("set statement_timeout='1500ms'");
 assert.equal((await second.query('select count(*)::int count from public.forms')).rows[0].count>=0,true);
 await second.query("set statement_timeout='150ms'");
 for(const [sql,id] of [['update public.forms set is_open=is_open where id=$1',made.formId],['update public.units set title=title where id=$1',f.unit],['update public.occasions set unit=unit where id=$1',f.occasion]]){
  await assert.rejects(second.query(sql,[id]),error=>error.code==='57014');
 }
 await db.query('ROLLBACK TO SAVEPOINT migration_lock');await second.query("set statement_timeout='1500ms'");
 // Fixture rows are uncommitted/invisible to the second connection, but its
 // UPDATE must now acquire the table lock and complete rather than time out.
 assert.equal((await second.query('update public.occasions set unit=unit where id=$1',[f.occasion])).rowCount,0);
});

test('a conflicting second Unit rolls back the whole migration without moving the first Unit configuration',options,async t=>{
 const {db,f}=await setup(t);const first=await create(db,f);
 await db.query("update public.forms set data='{\"analytics\":{\"gtm_container\":\"GTM-AB12\"}}' where id=$1",[first.formId]);
 const unit=(await db.query("insert into public.units(title,organization) values('Druhý pořadatel',$1) returning id",[f.org])).rows[0].id;
 const occasion=(await db.query("insert into public.occasions(title,organization,unit,link,start_time,end_time) values('Zimní koncert',$1,$2,$3,now(),now()+interval '1 day') returning id",[f.org,unit,'chaos-'+randomUUID()])).rows[0].id;
 const forms=[];
 for(const container of ['GTM-CC11','GTM-DD22'])forms.push((await db.query("insert into public.forms(occasion,link,data,is_open) values($1,$2,$3,true) returning id",[occasion,'chaos-'+randomUUID(),{analytics:{gtm_container:container}}])).rows[0].id);
 const ids=[first.formId,...forms];const before=(await db.query('select id,data from public.forms where id=any($1) order by id',[ids])).rows;
 await db.query('SAVEPOINT atomic_conflict');await assert.rejects(db.query(migration),error=>error.message.includes('Conflicting legacy measurement destinations'));
 await db.query('ROLLBACK TO SAVEPOINT atomic_conflict');
 assert.deepEqual((await db.query('select id,data from public.forms where id=any($1) order by id',[ids])).rows,before);
 assert.equal((await db.query('select data from public.units where id=$1',[f.unit])).rows[0].data?.measurement_gtm_container,undefined);
});
