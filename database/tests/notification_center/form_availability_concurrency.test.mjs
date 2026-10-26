import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
async function connect(){
 const c=new Client({connectionString});await c.connect();
 try{await assertDisposableDatabase(c);await c.query("SET statement_timeout='10s'");return c;}
 catch(error){await c.end();throw error;}
}
async function fixture(c){
 const {rows:[org]}=await c.query("INSERT INTO public.organizations(title) VALUES('Availability concurrency') RETURNING id");
 const {rows:[oc]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Concurrent',$2,now(),now()+interval '1 day') RETURNING id",[org.id,randomUUID()]);
 const {rows:[f]}=await c.query(`INSERT INTO public.forms(occasion,is_open,data) VALUES($1,true,jsonb_build_object('schedule',jsonb_build_object('start_time',clock_timestamp()-interval '2 hours','end_time',clock_timestamp()-interval '1 hour'))) RETURNING id`,[oc.id]);
 await c.query("INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES($1,clock_timestamp()-interval '1 day')",[org.id]);
 await c.query("SELECT public.notification_center_form_availability_internal($1,clock_timestamp()-interval '3 hours',NULL,true)",[f.id]);return {org:org.id,form:f.id};
}
async function lockForm(c,f){await c.query('BEGIN');await c.query('SELECT public.notification_center_initialized_internal($1)',[f.org]);await c.query('SELECT 1 FROM public.forms WHERE id=$1 FOR UPDATE',[f.form]);}
test('scheduler skips a writer lock, writer drains both boundaries once, retry is quiet',async()=>{
 const a=await connect(),b=await connect();try{
  const f=await fixture(a);await lockForm(a,f);
  assert.equal((await b.query('SELECT public.notification_center_evaluate_forms_internal(500) n')).rows[0].n,0);
  await a.query('SELECT public.notification_center_form_availability_internal($1)',[f.form]);
  await a.query('UPDATE public.forms SET is_open=false WHERE id=$1',[f.form]);
  await a.query('SELECT public.notification_center_form_availability_internal($1)',[f.form]);await a.query('COMMIT');
  await b.query('SELECT public.notification_center_evaluate_forms_internal(500)');
  const {rows}=await b.query('SELECT kind,occurred_at FROM public.notification_center_events WHERE organization=$1 ORDER BY occurred_at',[f.org]);
  assert.deepEqual(rows.map(r=>r.kind),['form_opened','form_closed']);assert.ok(rows[1].occurred_at>rows[0].occurred_at);
 }finally{await a.query('ROLLBACK');await a.end();await b.end();}
});
test('two real reducers contend on form lock and commit each transition exactly once',async()=>{
 const a=await connect(),b=await connect(),observer=await connect();try{
  const f=await fixture(a);await lockForm(a,f);
  await a.query('SELECT public.notification_center_form_availability_internal($1)',[f.form]);
  await b.query('BEGIN');const pid=(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const pending=b.query('SELECT public.notification_center_form_availability_internal($1)',[f.form]);
  let blocked=false;for(let i=0;i<100;i++){blocked=(await observer.query('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked;if(blocked)break;await new Promise(r=>setTimeout(r,10));}
  assert.ok(blocked,'real form lock contention');await a.query('COMMIT');await pending;await b.query('COMMIT');
  assert.equal((await observer.query('SELECT count(*)::int n FROM public.notification_center_events WHERE organization=$1',[f.org])).rows[0].n,2);
 }finally{for(const c of [a,b,observer]){await c.query('ROLLBACK');await c.end();}}
});
