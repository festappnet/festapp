// Reviewed all-blueprint conversion input. Reads canonical public source images;
// processing/persistence is exclusively the existing owned local Worker.
import {readFileSync,writeFileSync,mkdirSync,chmodSync,statSync} from 'node:fs';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import sharp from 'sharp';
const privateDir='/Users/miakh/source/festapp-blueprint-b-e2e-20261019';
const bridge='http://127.0.0.1:59525',api='http://127.0.0.1:59521';
const limit=20_000_000;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const envPath=process.env.BLUEPRINT_WORKER_ENV;assert(envPath);assert.equal(statSync(envPath).mode&0o077,0);
const vars=Object.fromEntries(readFileSync(envPath,'utf8').split(/\r?\n/).filter(s=>s&&!s.startsWith('#')).map(line=>{const at=line.indexOf('=');return [line.slice(0,at),line.slice(at+1).replace(/^['"]|['"]$/g,'')];}));
assert.equal((await(await fetch(bridge+'/health')).json()).project,'festapp-blueprint-b-image-local');
const source=JSON.parse(readFileSync(privateDir+'/private-existing-blueprints.json','utf8'));
const login=await fetch(api+'/auth/v1/token?grant_type=password',{method:'POST',headers:{apikey:vars.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:'1+t@t.com',password:'test'})});assert.equal(login.status,200);const jwt=(await login.json()).access_token;
const rasterDir=privateDir+'/private-existing-blueprints-rasters';mkdirSync(rasterDir,{recursive:true,mode:0o700});chmodSync(rasterDir,0o700);
const output={scope:'LOCAL_SYNTHETIC_ONLY',occasion:1,sourceExportSha256:sha(readFileSync(privateDir+'/private-existing-blueprints.json')),assets:{},failures:{}};
async function bounded(response){
 assert(response.ok,`source HTTP${response.status}`);assert(Number(response.headers.get('Content-Length')??0)<=limit,'source Content-Length exceeds20MB');
 const chunks=[];let size=0;for await(const chunk of response.body){size+=chunk.length;if(size>limit)throw Error('source exceeds20MB');chunks.push(chunk);}return Buffer.concat(chunks);
}
async function publicSource(url){
 for(let redirects=0;redirects<4;redirects++){
  const parsed=new URL(url);assert.equal(parsed.protocol,'https:');assert.equal(parsed.hostname,'img.festapp.net');assert.equal(parsed.username,'');assert.equal(parsed.password,'');assert.equal(parsed.search,'');
  const response=await fetch(url,{redirect:'manual',signal:AbortSignal.timeout(30_000)});
  if(response.status>=300&&response.status<400){url=new URL(response.headers.get('location'),url).href;continue;}
  return bounded(response);
 }throw Error('too many canonical redirects');
}
for(const blueprint of source.blueprints.filter(b=>b.background_svg)){
 try{
  const remote=blueprint.background_svg.startsWith('https:');
  const bytes=remote?await publicSource(blueprint.background_svg):Buffer.from(blueprint.background_svg);
  assert(bytes.length<=limit);const sourceSha256=sha(bytes);
  const form=new FormData();form.set('file',new File([bytes],`existing-${blueprint.id}.svg`,{type:'image/svg+xml'}));form.set('projectId','default');form.set('occasionId','1');form.set('profile','blueprint-background');
  const upload=await fetch(bridge+'/upload',{method:'POST',headers:{Authorization:`Bearer ${jwt}`},body:form});const receipt=await upload.json();assert.equal(upload.status,200,JSON.stringify(receipt));const asset=receipt.asset;assert.equal(asset.state,'ready');
  const processed=await bounded(await fetch(bridge+'/public'+new URL(asset.url).pathname));assert.equal(sha(processed),asset.hash);assert.equal(processed.length,asset.byteLength);
  const info=await sharp(processed,{animated:true}).metadata();assert.equal(info.width,asset.width);assert.equal(info.height,asset.height);assert.equal(info.pages??1,1);assert(['png','jpeg','webp'].includes(info.format));
  const file=`${rasterDir}/${blueprint.id}-${asset.hash}.${info.format==='jpeg'?'jpg':info.format}`;writeFileSync(file,processed,{mode:0o600});chmodSync(file,0o600);
  output.assets[String(blueprint.id)]={sourceSha256,sourceFieldSha256:sha(Buffer.from(blueprint.background_svg)),conversionSourceSha256:blueprint.conversionSourceSha256,sourceKind:remote?'canonical-public-url':'inline-svg',asset,rasterPath:file};
  console.log(`PASS background${blueprint.id}: ${asset.width}x${asset.height},${processed.length}B`);
 }catch(error){output.failures[String(blueprint.id)]={reason:error.message,conversionSourceSha256:blueprint.conversionSourceSha256};console.log(`FAIL background${blueprint.id}: ${error.message}`);}
}
const file=privateDir+'/private-existing-blueprints-assets.json';writeFileSync(file,JSON.stringify(output),{mode:0o600});chmodSync(file,0o600);
console.log(`RESULT local-only ready${Object.keys(output.assets).length}, failed${Object.keys(output.failures).length}, manifestSHA256 ${sha(readFileSync(file))}`);
if(Object.keys(output.failures).length)process.exitCode=1;
