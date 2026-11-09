import test from 'node:test';
import assert from 'node:assert/strict';
import {runWorkers} from '../../scripts/sql_worker_pool.mjs';
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
test('a freed worker starts more work before a slow earlier task finishes',async()=>{
 const slow=deferred();const freed=deferred();const started=[];
 const pending=runWorkers([0,1,2],2,async item=>{started.push(item);if(item===0)await slow.promise;if(item===2)freed.resolve();return item;});
 await freed.promise;assert.deepEqual(started,[0,1,2]);slow.resolve();assert.deepEqual(await pending,[0,1,2]);
});
test('singleton claims serialize only conflicting tasks and results retain failure',async()=>{
 const barrier=deferred();const other=deferred();let singleton=0;let peak=0;
 const pending=runWorkers(['a','b','c'],2,async item=>{
  if(item==='c'){other.resolve();return {success:false};}
  singleton++;peak=Math.max(peak,singleton);if(item==='a')await barrier.promise;singleton--;return {success:true};
 },item=>item==='c'?null:'projector');
 await other.promise;assert.equal(singleton,1);barrier.resolve();const result=await pending;
 assert.equal(peak,1);assert.equal(result[2].success,false);
});
test('a file claiming two fixture resources blocks either conflict without blocking independent work',async()=>{
 const release=deferred();const independent=deferred();const started=[];
 const pending=runWorkers(['both','first','second','free'],3,async item=>{
  started.push(item);if(item==='both')await release.promise;if(item==='free')independent.resolve();return item;
 },item=>({both:['policy','schema'],first:['policy'],second:['schema'],free:[]})[item]);
 await independent.promise;assert.deepEqual(started,['both','free']);release.resolve();
 assert.deepEqual(await pending,['both','first','second','free']);
});
test('destructive rollback fixtures run without any other connection executing a file',async()=>{
 let active=0;let exclusiveActive=false;
 const result=await runWorkers([0,1,2],3,async item=>{
  assert.equal(exclusiveActive,false);if(item===1){assert.equal(active,0);exclusiveActive=true;}
  active++;await new Promise(resolve=>setTimeout(resolve,5));active--;
  if(item===1)exclusiveActive=false;return item;
 },()=>[],item=>item===1);
 assert.deepEqual(result,[0,1,2]);
});
