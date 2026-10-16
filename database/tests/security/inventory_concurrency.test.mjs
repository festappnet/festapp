import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assert.equal(new URL(connectionString).hostname,'127.0.0.1');
assert.equal(new URL(connectionString).port,'55562');
async function connect(){const c=new Client({connectionString});await c.connect();return c;}
test('two actual editor connections compete for one resource slot without overbooking',async()=>{
 const db=await connect();const clients=await Promise.all([connect(),connect()]);
 let ids;
 const one=async(s,p=[]) => (await db.query(s,p)).rows[0];
 try{
  assert.match((await one('SHOW server_version')).server_version,/^17\./);
  assert.match((await one('SELECT project FROM festapp_test_support.disposable_environment')).project,/^festapp-security-/);
  await db.query('BEGIN');
  const actor=(await one('SELECT id FROM public.user_info LIMIT 1')).id;
  const org=(await one("INSERT INTO public.organizations(title) VALUES('Concurrency') RETURNING id")).id;
  const unit=(await one("INSERT INTO public.units(title,organization) VALUES('Fixture',$1) RETURNING id",[org])).id;
  const occ=(await one("INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Fixture',gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day') RETURNING id",[org,unit])).id;
  await db.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES($1,$2,true)',[occ,actor]);
  const pool=(await one('INSERT INTO public.inventory_pools(occasion) VALUES($1) RETURNING id',[occ])).id;
  const ctx=(await one('INSERT INTO public.inventory_contexts(inventory_pool) VALUES($1) RETURNING id',[pool])).id;
  const res=(await one("INSERT INTO public.resources(title,occasion,inventory_pool,capacity) VALUES('Fixture',$1,$2,1) RETURNING id",[occ,pool])).id;
  const slot=(await one('INSERT INTO public.resource_slots(resource) VALUES($1) RETURNING id',[res])).id;
  const spots=(await db.query('INSERT INTO eshop.spots(occasion,inventory_context) VALUES($1,$2),($1,$2) RETURNING id',[occ,ctx])).rows.map(r=>r.id);
  ids={org,unit,occ,pool,ctx,res,slot,spots};
  await db.query('COMMIT');
  const results=await Promise.allSettled(clients.map(async(c,i)=>{
   await c.query('BEGIN');
   try{
    await c.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[actor]);
    await c.query('SET LOCAL ROLE authenticated');
    await c.query('SELECT public.update_spot_assignments($1)',[JSON.stringify([{new_spot_id:spots[i],resource_id:res,resource_slot_id:slot,inventory_context_id:ctx}])]);
    await c.query('COMMIT');
   }catch(e){await c.query('ROLLBACK');throw e;}
  }));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1,JSON.stringify(results));
  assert.equal(results.filter(r=>r.status==='rejected'&&r.reason.code==='23514').length,1);
  assert.equal((await one('SELECT count(*)::int n FROM eshop.spots WHERE resource=$1',[res])).n,1);
 }finally{
  await db.query('ROLLBACK');
  if(ids){
   await db.query('BEGIN');
   for(const [table,col,value] of [['eshop.spots','occasion',ids.occ],['public.resource_slots','id',ids.slot],['public.resources','id',ids.res],['public.inventory_contexts','id',ids.ctx],['public.inventory_pools','id',ids.pool],['public.occasion_users','occasion',ids.occ],['public.occasions','id',ids.occ],['public.units','id',ids.unit],['public.organizations','id',ids.org]]) await db.query(`DELETE FROM ${table} WHERE ${col}=$1`,[value]);
   await db.query('COMMIT');
  }
  await Promise.all([...clients,db].map(c=>c.end()));
 }
});
