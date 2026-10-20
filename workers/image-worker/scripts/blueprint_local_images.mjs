// Actual guarded local pipeline proof. No mock image processor, R2 or SQL RPC.
import {readFileSync} from 'node:fs';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import assert from 'node:assert/strict';import sharp from 'sharp';
const api='http://127.0.0.1:59721',bridge='http://127.0.0.1:59725';
const envPath=process.env.BLUEPRINT_WORKER_ENV;assert(envPath,'BLUEPRINT_WORKER_ENV required');
const vars=Object.fromEntries(readFileSync(envPath,'utf8').split(/\r?\n/).filter(line=>line&&!line.startsWith('#')).map(line=>{const at=line.indexOf('=');return[line.slice(0,at),line.slice(at+1).replace(/^['"]|['"]$/g,'')]}));
assert.equal((await(await fetch(bridge+'/health')).json()).project,'festapp-blueprint-1000-image-local');
const sign=await fetch(api+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:vars.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:'1+t@t.com',password:'test'})});assert.equal(sign.status,200,'local seeded auth');const token=(await sign.json()).access_token;
const headers={apikey:vars.SUPABASE_ANON_KEY,Authorization:`Bearer ${token}`,'Content-Type':'application/json'};
const occasion=Number(process.env.BLUEPRINT_OCCASION??1);const blueprint=Number(process.env.BLUEPRINT_ID??1);
const assets=[];
const inputs=process.env.BLUEPRINT_ANIMATED_ONLY ? [['blueprint-animated.gif','image/gif'],['blueprint-animated.webp','image/webp']] : [['blueprint-raster.png','image/png'],['blueprint-safe.svg','image/svg+xml'],['blueprint-raster.png','image/png',true]];
for(const [name,mime,unitOwned] of inputs){
 const source=readFileSync(new URL('../tests/fixtures/'+name,import.meta.url));if(process.env.BLUEPRINT_ANIMATED_ONLY)assert.equal((await sharp(source,{animated:true}).metadata()).pages,2,'real animated two-frame input required');const form=new FormData();form.set('file',new File([source],name,{type:mime}));form.set('projectId','default');form.set(unitOwned?'unitId':'occasionId',String(unitOwned?Number(process.env.BLUEPRINT_UNIT??2):occasion));form.set('profile','blueprint-background');
 const response=await fetch(bridge+'/upload',{method:'POST',headers:{Authorization:`Bearer ${token}`},body:form});const result=await response.json();assert.equal(response.status,200,JSON.stringify(result));const asset=result.asset;assert.equal(asset.state,'ready');assert.equal(asset.mimeType,'image/png');assert.equal(asset.assetRef,'image:'+asset.hash);
 const read=await fetch(bridge+'/public'+new URL(asset.url).pathname);assert.equal(read.status,200);const bytes=Buffer.from(await read.arrayBuffer());assert.equal(createHash('sha256').update(bytes).digest('hex'),asset.hash);assert.equal(bytes.length,asset.byteLength);assert.equal((await sharp(bytes,{animated:true}).metadata()).pages??1,1,'output must be static');assert.equal((await sharp(bytes).metadata()).width,asset.width);assert.equal((await sharp(bytes).metadata()).height,asset.height);assert.deepEqual([...bytes.subarray(0,8)],[137,80,78,71,13,10,26,10]);assets.push(asset);
 console.log(`PASS real ${unitOwned?'unit':'occasion'} ${mime} upload -> Images -> R2 -> signed SQL registry -> public bytes ${asset.width}x${asset.height}, ${bytes.length}B`);
}
if(!process.env.BLUEPRINT_ANIMATED_ONLY){
// Save, read safe projection, and remove through the existing receipt owner.
const admin=await fetch(api+'/rest/v1/rpc/get_blueprint_for_edit',{method:'POST',headers,body:JSON.stringify({occasion_link:process.env.BLUEPRINT_OCCASION_LINK??'blueprint-business-20261019'})});
const adminResult=await admin.json();
if(adminResult.code===200&&adminResult.data.id===blueprint){
 const model=adminResult.data;let revision=model.layout_revision;const asset=assets[1];const original=model.layout;
 for(const [operation,layout] of [['save',{...original,background:{assetRef:asset.assetRef,hash:asset.hash,x:20,y:20,rotation:0,width:asset.width,height:asset.height,scale:1,opacity:1,crop:{x:0,y:0,width:1,height:1}}}],['remove',{...original,background:null}]]){
  const response=await fetch(api+'/rest/v1/rpc/update_blueprint_client_sync_v1',{method:'POST',headers,body:JSON.stringify({p_blueprint:{id:blueprint,occasion,expected_layout_revision:revision,layout,seatChanges:[],groupProductChanges:[],areaBindingChanges:[]},p_command_id:crypto.randomUUID()})});const receipt=await response.json();assert.equal(receipt.status,'applied',JSON.stringify(receipt));revision=receipt.data.layout_revision;
  const fresh=await(await fetch(api+'/rest/v1/rpc/get_blueprint_for_edit',{method:'POST',headers,body:JSON.stringify({occasion_link:process.env.BLUEPRINT_OCCASION_LINK??'blueprint-business-20261019'})})).json();assert.deepEqual(fresh.data.layout.background,layout.background);
  if(operation==='save')assert.equal(fresh.data.layoutResources.assets[asset.assetRef].hash,asset.hash);
  console.log(`PASS real receipted background ${operation} + persisted projection`);
 }
}else throw new Error('explicit BLUEPRINT_OCCASION_LINK must identify the owned fixture');
// Unsafe XML is rejected before any processed asset can become ready.
const unsafe=new FormData();unsafe.set('file',new File(['<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script>alert(1)</script></svg>'],'unsafe.svg',{type:'image/svg+xml'}));unsafe.set('projectId','default');unsafe.set('occasionId',String(occasion));unsafe.set('profile','blueprint-background');const rejected=await fetch(bridge+'/upload',{method:'POST',headers:{Authorization:`Bearer ${token}`},body:unsafe});assert.equal(rejected.status,400);console.log('PASS unsafe SVG rejected by same upload owner');

}
