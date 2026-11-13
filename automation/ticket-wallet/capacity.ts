/** Deterministic transport simulation. Never connects to Google or production. */
import {GoogleWallet} from '../../supabase/functions/_shared/googleWallet.ts';
const projection:any={state:'ACTIVE',branding:{APP_NAME:'Queue measurement',DEFAULT_URL:'https://queue.invalid'},ticket:{ticket_symbol:'fixture'},occasion:{title:'Queue measurement',start_time:'2026-11-13T18:00:00Z',end_time:'2026-11-14T01:00:00Z',data:{}}};
const output=[];
for(const count of [1000,10000]){
 let clock=0,nextSlot=0,requests=0,writes=0;const accepted:number[]=[];
 const before=async()=>{clock=Math.max(clock,nextSlot);nextSlot=clock+125;requests++;};
 const google=new GoogleWallet('fixture@queue.invalid',async()=> 'fixture',async(input,init)=>{
  clock+=50; // Controlled 50 ms response latency; SQL reservation enforces 8 requests/s.
  if(String(input).includes('oauth2'))return Response.json({access_token:'fixture',expires_in:3600});
  if(init?.method==='GET')return Response.json({id:'remote',state:'COMPLETED'});
  writes++;return Response.json(JSON.parse(String(init?.body)));
 },()=>clock,async ms=>{clock+=ms;});
 // Existing registrations: one shared class, not one class write per object.
 const wallStart=performance.now();
 for(let n=0;n<count;n++){
  // One persistent bad pass consumes its attempts but never blocks the next pass.
  if(n===Math.floor(count/2)){
   const bad=new GoogleWallet('fixture@queue.invalid',async()=> 'fixture',async input=>String(input).includes('oauth2')?Response.json({access_token:'fixture',expires_in:3600}):new Response('{}',{status:429}),()=>clock,async ms=>{clock+=ms;});
   try{await bad.synchronize({classId:'1234.shared',objectId:'1234.bad'},projection,before);}catch{/* queue retries independently */}
  }
  await google.synchronize({classId:'1234.shared',objectId:'1234.fixture-'+n},projection,before);accepted.push(clock);
 }
 output.push({registrations:count,mode:'controlled transport, saturated continuous worker, no network',responseLatencyMs:50,issuerRequestsPerSecond:8,
  requests,writes,throughputPerSecond:count/(clock/1000),p95Ms:accepted[Math.ceil(count*.95)-1],maxWaitMs:accepted.at(-1),
  cpuWallMs:Math.round(performance.now()-wallStart),p95Target60s:accepted[Math.ceil(count*.95)-1]<=60000,maxTarget5min:clock<=300000,
  limitation:'Bulk burst at issuer quota. Scheduler gaps, SQL and cold class approval add delay; these are optimistic bounds.'});
}
console.log(JSON.stringify(output,null,2));
