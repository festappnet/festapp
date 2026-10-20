import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert(['59722','59822'].includes(url.port));
const a=new Client({connectionString:url.href}),b=new Client({connectionString:url.href});
try{
 await Promise.all([a.connect(),b.connect()]);
 const marker=(await a.query('select project from festapp_test_support.disposable_environment where singleton')).rows[0].project;
 assert.equal(marker,url.port==='59822'?'festapp-blueprint-1000-fresh-20261020':'festapp-blueprint-1000-e2e-20261020');
 for(const c of [a,b])await c.query("set statement_timeout='10s';set lock_timeout='5s'");
 await a.query(readFileSync(new URL('../blueprint/fixtures.sql',import.meta.url),'utf8'));
 const f=(await a.query('select public.blueprint_test_fixture_internal() f')).rows[0].f;
 await a.query("select set_config('request.jwt.claim.sub',$1,false)",[f.actor]);
 const saved=(await a.query('select public.update_blueprint_client_sync_v1($1,$2) r',[f.request,randomUUID()])).rows[0].r;assert.equal(saved.status,'applied');
 const spot=saved.data.seatBindings[0].spotId,secret=randomUUID();
 assert.equal((await a.query('select public.select_spot($1,$2,$3,true) r',[f.formKey,secret,spot])).rows[0].r.code,200);
 const deadline=(await a.query("update public.forms set data=jsonb_build_object('end_time',clock_timestamp()+interval '2 seconds') where id=$1 returning data->>'end_time' deadline",[f.form])).rows[0].deadline;
 const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 await b.query("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claim.role','anon',false)");await b.query('set role anon');
 await a.query('begin');await a.query('select public.update_product_internal_v1($1)',[{id:f.product,price:101}]);
 let done=false;
 const pending=b.query('select public.create_ticket_order_client_sync_v1($1,$2,$3) r',[{form:f.formKey,email:`deadline-${f.occasion}@example.invalid`,secret,ticket:[{spot}]},randomUUID(),randomUUID()]).then(r=>{done=true;return r;});
 let blocked=false;
 for(let i=0;i<100;i++){
  if((await a.query('select pg_blocking_pids($1) blockers',[pid])).rows[0].blockers.length){blocked=true;break;}if(done)break;
  await new Promise(resolve=>setTimeout(resolve,10));
 }
 assert(blocked,'checkout must wait on actual price owner');
 // This is a real expiration test: release only after PostgreSQL confirms that
 // its authoritative clock crossed the configured deadline, not after a sleep.
 while(!(await a.query('select clock_timestamp()>$1::timestamptz expired',[deadline])).rows[0].expired)await new Promise(resolve=>setTimeout(resolve,10));
 await a.query('commit');
 const rejected=(await pending).rows[0].r;assert.equal(rejected.status,'rejected',JSON.stringify(rejected));
 assert.equal(rejected.data.code,1020,JSON.stringify(rejected));await b.query('reset role');
 assert.equal((await b.query('select count(*)::int n from eshop.orders where occasion=$1',[f.occasion])).rows[0].n,0);
 assert.equal((await b.query('select count(*)::int n from eshop.tickets where occasion=$1',[f.occasion])).rows[0].n,0);
 assert.equal((await b.query('select order_product_ticket from eshop.spots where id=$1',[spot])).rows[0].order_product_ticket,null);
 console.log(`PASS form deadline rechecked after actual product-owner lock wait; database=${marker}`);
}finally{await Promise.allSettled([a,b].map(async c=>{await c.query('rollback');await c.end();}));}
