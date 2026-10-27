import {describe,it,expect,vi} from 'vitest';
import {handleOccasionLifecycle} from '../../src/occasion-lifecycle';
import type {Env} from '../../src/types';
const command='00000000-0000-4000-8000-000000000021';
const source='https://img.festapp.net/images/source.jpg';
const target=`https://img.festapp.net/images/lifecycle/${command}/${'a'.repeat(64)}`;
function fixture(){
 const job={commandId:command,occasionId:42,action:'copy',state:'pending',media:[{field:'image',source,target,ready:false},{field:'background',source,target,ready:false}]};
 const objects=new Map<string,{customMetadata:Record<string,string>}>();
 const bucket={get:vi.fn(async()=>({size:8,body:new Uint8Array([137,80,78,71]),httpMetadata:{contentType:'image/png'}})),head:vi.fn(async(key:string)=>objects.get(key)??null),put:vi.fn(async(key:string,_body:unknown,options:{customMetadata:Record<string,string>})=>{objects.set(key,{customMetadata:options.customMetadata});return{};})};
 const env={IMAGES_BUCKET:bucket,IMAGES_PRIVATE_BUCKET:bucket,SUPABASE_URL:'https://api.festapp.net',SUPABASE_ANON_KEY:'fixture',SUPABASE_URL_A:'https://api.festapp.net',SUPABASE_ANON_KEY_A:'fixture-a'} as unknown as Env;
 let loseRecord=false,denied=false,denyAfterPut=false,admission=true;
 const fetcher=vi.fn(async(input:RequestInfo|URL,init?:RequestInit)=>{
  const url=new URL(String(input));expect(url.origin).toBe('https://api.festapp.net');expect(init?.headers).toMatchObject({Authorization:'Bearer fixture-user-jwt'});
  const name=url.pathname.split('/').pop();const args=JSON.parse(String(init?.body));
  if(denied||(denyAfterPut&&bucket.put.mock.calls.length))return new Response('{}',{status:403});
  if(name==='get_occasion_media_job')return Response.json(job);
  if(name?.startsWith('admit_image_'))return Response.json(admission);
  if(name==='record_occasion_media_step'){
   if(loseRecord){loseRecord=false;return new Response('{}',{status:503});}
   job.media[args.p_index].ready=true;return Response.json(job);
  }
  if(name==='finish_occasion_media_job'){expect(job.media.every(x=>x.ready)).toBe(true);job.state='complete';return Response.json(job);}
  throw Error('unexpected RPC '+name);
 }) as typeof fetch;
 const request=(extra={})=>new Request('https://image-api.festapp.net/occasion-lifecycle',{method:'POST',headers:{Authorization:'Bearer fixture-user-jwt'},body:JSON.stringify({projectId:'default',commandId:command,...extra})});
 return{job,bucket,objects,env,fetcher,request,lose:()=>{loseRecord=true;},revoke:()=>{denied=true;},revokeAfterPut:()=>{denyAfterPut=true;},denyAdmission:()=>{admission=false;}};
}
describe('resumable ordinary-user occasion media',()=>{
 it('reuses one deterministic object and one job after a lost registration acknowledgement',async()=>{
  const f=fixture();f.lose();expect((await handleOccasionLifecycle(f.request(),f.env,f.fetcher)).status).toBe(503);expect(f.bucket.put).toHaveBeenCalledTimes(1);
  expect((await handleOccasionLifecycle(f.request(),f.env,f.fetcher)).status).toBe(200);expect(f.bucket.put).toHaveBeenCalledTimes(1);expect(f.job.media.every(x=>x.ready)).toBe(true);
  expect((await handleOccasionLifecycle(f.request(),f.env,f.fetcher)).status).toBe(200);expect(f.bucket.put).toHaveBeenCalledTimes(1);
 });
 it('checks ordinary authorization before touching R2 and checks it again after a put',async()=>{
  const first=fixture();first.revoke();expect((await handleOccasionLifecycle(first.request(),first.env,first.fetcher)).status).toBe(403);expect(first.bucket.get).not.toHaveBeenCalled();expect(first.bucket.put).not.toHaveBeenCalled();
  const second=fixture();second.revokeAfterPut();expect((await handleOccasionLifecycle(second.request(),second.env,second.fetcher)).status).toBe(403);expect(second.job.state).toBe('pending');expect(second.job.media.every(x=>!x.ready)).toBe(true);expect(second.objects.size).toBe(1);
 });
 it('never fetches arbitrary source URLs or accepts client actor/source overrides',async()=>{
  const f=fixture();f.job.media[0].source='https://untrusted.invalid/private';expect((await handleOccasionLifecycle(f.request(),f.env,f.fetcher)).status).toBe(503);expect(f.bucket.get).not.toHaveBeenCalled();
  expect((await handleOccasionLifecycle(f.request({actorId:'other-user'}),f.env,f.fetcher)).status).toBe(400);
 });
 it('retains canonical storage/upload admission and refuses a colliding object identity',async()=>{
  const f=fixture();f.denyAdmission();expect((await handleOccasionLifecycle(f.request(),f.env,f.fetcher)).status).toBe(503);expect(f.bucket.put).not.toHaveBeenCalled();
  const other=fixture();other.objects.set(new URL(target).pathname.slice(1),{customMetadata:{lifecycle:'other'}});expect((await handleOccasionLifecycle(other.request(),other.env,other.fetcher)).status).toBe(503);expect(other.bucket.put).not.toHaveBeenCalled();
 });
 it('reads the historical a namespace but writes the canonical default object key',async()=>{
  const f=fixture();for(const step of f.job.media)step.source='https://a.img.festapp.net/images/source.jpg';
  expect((await handleOccasionLifecycle(f.request({projectId:'a'}),f.env,f.fetcher)).status).toBe(200);
  expect(f.bucket.get).toHaveBeenCalledWith('imports/a/images/source.jpg');expect(f.bucket.put.mock.calls[0][0]).toBe(new URL(target).pathname.slice(1));
 });
});
