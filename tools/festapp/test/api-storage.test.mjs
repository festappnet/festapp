import test from 'node:test';
import assert from 'node:assert/strict';
import { copyFile } from 'node:fs/promises';
import { join } from 'node:path';
import { setup, connect, apiRequest } from './api-fixture.mjs';
import { randomBytes, randomUUID } from 'node:crypto';
import { digest } from '../src/context/profile.mjs';
import { openRemoteStorage, REFRESH_REPLAY_LIMITS } from '../src/remote/storage.mjs';

test('restart retains current state; restoring a pre-revocation backup requires offline invalidation and reconsent', async t=>{
    const f=await setup(t),{tokens}=await connect(f);
    const backup=join(f.root,'backup.sqlite');
    await copyFile(join(f.root,'remote.sqlite'),backup);
    const grant=f.storage.values('Delegation')[0];f.storage.revoke(grant.id);
    assert.equal((await apiRequest(f,tokens)).status,401);
    await f.storage.close();
    await copyFile(backup,join(f.root,'remote.sqlite'));
    const restored=await openRemoteStorage(f.root,f.key);
    try {
        assert.equal(restored.values('Delegation')[0].revoked,false,'the backup actually predates revocation');
        const receipt=restored.invalidateRestoredState();assert(receipt.invalidatedRecords>0);
        for(const model of ['Delegation','AccessToken','RefreshToken','Backend','Connect','Grant','Session'])assert.deepEqual(restored.values(model),[]);
        assert(restored.get('Metadata','deployment'));
    } finally {await restored.close();}
});

test('pinned provider refresh retains consumed evidence; capacity stays bounded without evicting live replay records', async t=>{
    const f=await setup(t),{tokens}=await connect(f);
    let current=tokens,initial=f.storage.stats().byModel.RefreshToken;
    for(let i=0;i<12;i++){
        const response=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:current.refresh_token,resource:f.config.endpoints[0].resource})});
        assert.equal(response.status,200,await response.clone().text());current=await response.json();
    }
    assert.equal(f.storage.stats().byModel.RefreshToken,initial);
    assert.equal(f.storage.values('RefreshReplay').reduce((n,b)=>n+Object.keys(b.entries).length,0),12);
    const first=await f.storage.adapter('RefreshToken').find(tokens.refresh_token);assert(first.consumed);
    // Freeze only the synchronous capacity exercise so a 60s auth-code expiry
    // cannot change the record count while 20,000 fsync writes are performed.
    const originalNow=Date.now,at=Date.now();Date.now=()=>at;
    try {
        const before=f.storage.stats().records;
        for(let i=before;i<20000;i++)f.storage.put('CapacityFixture','record-'+i,{i},3600);
        assert.equal(f.storage.stats().records,20000);
        assert.throws(()=>f.storage.put('CapacityFixture','overflow',{rejected:true},3600),/REMOTE_STORAGE_FULL/);
        assert.equal(f.storage.values('RefreshReplay').reduce((n,b)=>n+Object.keys(b.entries).length,0),12);
    } finally {Date.now=originalNow;}
    // Public default consent stays seven days; longer durations remain explicit policy.
    assert.equal(f.config.clients.find(c=>c.id==='api-fixture').maxConsentDays,7);
});


test('legacy consumed rows migrate exactly and a restart preserves spent-token membership',async t=>{
 const f=await setup(t),{tokens}=await connect(f),adapter=f.storage.adapter('RefreshToken');
 const original=await adapter.find(tokens.refresh_token),spent={...original,consumed:Math.floor(Date.now()/1000)};
 f.storage.putUntil('RefreshToken',tokens.refresh_token,spent,original.exp*1000);
 f.storage.remove('Metadata','refresh-replay-v1');await f.storage.close();
 const reopened=await openRemoteStorage(f.root,f.key);
 try{assert.equal(reopened.get('RefreshToken',tokens.refresh_token),undefined);assert.deepEqual(await reopened.adapter('RefreshToken').find(tokens.refresh_token),spent);assert.equal(reopened.stats().byModel.RefreshReplay,1);}
 finally{await reopened.close();}
});

test('replay packing spans a full consent year, expires only old evidence and refuses bucket overflow before consuming',async t=>{
 const f=await setup(t),adapter=f.storage.adapter('RefreshToken'),now=Date.now,base=Date.now();
 const source={kind:'RefreshToken',clientId:'api-fixture',accountId:randomUUID(),grantId:randomUUID(),scope:'openid offline_access festapp:ticket-layouts:read',resource:'https://api.festapp.net/integrations',expiresWithSession:false};
 let first,last;
 try{
  // One exchange per six hours for 365 days. At most 30 days of spent proofs
  // remain valid, exactly matching the configured refresh idle lifetime.
  for(let i=0;i<1460;i++){
   Date.now=()=>base+i*21600000;const id=randomBytes(32).toString('base64url');first??=id;last=id;
   const value={...source,jti:id,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+30*86400,rotations:i};
   await adapter.upsert(id,value,30*86400);await adapter.consume(id);assert((await adapter.find(id)).consumed);
  }
  assert.equal(await adapter.find(first),undefined);assert((await adapter.find(last)).consumed);
  assert.equal(f.storage.stats().byModel.RefreshToken??0,0);assert(f.storage.stats().byModel.RefreshReplay<=256);
  // A high-entropy payload reaches the compressed cap. It is refused without
  // deleting the live original or any already retained replay evidence.
  const id=randomBytes(32).toString('base64url'),value={...source,jti:id,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+86400,claims:randomBytes(REFRESH_REPLAY_LIMITS.compressedBytes*2).toString('base64url')};
  await adapter.upsert(id,value,86400);await assert.rejects(()=>adapter.consume(id),/REFRESH_REPLAY_FULL/);
  assert.deepEqual(await adapter.find(id),value);assert((await adapter.find(last)).consumed);
 }finally{Date.now=now;}
});

test('offline storage rekey retains exact active and replay records, rolls back corrupt input and rejects the old key',async t=>{
 const {DatabaseSync}=await import('node:sqlite');
 const f=await setup(t),{tokens}=await connect(f);await f.storage.adapter('RefreshToken').consume(tokens.refresh_token);
 const old=f.storage.get('Metadata','encryption'),newKey=randomBytes(32),before=await f.storage.adapter('RefreshToken').find(tokens.refresh_token);
 // Corruption after a valid row forces rollback after an earlier row was
 // already re-encrypted. The original key must remain the sole valid key.
 const db=new DatabaseSync(join(f.root,'remote.sqlite'));
 db.prepare('INSERT INTO records(model,id,value,expires) VALUES(?,?,?,?)').run('Fault',digest('fault'),Buffer.from('invalid'),Date.now()+60000);
 assert.throws(()=>f.storage.rekey(newKey));assert.deepEqual(f.storage.get('Metadata','encryption'),old);
 db.prepare('DELETE FROM records WHERE model=?').run('Fault');db.close();
 assert(f.storage.rekey(newKey).reencryptedRecords>0);assert.deepEqual(await f.storage.adapter('RefreshToken').find(tokens.refresh_token),before);
 await f.storage.close();await assert.rejects(()=>openRemoteStorage(f.root,f.key));
 const rotated=await openRemoteStorage(f.root,newKey);
 try{assert.deepEqual(rotated.get('Metadata','encryption'),old);assert.deepEqual(await rotated.adapter('RefreshToken').find(tokens.refresh_token),before);}
 finally{await rotated.close();}
});
