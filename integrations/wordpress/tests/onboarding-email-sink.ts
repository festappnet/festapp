// Disposable provider boundary only: real canonical queue, renderer and sender.
// Local acceptance is never claimed as SES acceptance or email deliverability.
import {supabaseAdmin} from '../_shared/supabaseUtil.ts';
import {emailRpc} from '../_shared/emailQueueClient.ts';
import {drainEmails} from '../_shared/emailDispatcher.ts';
import {renderQueuedEmail} from '../_shared/emailRenderer.ts';
import {sealEmail,openEmail} from '../_shared/emailPayload.ts';
import {sendEmailAttempt} from '../_shared/emailSender.ts';
Deno.serve(async req=>{
 if(Deno.env.get('VO_LOCAL_CAPTURE')!=='1'||!Deno.env.get('SUPABASE_URL')?.includes('kong:8000')||req.headers.get('x-local-capture')!==Deno.env.get('VO_CAPTURE_SECRET'))return new Response('',{status:403});
 const {data:org}=await supabaseAdmin.from('organizations').select('title').eq('id',1).single();
 if(org?.title!=='Test Organization')return new Response('',{status:403});
 await emailRpc('refresh_email_quota',{p_account:'local-sink',p_region:'local',p_rate:20,p_daily:1000,p_used:0});
 const captures:any[]=[];
 const config={region:'local',accessKey:'unused',secretKey:'unused',sender:Deno.env.get('DEFAULT_EMAIL')!,transactionalSet:'local',securitySet:'local',maxBytes:30000000};
 try{
 const result=await drainEmails({rpc:emailRpc,prepare:renderQueuedEmail,seal:sealEmail,now:Date.now,send:async row=>{
  await sendEmailAttempt(row.attempt_id,row.lease_token,{rpc:emailRpc,open:openEmail,config,send:async(message,tags)=>{
   if(!message.to.endsWith('@example.invalid'))throw Error('non_synthetic_recipient');
   captures.push({message,tags});return 'local-sink-'+crypto.randomUUID();
  }});
 }},2000);
 return Response.json({mode:'local_sink_acceptance_no_provider_send',...result,captures});
 }catch(e){return Response.json({error:String(e)},{status:500});}
});
