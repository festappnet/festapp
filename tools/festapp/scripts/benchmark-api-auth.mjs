import assert from 'node:assert/strict';
import { setup,connect } from '../test/api-fixture.mjs';
import { createRateLimiter } from '../src/remote/rate-limit.mjs';
import { performance } from 'node:perf_hooks';
// Synthetic personal consent, actual pinned provider HTTP exchanges and FULL
// encrypted SQLite writes. Advance only the wall clock, five minutes/exchange.
// No external backend, cron, sender or payment provider participates.
const callbacks=[],t={after:fn=>callbacks.push(fn)},realNow=Date.now;
const rounds=Number(process.argv[2]??105119);assert(Number.isInteger(rounds)&&rounds>0&&rounds<=105119);
const epoch=realNow();let offset=0;Date.now=()=>epoch+offset;
const start=performance.now();let reportAt=start,peakRecords=0,peakReplayBytes=0,peakRss=0;
try{
 const f=await setup(t,{apiPolicy:{maxConsentDays:365},rateLimiter:createRateLimiter({now:()=>offset})});
 let {tokens}=await connect(f,{consentFields:{durationDays:'365'}}),recent;
 for(let i=0;i<rounds;i++){
  recent=tokens.refresh_token;offset+=300000;
  const response=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:recent,resource:f.config.endpoints[0].resource})});
  assert.equal(response.status,200,'refresh '+i+': '+await response.clone().text());tokens=await response.json();
  if(i%100===0){const stats=f.storage.stats();peakRecords=Math.max(peakRecords,stats.records);peakReplayBytes=Math.max(peakReplayBytes,stats.replayBytes);peakRss=Math.max(peakRss,process.memoryUsage().rss);}
  if(performance.now()-reportAt>30000){process.stderr.write('Refresh exchanges completed: '+(i+1)+'/'+rounds+'\n');reportAt=performance.now();}
 }
 const before=f.storage.stats();assert.equal(before.byModel.RefreshToken,1);assert(before.byModel.RefreshReplay<=256);assert(before.records<400);
 const replay=await fetch(f.issuer+'/token',{method:'POST',body:new URLSearchParams({client_id:'api-fixture',grant_type:'refresh_token',refresh_token:recent,resource:f.config.endpoints[0].resource})});assert.equal(replay.status,400);
 assert(f.storage.values('Delegation').find(g=>g.clientId==='api-fixture').revoked);
 console.log(JSON.stringify({ok:true,rounds,virtualDays:rounds/288,intervalSeconds:300,limiter:'unchanged budgets; monotonic fixture clock advances with the virtual wall clock',elapsedSeconds:(performance.now()-start)/1000,peakRecords,peakReplayBytes,peakRss,finalBeforeReplay:before,reuseRevokedFamily:true,node:process.version,durability:'SQLite synchronous FULL, actual provider HTTP; native process',limits:'192 MiB Node heap; encrypted replay buckets capped at 32 MiB compressed, 2 MiB decoded per lookup'}));
}finally{Date.now=realNow;for(const callback of callbacks.reverse())await callback();}
