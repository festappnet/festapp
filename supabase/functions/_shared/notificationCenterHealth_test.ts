import {assertEquals,assertRejects} from 'jsr:@std/assert@1';
import {refreshNotificationCenterHealth} from './notificationCenterHealth.ts';
Deno.test('health uses authenticated shared status transport; token error stays distinct from transport failure',async()=>{
 const originalFetch=globalThis.fetch;
 const before={url:Deno.env.get('BANKSYNC_API_URL'),key:Deno.env.get('BANKSYNC_TENANT_ADMIN_KEY')};
 Deno.env.set('BANKSYNC_API_URL','https://banksync.example.invalid');Deno.env.set('BANKSYNC_TENANT_ADMIN_KEY','test-private-key');
 const saved:Record<string,unknown>[]=[];
 try{
  let calls=0;
  globalThis.fetch=((url:RequestInfo|URL,init?:RequestInit)=>{
   assertEquals(String(url),`https://banksync.example.invalid/bank-accounts/${++calls}`);
   assertEquals(new Headers(init?.headers).get('x-tenant-secret'),'test-private-key');
   assertEquals(init?.method,'GET');
   if(calls===2)throw new TypeError('simulated timeout');
   return Promise.resolve(new Response(JSON.stringify({api_last_error:'fio_token_invalid_or_inactive',api_last_success_at:'2026-10-23T08:00:00Z'})));
  }) as typeof fetch;
  const count=await refreshNotificationCenterHealth(async(name,args)=>{
   if(name==='claim_notification_center_bank_health')return {data:[{id:1,token:'one',remoteId:'1'},{id:2,token:'two',remoteId:'2'}],error:null};
   saved.push(args);return {data:null,error:null};
  });
  assertEquals(count,2);assertEquals(saved[0].p_reason,'fio_token_invalid_or_inactive');assertEquals(saved[1].p_reason,'transport_unavailable');
  assertEquals(saved[0].p_token,'one');assertEquals(saved[1].p_success_at,null);
 }finally{
  globalThis.fetch=originalFetch;
  for(const [name,value] of [['BANKSYNC_API_URL',before.url],['BANKSYNC_TENANT_ADMIN_KEY',before.key]] as const){
   if(value===undefined)Deno.env.delete(name);else Deno.env.set(name,value);
  }
 }
});
Deno.test('health stops on a failed lease commit and never claims an unbounded batch',async()=>{
 await assertRejects(()=>refreshNotificationCenterHealth(async(name,args)=>{
  if(name==='claim_notification_center_bank_health'){assertEquals(args.p_limit,4);return {data:[{id:1,token:'one',remoteId:'1'}],error:null};}
  return {data:null,error:Error('stale lease')};
 },async()=>({api_last_error:null,api_last_success_at:null})),Error,'notification_health_commit_failed');
});

for(const raw of ['FioTransientFailure: Fio API 502','FioRateLimited: Fio API 429','TimeoutError: The signal timed out']){
 Deno.test(`Fio observation ${raw} completes through the notification-center reason contract`,async()=>{
  const saved:Record<string,unknown>[]=[];
  const count=await refreshNotificationCenterHealth(async(name,args)=>{
   if(name==='claim_notification_center_bank_health')return {data:[{id:1,token:'lease',remoteId:'408'}],error:null};
   assertEquals(name,'complete_notification_center_bank_health');
   // The actual SQL contract deliberately rejects unrecognized reasons.
   if(![null,'fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required','transport_unavailable'].includes(args.p_reason as string|null)){
    return {data:null,error:Error('notification_health_reason_invalid')};
   }
   saved.push(args);return {data:null,error:null};
  },async()=>({api_last_error:raw,api_last_success_at:'2026-10-31T06:50:00Z'}));
  assertEquals(count,1);assertEquals(saved[0].p_reason,'bank_sync_retry_required');
  assertEquals(saved[0].p_success_at,'2026-10-31T06:50:00Z');
 });
}
