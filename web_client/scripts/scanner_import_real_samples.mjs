// Import an explicitly authorized, private read-only sample into the isolated local scanner.
// Customer data and fixture credentials must never be written to the repository/public assets.
import pg from 'pg';import {readFile,writeFile,chmod} from 'node:fs/promises';import assert from 'node:assert/strict';
const [sourceFile,catalogFile]=process.argv.slice(2);if(!sourceFile||!catalogFile||catalogFile.includes('/web_client/'))throw Error('Private source and output paths required');
const url=new URL(process.env.SCANNER_DATABASE_URL||'');if(!['127.0.0.1','localhost'].includes(url.hostname)||!url.pathname.startsWith('/festapp_scanner_'))throw Error('Isolated local DB required');
const source=JSON.parse(await readFile(sourceFile,'utf8'));assert.equal(source.organization,3);const keys={82:'skaut',1072585:'akh',32316:'country'};
if(source.events.length!==3||source.events.some(e=>!keys[e.id]))throw Error('Unexpected source scope');
try{await readFile(catalogFile);throw Error('Catalog already exists; refusing to reset/reimport customer samples');}catch(error){if(error.code!=='ENOENT')throw error;}
const db=new pg.Client({connectionString:url.toString()});await db.connect();const catalog={captured_at:source.captured_at,events:{}};
const mapFields=(fields,map)=>(fields||[]).flatMap(answer=>{const mapped=Object.fromEntries(Object.entries(answer).filter(([key])=>map.has(String(key))).map(([key,value])=>[map.get(String(key)),value]));return Object.keys(mapped).length?[mapped]:[];});
try{
 await db.query('begin');
 for(const event of source.events){
  const key=keys[event.id],fx=(await db.query('select public.scanner_test_fixture(0) fx')).rows[0].fx;
  const organization=(await db.query('select organization from public.occasions where id=$1',[fx.occasion])).rows[0].organization;
  const ticketFeature=(event.features||[]).find(f=>f.code==='ticket')||{};
  await db.query('update public.occasions set title=$2,features=$3 where id=$1',[fx.occasion,`${event.title} · simulace`,JSON.stringify([{code:'ticket',is_enabled:ticketFeature.is_enabled!==false,can_scan_manually:ticketFeature.can_scan_manually===true,show_hidden_note:ticketFeature.show_hidden_note===true}])]);
  await db.query('update public.organizations set title=$2 where id=$1',[organization,`Soukromá simulace: ${event.title}`]);
  const forms=new Map(),fields=new Map(),types=new Map(),products=new Map(),tickets=new Map(),orders=new Map(),links=new Map(),spots=new Map(),blueprints=new Map();
  for(const [index,form] of (event.forms||[]).entries()){
   const id=index===0?fx.form:(await db.query('insert into public.forms(occasion,title) values($1,$2) returning id',[fx.occasion,form.title])).rows[0].id;
   if(index===0)await db.query('update public.forms set title=$2 where id=$1',[id,form.title]);forms.set(String(form.id),id);
  }
  for(const type of event.product_types||[])types.set(String(type.id),(await db.query('insert into eshop.product_types(occasion,title,type,data) values($1,$2,$3,$4) returning id',[fx.occasion,type.title,type.type,type.data])).rows[0].id);
  for(const product of event.products||[])products.set(String(product.id),(await db.query('insert into eshop.products(occasion,title,price,product_type,data) values($1,$2,$3,$4,$5) returning id',[fx.occasion,product.title,product.price,types.get(String(product.product_type)),product.data])).rows[0].id);
  for(const field of event.fields||[])fields.set(String(field.id),(await db.query('insert into public.form_fields(form,title,type,is_ticket_field,is_hidden,is_required,product_type) values($1,$2,$3,$4,$5,$6,$7) returning id',[forms.get(String(field.form)),field.title,field.type,field.is_ticket_field,field.is_hidden,field.is_required,types.get(String(field.product_type))])).rows[0].id);
  for(const ticket of event.tickets){
   const symbol=`SIM-${key.toUpperCase()}-${fx.occasion}-${tickets.size+1}`;
   const id=(await db.query('insert into eshop.tickets(occasion,ticket_symbol,state,note,note_hidden,data,updated_at) values($1,$2,$3,$4,$5,$6,$7) returning id',[fx.occasion,symbol,ticket.state,ticket.note,ticket.note_hidden,JSON.stringify({fields:mapFields(ticket.data?.fields,fields)}),ticket.updated_at])).rows[0].id;tickets.set(String(ticket.id),{id,symbol});
   if(ticket.linked_holder){
    const uid=(await db.query("insert into auth.users(id,email) values(gen_random_uuid(),gen_random_uuid()||'@scanner-simulation.invalid') returning id")).rows[0].id;
    await db.query('insert into public.user_info(id,name,surname,organization) values($1,$2,$3,$4)',[uid,ticket.linked_holder.name,ticket.linked_holder.surname,organization]);await db.query('insert into public.occasion_users(occasion,"user",ticket) values($1,$2,$3)',[fx.occasion,uid,id]);
   }
  }
  for(const order of event.orders){
   const data={...order.data,fields:mapFields(order.data?.fields,fields),tickets:(order.data?.tickets||[]).filter(t=>tickets.has(String(t.id))).map(t=>({...t,id:tickets.get(String(t.id)).id}))};
   let payment=null;if(order.payment)payment=(await db.query('insert into eshop.payment_info(amount,paid,currency_code) values($1,$2,$3) returning id',[order.payment.amount,order.payment.paid,order.payment.currency_code])).rows[0].id;
   orders.set(String(order.id),(await db.query('insert into eshop.orders(occasion,form,state,order_symbol,order_sequence,data,payment_info,note_hidden) values($1,$2,$3,public.generate_order_symbol(),$4,$5,$6,$7) returning id',[fx.occasion,forms.get(String(order.form)),order.state,order.order_sequence,JSON.stringify(data),payment,order.note_hidden])).rows[0].id);
  }
  for(const link of event.links)links.set(String(link.id),(await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[orders.get(String(link.order)),tickets.get(String(link.ticket)).id,products.get(String(link.product))])).rows[0].id);
  for(const bp of event.blueprints||[])blueprints.set(String(bp.id),(await db.query("insert into eshop.blueprints(occasion,organization,title,groups,objects) values($1,$2,$3,$4,'[]') returning id",[fx.occasion,organization,bp.title,JSON.stringify(bp.groups||[])])).rows[0].id);
  for(const spot of event.spots||[])spots.set(String(spot.id),(await db.query('insert into eshop.spots(occasion,title,blueprint,product,order_product_ticket,state) values($1,$2,$3,$4,$5,\'ordered\') returning id',[fx.occasion,spot.title,blueprints.get(String(spot.blueprint)),products.get(String(spot.product)),links.get(String(spot.order_product_ticket))])).rows[0].id);
  for(const bp of event.blueprints||[]){const objects=(bp.objects||[]).filter(o=>spots.has(String(o.id))).map(o=>({id:Number(spots.get(String(o.id))),type:'spot',title:o.title,x:o.x,y:o.y,group:o.group,product:Number(products.get(String(o.product))),state:'ordered'}));await db.query('update eshop.blueprints set objects=$2 where id=$1',[blueprints.get(String(bp.id)),JSON.stringify(objects)]);}
  let config=(await db.query('select public.scanner_default_settings_internal($1) config',[fx.occasion])).rows[0].config;
  const legacyVisible=new Set([735,725,739,615,616,629,620]);
  config.fields=(event.fields||[]).filter(f=>legacyVisible.has(f.id)&&!f.is_hidden).map(f=>({key:`${f.is_ticket_field?'ticket':'order'}:${forms.get(String(f.form))}:${fields.get(String(f.id))}`,source:f.is_ticket_field?'ticket_field':'order_field',form_id:Number(forms.get(String(f.form))),field_id:Number(fields.get(String(f.id))),label:f.title||f.type,default_visible:true,hide_empty:true}));
  await db.query('select public.scanner_validate_settings_internal($1,$2)',[fx.occasion,config]);await db.query('update public.scanner_settings set config=$2 where occasion_id=$1',[fx.occasion,config]);
  const session=(await db.query('select public.open_scanner_session($1) r',[fx.scan_code])).rows[0].r.data;
  for(const ticket of event.tickets){const local=tickets.get(String(ticket.id));const r=(await db.query('select public.lookup_scanner_ticket($1,$2,$3) r',[session.session_id,session.token,local.symbol])).rows[0].r;assert.equal(r.code,200);assert.equal(r.data.state,ticket.state);assert.equal(r.data.note||null,ticket.note?.trim()||null);}
  const grouped=event.orders.map((order,index)=>{const ids=new Set(event.links.filter(z=>z.order===order.id).map(z=>String(z.ticket)));const symbols=[...ids].map(id=>tickets.get(id).symbol);return {key:`real_order_${index+1}`,label:`Objednávka č. ${order.order_sequence} · ${symbols.length} ${symbols.length===1?'vstupenka':symbols.length<5?'vstupenky':'vstupenek'}`,source_order_id:order.id,local_order_id:orders.get(String(order.id)),symbols,source_state:order.state};});
  catalog.events[key]={fixture:{...fx,organization},title:event.title,source_occasion:event.id,orders:grouped};
 }
 await db.query('commit');await writeFile(catalogFile,JSON.stringify(catalog,null,2),{mode:0o600});await chmod(catalogFile,0o600);
 console.log(JSON.stringify({imported:Object.entries(catalog.events).map(([key,e])=>({key,orders:e.orders.length,tickets:e.orders.reduce((n,o)=>n+o.symbols.length,0)}))}));
}catch(error){await db.query('rollback');throw error;}finally{await db.end();}
