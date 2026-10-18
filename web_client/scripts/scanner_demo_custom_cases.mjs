// Real data for the isolated scanner demo only. Never accepts a remote database.
import pg from 'pg';
import QRCode from 'qrcode';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
const [fixturePath,outputPath]=process.argv.slice(2);
if(!fixturePath||!outputPath)throw Error('Pass fixture JSON and output JSON paths');
const url=new URL(process.env.SCANNER_DATABASE_URL||'');
if(!['127.0.0.1','localhost'].includes(url.hostname)||!url.pathname.startsWith('/festapp_scanner_'))throw Error('Explicit isolated local database required');
const fx=JSON.parse(await readFile(fixturePath,'utf8'));
const db=new pg.Client({connectionString:url.toString()});await db.connect();
try{
 await db.query('begin');
 await db.query('select pg_advisory_xact_lock($1)',[fx.occasion]);
 const oc=(await db.query('select organization from public.occasions where id=$1',[fx.occasion])).rows[0];
 assert(oc,'Fixture occasion exists');
 const field=async(form,title,ticket=false)=>{
  const prior=(await db.query('select id from public.form_fields where form=$1 and title=$2 and is_ticket_field=$3',[form,title,ticket])).rows[0];
  return prior?.id||(await db.query("insert into public.form_fields(form,title,type,is_ticket_field) values($1,$2,'text',$3) returning id",[form,title,ticket])).rows[0].id;
 };
 const ballForm=(await db.query("select id from public.forms where occasion=$1 and title='Ples - rezervace stolu'",[fx.occasion])).rows[0]?.id||(await db.query("insert into public.forms(occasion,title) values($1,'Ples - rezervace stolu') returning id",[fx.occasion])).rows[0].id;
 const defs=[];
 for(const [form,title,ticket,visible] of [[fx.form,'Název skupiny',false,true],[fx.form,'Počet hostů v objednávce',false,true],[fx.form,'Stravování hosta',true,true],[fx.form,'Poznámka pro vstup',true,true],[fx.form,'Interní kontakt objednatele',false,false],[ballForm,'Společnost / rezervace',false,true],[ballForm,'Počet míst v objednávce',false,true],[ballForm,'Menu hosta',true,true]]){
  const id=await field(form,title,ticket);defs.push({key:`${ticket?'ticket':'order'}:${form}:${id}`,source:ticket?'ticket_field':'order_field',form_id:Number(form),field_id:Number(id),label:title,default_visible:visible,hide_empty:true});
 }
 const answers=(form,ticket,values)=>defs.filter(f=>f.form_id===Number(form)&&f.source===(ticket?'ticket_field':'order_field')).map(f=>({[f.field_id]:values[f.label]??''}));
 const blueprint=(await db.query("select id from eshop.blueprints where occasion=$1 and title='Demo - plesový sál'",[fx.occasion])).rows[0]?.id||(await db.query("insert into eshop.blueprints(occasion,organization,title,objects,groups) values($1,$2,'Demo - plesový sál','[]','[]') returning id",[fx.occasion,oc.organization])).rows[0].id;
 const product=async title=>(await db.query('select id from eshop.products where occasion=$1 and title=$2',[fx.occasion,title])).rows[0]?.id||(await db.query('insert into eshop.products(occasion,title,price) values($1,$2,100) returning id',[fx.occasion,title])).rows[0].id;
 const admission=await product('Vstup do hlavního sálu'),ball=await product('Ples - vstup se sezením'),meal=await product('Slavnostní večeře');
 const cases=[
  {key:'custom',label:'Vlastní pole: vyplněná objednávka',suffix:'CUSTOM',form:fx.form,name:'Klára',surname:'Veselá',order:{'Název skupiny':'Taneční klub Orion','Počet hostů v objednávce':'4','Interní kontakt objednatele':'Tento údaj je ve scanneru vypnutý'},ticket:{'Stravování hosta':'Vegetariánské menu','Poznámka pro vstup':'Příchod bočním vchodem, doprovod 1 dítěte.'},products:[admission]},
  {key:'ball',label:'Ples: účet hosta, stůl a večeře',suffix:'BALL-A',form:ballForm,name:'Jana',surname:'Dvořáková',linked:true,seat:'Stůl 7 · místo 1',order:{'Společnost / rezervace':'Novákovi a přátelé','Počet míst v objednávce':'2'},ticket:{'Menu hosta':'Kuřecí menu'},products:[ball,meal]},
  {key:'ball_partner',label:'Ples: druhý host stejné objednávky',suffix:'BALL-B',form:ballForm,name:'Petr',surname:'Dvořák',seat:'Stůl 7 · místo 2',order:{'Společnost / rezervace':'Novákovi a přátelé','Počet míst v objednávce':'2'},ticket:{'Menu hosta':'Bezlepkové menu'},products:[ball,meal]},
  {key:'empty',label:'Vlastní pole: nevyplněné odpovědi',suffix:'EMPTY',form:fx.form,name:'Martin',surname:'Král',order:{},ticket:{},products:[admission]},
  {key:'long',label:'Vlastní pole: dlouhá poznámka',suffix:'LONG',form:fx.form,name:'Eliška',surname:'Novotná',order:{'Název skupiny':'Spolek přátel kultury a společenského tance z Nového Města','Počet hostů v objednávce':'12'},ticket:{'Stravování hosta':'Bez lepku a laktózy','Poznámka pro vstup':'Hosté přijdou postupně mezi 18:00 a 19:30. Paní Novotná potřebuje bezbariérový přístup; doprovod má vlastní vstupenku. U vstupu prosíme předat modrý náramek.'},products:[admission]}
 ];
 let ballOrder;
 for(const item of cases){
  item.symbol=`DEMO-${fx.occasion}-${item.suffix}`;
  let t=(await db.query('select id from eshop.tickets where occasion=$1 and ticket_symbol=$2',[fx.occasion,item.symbol])).rows[0];
  if(!t){
   t=(await db.query("insert into eshop.tickets(occasion,ticket_symbol,state,data) values($1,$2,'sent',$3) returning id",[fx.occasion,item.symbol,JSON.stringify({fields:answers(item.form,true,item.ticket)})])).rows[0];
   let oid;
   if(item.key==='ball_partner'&&ballOrder)oid=ballOrder;
   else oid=(await db.query("insert into eshop.orders(occasion,form,state,order_symbol,data,order_sequence) values($1,$2,'sent',public.generate_order_symbol(),$3,(select coalesce(max(order_sequence),0)+1 from eshop.orders where occasion=$1)) returning id",[fx.occasion,item.form,JSON.stringify({fields:answers(item.form,false,item.order),tickets:item.linked?[]:[{id:t.id,name:item.name,surname:item.surname}]})])).rows[0].id;
   if(item.key==='ball')ballOrder=oid;
   if(item.key==='ball_partner')await db.query('select public.lock_order_capacity_scope_internal(ARRAY[$1]::bigint[])',[oid]);
   if(item.key==='ball_partner')await db.query("update eshop.orders set data=jsonb_set(data,'{tickets}',coalesce(data->'tickets','[]')||$2::jsonb) where id=$1",[oid,JSON.stringify([{id:t.id,name:item.name,surname:item.surname}])]);
   let primary;
   for(const pid of item.products){const row=(await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3) returning id',[oid,pid,t.id])).rows[0];primary??=row.id;}
   if(item.seat)await db.query('insert into eshop.spots(occasion,title,blueprint,order_product_ticket,product,state) values($1,$2,$3,$4,$5,\'ordered\')',[fx.occasion,item.seat,blueprint,primary,ball]);
   if(item.linked){
    const user=(await db.query("insert into auth.users(id,email) values(gen_random_uuid(),$1) returning id",[`scanner-demo-${fx.occasion}@example.invalid`])).rows[0].id;
    await db.query('insert into public.user_info(id,name,surname,organization) values($1,$2,$3,$4)',[user,item.name,item.surname,oc.organization]);
    await db.query('insert into public.occasion_users(occasion,"user",ticket) values($1,$2,$3)',[fx.occasion,user,t.id]);
   }
  }else if(item.key==='ball')ballOrder=(await db.query('select "order" id from eshop.order_product_ticket where ticket=$1 limit 1',[t.id])).rows[0].id;
  item.ticket_id=Number(t.id);
 }
 const cfg=(await db.query('select config from public.scanner_settings where occasion_id=$1',[fx.occasion])).rows[0].config;
 cfg.fields=[...cfg.fields.filter(f=>!defs.some(d=>d.key===f.key)),...defs];
 await db.query('select public.scanner_validate_settings_internal($1,$2)',[fx.occasion,cfg]);
 await db.query('update public.scanner_settings set config=$2,revision=revision+1,epoch=epoch+1 where occasion_id=$1',[fx.occasion,cfg]);
 const session=(await db.query('select public.open_scanner_session($1) r',[fx.scan_code])).rows[0].r.data;
 const output=[];
 for(const item of cases){
  const dto=(await db.query('select public.lookup_scanner_ticket($1,$2,$3) r',[session.session_id,session.token,item.symbol])).rows[0].r.data;
  assert.equal(dto.holder_name,`${item.name} ${item.surname}`);
  assert.equal(dto.fields.length,item.form===fx.form?5:3);
  if(item.seat)assert.equal(dto.spot,item.seat);
  if(item.key==='custom')assert.equal(dto.fields.find(f=>f.label==='Stravování hosta').value,'Vegetariánské menu');
  output.push({key:item.key,label:item.label,symbol:item.symbol,ticket_id:item.ticket_id,holder:dto.holder_name,spot:dto.spot,fields:dto.fields,products:dto.products,svg:await QRCode.toString(item.symbol,{type:'svg',margin:4,width:260})});
 }
 await db.query('commit');
 await writeFile(outputPath,JSON.stringify({occasion:fx.occasion,cases:output},null,2));
 console.log(`Prepared and RPC-verified ${output.length} custom demo cases for occasion ${fx.occasion}.`);
}catch(error){await db.query('rollback');throw error;}finally{await db.end();}
