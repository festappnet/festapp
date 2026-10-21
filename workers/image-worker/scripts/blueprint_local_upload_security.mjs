// Reproducible actual local upload boundary, with no remote storage/provider.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const envPath=process.env.BLUEPRINT_WORKER_ENV;assert(envPath);
const vars=Object.fromEntries(readFileSync(envPath,'utf8').split(/\r?\n/).filter(Boolean).map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const api='http://127.0.0.1:59721',bridge='http://127.0.0.1:59725';
assert.equal((await(await fetch(bridge+'/health')).json()).project,'festapp-blueprint-1000-image-local');
const login=await fetch(api+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:vars.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:'1+t@t.com',password:'test'})});assert.equal(login.status,200);
const token=(await login.json()).access_token;
const upload=async(bytes,type,name)=>{const form=new FormData();form.set('file',new File([bytes],name,{type}));form.set('projectId','default');form.set('occasionId','195');form.set('profile','blueprint-background');return fetch(bridge+'/upload',{method:'POST',headers:{Authorization:`Bearer ${token}`},body:form});};
const results=[];
for(const [name,type] of [['blueprint-raster.png','image/png'],['blueprint-safe.svg','image/svg+xml']]){
 const res=await upload(readFileSync(new URL('../tests/fixtures/'+name,import.meta.url)),type,name);const body=await res.json();assert.equal(res.status,200,JSON.stringify(body));
 const asset=body.asset;assert.equal(asset.state,'ready');assert.equal(asset.mimeType,'image/png');
 const bytes=new Uint8Array(await(await fetch(bridge+'/public'+new URL(asset.url).pathname)).arrayBuffer());
 assert.equal(createHash('sha256').update(bytes).digest('hex'),asset.hash);assert.equal(bytes.length,asset.byteLength);
 results.push({input:type,result:asset.mimeType,width:asset.width,height:asset.height,bytes:bytes.length,hashVerified:true});
}
const unsafe='<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><foreignObject><img xmlns="http://www.w3.org/1999/xhtml" src="x" onerror="globalThis.__blueprintExecuted=true"/></foreignObject></svg>';
const bad=await upload(unsafe,'image/svg+xml','unsafe.svg');assert.equal(bad.status,400);
console.log(JSON.stringify({passed:true,results,activeSvgRejected:bad.status,boundary:'actual local Images/R2 and signed SQL registry; no save or order mutation'}));
