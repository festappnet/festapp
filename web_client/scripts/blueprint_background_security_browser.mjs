// Actual shared resource boundary in a local headless browser. No production IO.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import pg from 'pg';
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'59722');
const db=new pg.Client({connectionString:url.href});
const temp=await mkdtemp(path.join(tmpdir(),'blueprint1000-security-'));
const config=path.join(temp,'browser.json');await writeFile(config,'{}',{mode:0o600});
const session=`blueprint1000-svg-${process.pid}`,exec=promisify(execFile);
const browser=async(...args)=>{
 const {stdout}=await exec('agent-browser',['--config',config,'--headed','false','--session',session,'--json',...args],{timeout:30000});
 const response=JSON.parse(stdout);assert.equal(response.success,true,response.error);return response.data;
};
try{
 await db.connect();assert.equal((await db.query('select project from festapp_test_support.disposable_environment where singleton')).rows[0]?.project,'festapp-blueprint-1000-e2e-20261020');
 const asset=(await db.query('select asset_ref,hash,url,width,height,mime_type,byte_length from public.blueprint_image_assets where occasion=195 order by created_at desc limit 1')).rows[0];assert(asset);
 const manifest={hash:asset.hash,url:`http://127.0.0.1:59725/public${new URL(asset.url).pathname}`,width:asset.width,height:asset.height,mimeType:asset.mime_type,byteLength:asset.byte_length};
 await browser('open','about:blank');
 await browser('network','route','**/*festapp.net/**','--abort');
 await browser('network','route','**/*supabase.co/**','--abort');
 await browser('open','http://127.0.0.1:59741/');
 await browser('snapshot','-i');
 const source=`(async()=>{
  const {loadLayoutAssets}=await import('/node_modules/@festapp/venue-layout/src/index.js');
  const payload='<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><img xmlns="http://www.w3.org/1999/xhtml" src="x" onerror="globalThis.__blueprintExecuted=true"/></foreignObject></svg>';
  const hash='a'.repeat(64);let rejection;
  try{await loadLayoutAssets({assets:{['image:'+hash]:{hash,mimeType:'image/svg+xml',width:1,height:1,byteLength:payload.length,url:'data:image/svg+xml,'+encodeURIComponent(payload)}}});}catch(error){rejection=error.message;}
  const resolved=await loadLayoutAssets({assets:{${JSON.stringify(asset.asset_ref)}:${JSON.stringify(manifest)}}});
  const image=new Image();image.src=resolved.assets[${JSON.stringify(asset.asset_ref)}].url;await image.decode();
  return {rejection,executed:globalThis.__blueprintExecuted===true,activePayloadInDom:document.documentElement.innerHTML.includes('__blueprintExecuted'),rasterDecoded:image.naturalWidth===${asset.width}&&image.naturalHeight===${asset.height}};
 })()`;
 const data=await browser('eval','-b',Buffer.from(source).toString('base64'));
 const result=data.result??data;
 assert.equal(result.rejection,'invalid_asset_manifest');assert.equal(result.executed,false);assert.equal(result.activePayloadInDom,false);assert.equal(result.rasterDecoded,true);
 console.log(JSON.stringify({passed:true,...result,boundary:'actual installed shared package + actual Worker-registered raster in headless Chrome'}));
}finally{await browser('close').catch(()=>{});await db.end();await rm(temp,{recursive:true,force:true});}
