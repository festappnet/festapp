import pg from 'pg';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');assert(['localhost','127.0.0.1'].includes(url.hostname));
const c=new pg.Client({connectionString:url.href});
try{
 await c.connect();assert.equal((await c.query('select project from festapp_test_support.disposable_environment')).rows[0]?.project,'festapp-blueprint-b-20261019');
 await c.query('begin');
 await c.query(readFileSync(new URL('../../database/tests/blueprint/fixtures.sql',import.meta.url),'utf8'));
 const f=(await c.query('select public.blueprint_test_fixture_internal() f')).rows[0].f;
 await c.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);
 const request=f.request;request.layout.nodes=[];
 request.seatChanges=[];
 const count=Number(process.env.BLUEPRINT_SEATS??20000);
 for(let i=0;i<count;i++){
  const id=randomUUID();request.layout.nodes.push({id,kind:'seat',width:40,height:40,transform:{x:(i%100)*60,y:Math.floor(i/100)*60,rotation:0}});
  request.seatChanges.push({nodeId:id,spotId:null,productId:f.product,title:`Seat ${i+1}`,groupNodeId:null,selectionUnitId:null,blocked:false,operation:'upsert'});
 }
 // Seed the largest practical full snapshot directly in the disposable fixture;
 // the save request changes geometry only and must still return all bindings.
 await c.query(`with made as (insert into eshop.spots(occasion,blueprint,product,title)
 select $1,$2,$3,(ord-1)::text from jsonb_array_elements($4::jsonb) with ordinality n(node,ord) returning id,title)
 insert into eshop.blueprint_seat_bindings(blueprint,node_id,spot)
 select $2,($4::jsonb->made.title::int->>'id')::uuid,made.id from made`,[f.occasion,f.blueprint,f.product,JSON.stringify(request.layout.nodes)]);
 await c.query("update eshop.spots set title=title||repeat('x',30) where blueprint=$1",[f.blueprint]);
 request.seatChanges=[];
 const command=randomUUID();
 let validationMs=null;
 if(process.env.BLUEPRINT_PROFILE){const start=performance.now();await c.query('select public.validate_blueprint_layout_internal($1)',[request.layout]);validationMs=Math.round(performance.now()-start);}
 const saveStart=performance.now();
 const r=(await c.query('select public.update_blueprint_client_sync_v1($1,$2) r',[request,command])).rows[0].r;
 const saveMs=Math.round(performance.now()-saveStart);
 assert.equal(r.status,'applied',JSON.stringify(r));assert.equal(r.data.seatBindings.length,count);assert(!('layout' in r.data));
 const sizes=(await c.query("select octet_length((response->'data')::text) data_bytes,octet_length(to_jsonb(r)::text) receipt_bytes from public.client_mutation_receipts r where command_id=$1",[command])).rows[0];
 assert(sizes.data_bytes<=4194304);assert(sizes.receipt_bytes<=8388608);
 console.log(`PASS ${count} seats: data=${sizes.data_bytes} receipt=${sizes.receipt_bytes} bytes; layout not echoed; save_ms=${saveMs}${validationMs===null?'':`; validator_ms=${validationMs}`}`);
}finally{await c.query('rollback');await c.end();}
