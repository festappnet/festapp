import type {Env} from './types';
import {resolveControlProject,resolveProjectByHostname,assertControlHost} from './project-registry';
import {extractBearerToken} from './auth';
import {assetKey} from './asset-key';
import {errorResponse,jsonResponse} from './responses';
interface MediaStep {field:string;source:string;target:string;ready:boolean}
interface MediaJob {commandId:string;occasionId:number;action:'copy'|'delete';state:'pending'|'complete';media:MediaStep[]}
export async function handleOccasionLifecycle(request:Request,env:Env,fetcher:typeof fetch=fetch):Promise<Response>{
 if(request.method!=='POST')return errorResponse(405,'METHOD_NOT_ALLOWED','Method not allowed');
 if(Number(request.headers.get('content-length')??0)>4096)return errorResponse(413,'BODY_LIMIT','Request too large');
 let body:{projectId?:string;commandId?:string};let jwt:string;
 try{const text=await request.text();if(text.length>4096)throw Error();body=JSON.parse(text);jwt=extractBearerToken(request.headers.get('Authorization')??'');}
 catch{return errorResponse(400,'INVALID_REQUEST','Invalid lifecycle request');}
 if(!body||Object.keys(body).some(k=>!['projectId','commandId'].includes(k))||typeof body.commandId!=='string'||!/^([a-f0-9]{8}-)([a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(body.commandId))return errorResponse(400,'INVALID_REQUEST','Invalid lifecycle request');
 let project;try{project=resolveControlProject(env,{projectId:body.projectId});assertControlHost(project,request.url);if(project.authContract!=='festapp')throw Error();}catch{return errorResponse(400,'UNKNOWN_PROJECT','Unknown lifecycle project');}
 const rpc=async(name:string,args:Record<string,unknown>)=>{
  const response=await fetcher(`${project.supabaseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:project.anonKey,Authorization:`Bearer ${jwt}`,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(10000),redirect:'error'});
  if(!response.ok)throw Object.assign(Error('lifecycle_rpc_rejected'),{status:response.status});
  return response.json();
 };
 try{
  let job=await rpc('get_occasion_media_job',{p_command_id:body.commandId}) as MediaJob;
  if(job.commandId!==body.commandId||!Array.isArray(job.media)||job.media.length>2)throw Error();
  for(let index=0;index<job.media.length;index++){
   const step=job.media[index];const sourceUrl=new URL(step.source),targetUrl=new URL(step.target);
   const source=resolveProjectByHostname(env,sourceUrl.hostname);
   if(sourceUrl.protocol!=='https:'||sourceUrl.username||sourceUrl.password||sourceUrl.search||sourceUrl.hash||source.authContract!=='festapp'||source.supabaseUrl!==project.supabaseUrl
    ||!source.publicKeyPrefixes.some(p=>sourceUrl.pathname.slice(1).startsWith(p))
    ||targetUrl.origin!=='https://img.festapp.net'||!targetUrl.pathname.startsWith(`/images/lifecycle/${job.commandId}/`)
    ||targetUrl.pathname.includes('..')||sourceUrl.pathname.includes('..'))throw Error();
   const targetProject=resolveProjectByHostname(env,targetUrl.hostname);
   if(targetProject.supabaseUrl!==project.supabaseUrl)throw Error();
   const key=targetUrl.pathname.slice(1);const original=await source.publicBucket.get(assetKey(source,sourceUrl.pathname.slice(1)));
   const existing=await targetProject.publicBucket.head(assetKey(targetProject,key));
   if(!existing){
    if(!original||original.size>20*1024*1024||!/^image\/(png|jpeg|webp|gif)$/.test(original.httpMetadata?.contentType??''))throw Error('source_unavailable');
    for(const name of ['admit_image_upload_v1','admit_image_storage_v1']){
     if(await rpc(name,{p_bytes:original.size,p_occasion_id:job.occasionId,p_unit_id:null})!==true)throw Error('admission_rejected');
    }
    await targetProject.publicBucket.put(assetKey(targetProject,key),original.body,{httpMetadata:original.httpMetadata,customMetadata:{lifecycle:job.commandId,source:step.source}});
   }else if(existing.customMetadata?.lifecycle!==job.commandId||existing.customMetadata?.source!==step.source)throw Error('copy_identity_conflict');
   // Reauthorization and gallery registration happen after the durable object put.
   // A failed/lost response leaves the same deterministic object for retry.
   job=await rpc('record_occasion_media_step',{p_command_id:body.commandId,p_index:index}) as MediaJob;
  }
  job=await rpc('finish_occasion_media_job',{p_command_id:body.commandId}) as MediaJob;
  return jsonResponse({commandId:job.commandId,occasionId:job.occasionId,state:job.state});
 }catch(error){const status=(error as {status?:number}).status;return errorResponse(status===401||status===403?403:503,status===401||status===403?'FORBIDDEN':'LIFECYCLE_PENDING','Resume the same lifecycle command',true);}
}
