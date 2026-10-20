// Local-only read RPCs. No production mutation endpoint is exposed.
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
const exec=promisify(execFile),read=async p=>JSON.parse(await readFile(p,'utf8'));
const digest=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const events=[{id:44,title:'Country bál 2026',date:'14. 11. 2026',link:'country_bal_vetrkovice'},{id:87,title:'Ples AKH 2026',date:'20. 11. 2026',link:'4aa0bcbb7d114ceb9f07762cc8660c1b'}];
const templates=[{id:'cinema-galaxy',title:'Galaktické kino'},{id:'ball-classic',title:'Klasický ples'},{id:'auditorium',title:'Obloukové řady'},{id:'bus',title:'Autobus'}];
export function blueprintPreviewPlugin({backend,artifact}){
 const rpc=async(name,body)=>{
  const {url,key}=await read(resolve(backend,'private-public-preview-api.json'));assert.equal(url,'https://api.festapp.net');
  let stdout;try{({stdout}=await exec('curl',['-fsS','--max-time','25','-A','Mozilla/5.0','-H',`apikey: ${key}`,'-H',`Authorization: Bearer ${key}`,'-H','Content-Type: application/json','--data',JSON.stringify(body),`${url}/rest/v1/rpc/${name}`],{maxBuffer:8*1024*1024}));}catch{throw Error('Veřejná data se nepodařilo načíst.');}
  const r=JSON.parse(stdout);assert.equal(r.code,200,`${name} unavailable`);return r.data;
 };
 const live=async event=>{
  const activation=JSON.parse((await exec('curl',['-fsS','--max-time','15','-A','Mozilla/5.0','https://vstupenky.online/backend-activation.json'])).stdout);
  assert.equal(activation.tenantId,'festapptickets');assert.equal(activation.backend,'canonical');assert.equal(activation.generation,1);
  const form=await rpc('get_form_by_link',{form_link:event.link});assert.equal(form.blueprint,event.id);
  const current=await rpc('get_blueprint',{my_secret:randomUUID(),form_key:form.key,blueprint_id:event.id});
  const source=(await read(resolve(backend,'private-existing-blueprints.json'))).blueprints.find(b=>b.id===event.id);
  for(const k of ['objects','groups','configuration','background_svg'])assert.ok(digest(current[k])===digest(source[k]),`Geometry changed: ${k}; conversion review required`);
  const paths=await read(resolve(backend,'blueprint-preview-artifacts.json'));
  const converted=(await read(resolve(backend,paths.conversion))).blueprints.find(b=>b.blueprintId===event.id);
  const layout=converted.request.layout;assert.equal(layout.schemaVersion,2);
  const resources=await read(resolve(backend,paths.resources));assert.equal(resources.protocol,2);
  for(const id of converted.request.textResourceIds)assert.ok(resources.textLayouts[id],`Missing canonical text ${id}`);
  const spots=current.spots.map(({id,title,product,state})=>({id,title,product,state}));
  const bySpot=new Map(spots.map(s=>[s.id,s])),bindings=converted.request.seatChanges;
  assert.equal(new Set(bindings.map(b=>b.spotId)).size,spots.length);
  assert.deepEqual(bindings.map(b=>b.spotId).sort((a,b)=>a-b),spots.map(s=>s.id).sort((a,b)=>a-b));
  const objects=new Map(current.objects.filter(o=>o.type==='spot').map(o=>[o.id,o]));
  const nodes=new Map(layout.nodes.map(n=>[n.id,n])),groups=new Map(current.groups.map(g=>[String(g.id),g.title])),groupTitles=new Map();
  for(const b of bindings){
   const s=bySpot.get(b.spotId);assert.equal(b.productId,s.product,'Product drift');assert.equal(b.title,s.title,'Seat title drift');
   const n=nodes.get(b.nodeId);assert.equal(n?.kind,'seat');let parent=n;const visited=new Set();while(parent?.parentId&&parent.parentId!==b.groupNodeId){assert.ok(!visited.has(parent.id),'Cyclic parent');visited.add(parent.id);parent=nodes.get(parent.parentId);}assert.equal(parent?.parentId,b.groupNodeId);
   const expected=groups.get(String(objects.get(b.spotId).group));
   if(b.groupNodeId){assert.equal(nodes.get(b.groupNodeId)?.label,expected,'Table/group title drift');groupTitles.set(b.groupNodeId,expected);}
  }
  const fp=form.fields.flatMap(f=>f.product_type_data?.products||[]);
  const products=[...new Map(current.products.map(p=>[p.id,p])).values()].map(p=>{const f=fp.find(f=>f.id===p.id);return {id:p.id,title:p.title,price:p.price,currency_code:f?.currency_code||null,is_dynamically_available:f?.is_dynamically_available};});
  const states=Object.fromEntries([...new Set(spots.map(s=>s.state))].sort().map(s=>[s,spots.filter(x=>x.state===s).length]));
  const seatBindings=bindings.map(({nodeId,spotId,productId,title,groupNodeId,selectionUnitId,blocked})=>({nodeId,spotId,productId,title,groupNodeId,selectionUnitId,blocked}));
  const parity={seats:spots.length,groups:groupTitles.size,states,spotStateSha256:digest([...spots].sort((a,b)=>a.id-b.id)),layoutSha256:digest(layout),verifiedAt:new Date().toISOString()};
  return {...event,formUrl:event.id===44?'/form/preview-country-bal-2026':'/form/preview-ples-akh-2026',kind:'live',sourceUrl:`https://vstupenky.online/form/${event.link}`,data:{layout,layoutResources:resources,spots,products,seatBindings},parity};
 };
 return {name:'blueprint-readonly-preview',transformIndexHtml(){return [{tag:'script',injectTo:'head-prepend',children:`
if(location.pathname.startsWith('/form/preview-')){
 localStorage.setItem('locale','cs');
 addEventListener('DOMContentLoaded',()=>{
  const bar=document.createElement('div');bar.className='blueprint-preview-banner';bar.textContent='TESTOVACÍ OBJEDNÁVKA - bez platby a odesílání e-mailů';
  Object.assign(bar.style,{position:'sticky',top:'0',zIndex:'100000',background:'#f5d78b',color:'#241f12',padding:'9px 16px',textAlign:'center',font:'600 13px system-ui'});
  document.body.classList.add('blueprint-preview-order');
  document.body.prepend(bar);
  const style=document.createElement('style');style.textContent='body.blueprint-active .blueprint-preview-banner{position:fixed!important;top:0;left:0;right:0}body.blueprint-preview-order .blueprint-modal-container{top:var(--preview-banner-height,34px);height:calc(100% - var(--preview-banner-height,34px))}';document.head.append(style);
  const measure=()=>document.body.style.setProperty('--preview-banner-height',bar.getBoundingClientRect().height+'px');measure();addEventListener('resize',measure);

 });
}`}]},configureServer(server){server.middlewares.use(async(req,res,next)=>{
  const path=new URL(req.url,'http://localhost').pathname;
  if(!path.startsWith('/__blueprint-preview')&&path!=='/blueprint-preview')return next();
  res.setHeader('Cache-Control','no-store');if(req.method!=='GET'){res.statusCode=405;return res.end();}
  try{
   if(path==='/blueprint-preview'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(await readFile(new URL('./blueprint_web_preview.html',import.meta.url),'utf8'));}
   let result;
   if(path==='/__blueprint-preview/catalog')result={events,templates};
   else if(path.startsWith('/__blueprint-preview/live/')){const event=events.find(e=>String(e.id)===path.split('/').pop());assert.ok(event);result=await live(event);}
   else if(path.startsWith('/__blueprint-preview/template/')){
    const id=path.split('/').pop();assert.ok(templates.some(t=>t.id===id));
    const t=(await read(resolve(artifact,'templates.json'))).find(t=>t.id===id),resources=await read(resolve(artifact,'npm/assets/layout_fonts/fixtures.json'));
    const seats=t.document.nodes.filter(n=>n.kind==='seat');
    result={id,kind:'template',data:{layout:t.document,layoutResources:resources,products:[{id:1,title:'Ukázkové vstupné',price:150,currency_code:'CZK'}],spots:seats.map(n=>({id:n.id,title:n.label||'',product:1,state:'available'})),seatBindings:seats.map(n=>({nodeId:n.id,spotId:n.id,title:n.label||'',productId:1}))}};
   }else{res.statusCode=404;return res.end();}
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
  }catch(error){console.error('Blueprint preview:',error.message);res.statusCode=409;res.setHeader('Content-Type','application/json');res.end(JSON.stringify({error:'Náhled nebyl ověřen. '+error.message}));}
 });}};
}
