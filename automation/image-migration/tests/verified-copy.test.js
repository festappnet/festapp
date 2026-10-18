import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { copyVerifiedAsset } from '../lib/verified-copy.js';

function fixture() {
  const bytes = Buffer.from('identical binary bytes\0\xff');
  const asset = { identity: {bucket:'public-files',key:'fixture'}, issues: [], visibility:'public',
    source: {size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')},
    destination: {bucket:'festapp-images',key:'assets/storage/fixture'}, contentType:'application/pdf' };
  const objects = new Map(); const receipts = [];
  const dependencies = {
    async openSource() { return {stream:Readable.from([bytes]),done:Promise.resolve()}; },
    destination: {
      async exists(bucket,key) { return objects.has(bucket+'/'+key); },
      async read(bucket,key) { const obj=objects.get(bucket+'/'+key);return obj ? {...obj, stream:Readable.from([obj.bytes])}:null; },
      async create(bucket,key,stream,options) {
        assert.equal(options.ifNoneMatch,'*');
        const chunks=[]; for await (const chunk of stream) chunks.push(chunk);
        objects.set(bucket+'/'+key,{bytes:Buffer.concat(chunks),contentType:options.contentType});
      },
    },
    async persistReceipt(receipt) { receipts.push(receipt); },
  };
  return {asset,objects,receipts,dependencies,bytes};
}
test('copies exact bytes/MIME and resumes after lost receipt without rewriting',async()=>{
  const f=fixture();
  const first=await copyVerifiedAsset(f.asset,f.dependencies);
  assert.equal(first.resumed,false);assert.equal(f.receipts.length,1);
  f.dependencies.destination.create=()=>{throw Error('must not overwrite');};
  const resumed=await copyVerifiedAsset(f.asset,f.dependencies);
  assert.equal(resumed.resumed,true);assert.equal(resumed.sha256,first.sha256);
});
test('refuses existing conflicting bytes and access-classification destinations',async()=>{
  const f=fixture();f.objects.set('festapp-images/assets/storage/fixture',{bytes:Buffer.from('other'),contentType:'application/pdf'});
  await assert.rejects(copyVerifiedAsset(f.asset,f.dependencies),/destination_conflict/);
  assert.equal(f.receipts.length,0);
  await assert.rejects(copyVerifiedAsset({...f.asset,destination:{bucket:'festapp-images-akhweb',key:'x'}},f.dependencies),/invalid_destination/);
  await assert.rejects(copyVerifiedAsset({...f.asset,visibility:'private'},f.dependencies),/visibility_destination_mismatch/);
});
test('fails on changed source or interrupted read without a verified receipt',async()=>{
  const f=fixture();f.dependencies.openSource=async()=>({stream:Readable.from([Buffer.from('wrong')]),done:Promise.resolve()});
  await assert.rejects(copyVerifiedAsset(f.asset,f.dependencies),/source_changed/);
  assert.equal(f.receipts.length,0);
});
test('a racing create is accepted only after a full matching destination read',async()=>{
  const f=fixture();f.dependencies.destination.create=async(bucket,key,stream)=>{
    for await (const _ of stream) { /* Consume the independent source hash gate. */ }
    f.objects.set(bucket+'/'+key,{bytes:f.bytes,contentType:f.asset.contentType});
    throw Object.assign(new Error('race'),{code:'PRECONDITION_FAILED'});
  };
  const result=await copyVerifiedAsset(f.asset,f.dependencies);
  assert.equal(result.resumed,true);assert.equal(f.receipts.length,1);
});
