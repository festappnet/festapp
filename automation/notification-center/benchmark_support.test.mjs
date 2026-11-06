import {test} from 'node:test';
import assert from 'node:assert/strict';
import {withDatabase,setupFixture,receiptPath} from './benchmark_support.mjs';

const local='postgresql://postgres:postgres@127.0.0.1:55432/postgres';
function fake({marker='festapp-fixture',failOn}={}){
 const instances=[];
 class Client {
  constructor(){instances.push(this);this.queries=[];}
  async connect(){}
  async end(){this.closed=true;}
  async query(sql,args){
   this.queries.push({sql,args});
   if(failOn&&sql.includes(failOn))throw Error('injected failure');
   if(sql.includes('disposable_environment'))return {rows:[{project:marker}]};
   if(sql.includes('INSERT INTO public.organizations'))return {rows:[{id:17}]};
   return {rows:[]};
  }
 }
 return {Client,instances};
}
test('rejects remote URLs before connecting',async()=>{
 const {Client,instances}=fake();
 await assert.rejects(withDatabase(()=>assert.fail(),{connectionString:'postgresql://example.com/postgres',Client}));
 assert.equal(instances.length,0);
});
test('rejects a wrong marker and closes the connection',async()=>{
 const {Client,instances}=fake({marker:'production'});
 await assert.rejects(withDatabase(()=>assert.fail(),{connectionString:local,Client}));
 assert.equal(instances[0].closed,true);
 assert.equal(instances[0].queries.length,1);
});
test('cleans partial setup by recorded organization and users after resetting claims',async()=>{
 const {Client,instances}=fake({failOn:'INSERT INTO public.user_info'});
 await assert.rejects(withDatabase(async([c],fixtures)=>setupFixture(c,fixtures,3,1),{connectionString:local,Client}));
 const c=instances[0];
 assert.equal(c.closed,true);
 const deletes=c.queries.filter(q=>q.sql.startsWith('DELETE'));
 assert.ok(deletes.some(q=>q.sql.includes('public.organizations')&&q.args[0]===17));
 assert.ok(!deletes.some(q=>q.sql.includes('occasions')));
 assert.ok(c.queries.findIndex(q=>q.sql.includes("set_config"))<c.queries.indexOf(deletes[0]));
});
test('closes every independent connection when the scenario fails',async()=>{
 const {Client,instances}=fake();
 await assert.rejects(withDatabase(()=>{throw Error('scenario');},{connectionString:local,Client,count:3}));
 assert.equal(instances.length,3);
 assert.ok(instances.every(c=>c.closed));
});
test('receipt is required before starting fixture work',()=>{
 assert.throws(()=>receiptPath(undefined));
 assert.throws(()=>receiptPath('/missing-festapp-parent/receipt.json'));
});
