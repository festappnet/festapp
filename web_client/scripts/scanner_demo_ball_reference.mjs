// Local structural reference only; never imports customers, answers or payments.
import pg from 'pg';import QRCode from 'qrcode';import assert from 'node:assert/strict';import {readFile,writeFile} from 'node:fs/promises';
const [fixtureFile,sourceFile,outputFile]=process.argv.slice(2);if(!fixtureFile||!sourceFile||!outputFile)throw Error('Pass fixture, source configuration snapshot, output JSON');
const url=new URL(process.env.SCANNER_DATABASE_URL||'');if(!['127.0.0.1','localhost'].includes(url.hostname)||!url.pathname.startsWith('/festapp_scanner_'))throw Error('Isolated local DB required');
const fx=JSON.parse(await readFile(fixtureFile,'utf8')),src=JSON.parse(await readFile(sourceFile,'utf8')).sources.find(s=>s.occasion.title==='Sportovní ples Větřkovice 2026');assert(src);
const sourceForm=src.forms[0],sourceBlueprint=src.blueprints[0];
const food=sourceForm.fields.find(f=>f.product_type_data?.type==='food').product_type_data;
const spot=sourceForm.fields.find(f=>f.product_type_data?.type==='spot').product_type_data;
const db=new pg.Client({connectionString:url.toString()});await db.connect();
try{
 await db.query('begin');await db.query('select pg_advisory_xact_lock($1)',[fx.occasion]);
 const org=(await db.query('select organization from public.occasions where id=$1',[fx.occasion])).rows[0].organization;
 const form=(await db.query("select id from public.forms where occasion=$1 and title='Model Sportovní ples - objednatel a menu'",[fx.occasion])).rows[0]?.id||(await db.query("insert into public.forms(occasion,title) values($1,'Model Sportovní ples - objednatel a menu') returning id",[fx.occasion])).rows[0].id;
 for(const f of sourceForm.fields.filter(f=>['name','surname','email','note','spot'].includes(f.type))){
  if(!(await db.query('select id from public.form_fields where form=$1 and type=$2 and is_ticket_field=$3',[form,f.type,f.is_ticket_field])).rows.length)await db.query('insert into public.form_fields(form,title,type,is_ticket_field,is_required) values($1,$2,$3,$4,$5)',[form,f.title,f.type,f.is_ticket_field,f.is_required]);
 }
 const types=new Map(),products=new Map();
 for(const pt of [spot,food]){
  const type=(await db.query('select id from eshop.product_types where occasion=$1 and title=$2 and type=$3',[fx.occasion,pt.title,pt.type])).rows[0]?.id||(await db.query('insert into eshop.product_types(occasion,title,type) values($1,$2,$3) returning id',[fx.occasion,pt.title,pt.type])).rows[0].id;types.set(pt.id,type);
  for(const p of pt.products){
   const id=(await db.query('select id from eshop.products where occasion=$1 and product_type=$2 and title=$3',[fx.occasion,type,p.title])).rows[0]?.id||(await db.query('insert into eshop.products(occasion,product_type,title,price,data) values($1,$2,$3,$4,$5) returning id',[fx.occasion,type,p.title,p.price,p.data])).rows[0].id;products.set(p.id,id);
   if(pt.type==='food' && p.title.startsWith('Menu 2:'))await db.query("update eshop.products set data=coalesce(data,'{}')||jsonb_build_object('short_title','Menu 2: Panenka s pepřovou omáčkou') where id=$1",[id]);
  }
 }
 const bp=(await db.query("select id from eshop.blueprints where occasion=$1 and title='Sportovní ples - model pro scanner'",[fx.occasion])).rows[0]?.id||(await db.query("insert into eshop.blueprints(occasion,organization,title,objects,groups,configuration) values($1,$2,'Sportovní ples - model pro scanner','[]',$3,$4) returning id",[fx.occasion,org,JSON.stringify(sourceBlueprint.groups),JSON.stringify(sourceBlueprint.configuration)])).rows[0].id;
 const cases=[],objects=[];
 const specs=[{key:'ball_order',purchaser:{name:'Petra',surname:'Svobodová'},table:'7',menus:[1,2],note:'Přijdeme společně kolem 19:30.',ticketNotes:['Prosím bezbariérový přístup.','']},{key:'ball_without_dinner',purchaser:{name:'Tomáš',surname:'Novák'},table:'8',menus:[3,0],note:'',ticketNotes:['Přijde později.','']}];
 for(const spec of specs){
  const group=sourceBlueprint.groups.find(g=>g.title===spec.table);assert(group);
  const seats=sourceBlueprint.objects.filter(o=>o.type==='spot'&&o.group===group.id).sort((a,b)=>a.title.localeCompare(b.title)).slice(0,2);assert.equal(seats.length,2);
  let order;
  for(let i=0;i<2;i++){
   const symbol=`DEMO-${fx.occasion}-PLES-${spec.table}-${i+1}`;
   let ticket=(await db.query('select id from eshop.tickets where occasion=$1 and ticket_symbol=$2',[fx.occasion,symbol])).rows[0];
   if(!ticket){
    order??=(await db.query("insert into eshop.orders(occasion,form,state,order_symbol,order_sequence,data) values($1,$2,'sent',public.generate_order_symbol(),(select coalesce(max(order_sequence),0)+1 from eshop.orders where occasion=$1),$3) returning id",[fx.occasion,form,JSON.stringify({...spec.purchaser,tickets:[],fields:[]})])).rows[0].id;
    ticket=(await db.query("insert into eshop.tickets(occasion,ticket_symbol,state) values($1,$2,'sent') returning id",[fx.occasion,symbol])).rows[0];
    const opt=(await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3) returning id',[order,products.get(spot.products[0].id),ticket.id])).rows[0].id;
    await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[order,products.get(food.products[spec.menus[i]].id),ticket.id]);
    const seat=(await db.query('insert into eshop.spots(occasion,blueprint,title,product,order_product_ticket,state) values($1,$2,$3,$4,$5,\'ordered\') returning id',[fx.occasion,bp,seats[i].title,products.get(spot.products[0].id),opt])).rows[0];
    objects.push({...seats[i],id:Number(seat.id),product:Number(products.get(spot.products[0].id)),state:'ordered'});
   }else{
    order??=(await db.query('select "order" id from eshop.order_product_ticket where ticket=$1 limit 1',[ticket.id])).rows[0].id;
    const seat=(await db.query('select id from eshop.spots where order_product_ticket in(select id from eshop.order_product_ticket where ticket=$1)',[ticket.id])).rows[0];objects.push({...seats[i],id:Number(seat.id),product:Number(products.get(spot.products[0].id)),state:'ordered'});
   }
   await db.query('select public.lock_order_capacity_scope_internal(ARRAY[$1]::bigint[])',[order]);
   if(i===0)await db.query("update eshop.orders set data=jsonb_set(coalesce(data,'{}'),'{note}',to_jsonb($2::text)) where id=$1",[order,spec.note]);
   await db.query("update eshop.tickets set note=nullif($2,'') where id=$1",[ticket.id,spec.ticketNotes[i]]);
   cases.push({key:spec.key,label:spec.key==='ball_order'?'Ples: jedna objednávka, dvě různá menu':'Ples: menu a bez večeře',symbol,seat:seats[i].title,purchaser:`${spec.purchaser.name} ${spec.purchaser.surname}`,menu:food.products[spec.menus[i]].title});
  }
 }
 await db.query('update eshop.blueprints set objects=$2 where id=$1',[bp,JSON.stringify(objects)]);
 const session=(await db.query('select public.open_scanner_session($1) r',[fx.scan_code])).rows[0].r.data;
 for(const item of cases){
  const dto=(await db.query('select public.lookup_scanner_ticket($1,$2,$3) r',[session.session_id,session.token,item.symbol])).rows[0].r.data;
  assert.equal(dto.holder_name,item.symbol,'No fictional guest name');assert.equal(dto.purchaser_name,item.purchaser);assert.equal(dto.spot,item.seat);assert(dto.spot_group?.id);assert(dto.products.some(p=>p.type==='food'&&p.title===item.menu));
  Object.assign(item,{ticket_id:dto.ticket_id,order_id:dto.order_id,holder:null,fields:dto.fields,note:dto.note,order_note:dto.order_note,products:dto.products,spot_group:dto.spot_group,svg:await QRCode.toString(item.symbol,{type:'svg',margin:4,width:260})});
 }
 assert.equal(cases[0].order_id,cases[1].order_id);assert.notEqual(cases[0].order_id,cases[2].order_id);
 await db.query('commit');
 const prior=JSON.parse(await readFile(outputFile,'utf8'));prior.cases=prior.cases.filter(c=>!specs.some(s=>s.key===c.key)).concat(cases);prior.reference={title:src.occasion.title,configuration_snapshot:'2026-10-05',synthetic_customers:true};await writeFile(outputFile,JSON.stringify(prior,null,2));
 console.log('Prepared 2 real local orders / 4 tickets, canonical purchaser names, blueprint groups and source menu variants.');
}catch(error){await db.query('rollback');throw error;}finally{await db.end();}
