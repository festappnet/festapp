import {afterEach,describe,expect,it,vi} from 'vitest';
import {handleUpload} from '../../src/upload';
import {imageAttestationMessage} from '../../src/blueprint-assets';
import {validateBlueprintSvg} from '../../src/upload-policy';
import type {Env} from '../../src/types';
afterEach(()=>vi.unstubAllGlobals());
function setup(){
 const bytes=new Uint8Array([137,80,78,71,13,10,26,10]);
 const stored=new Set<string>();
 const bucket={put:vi.fn(async(key:string)=>{if(stored.has(key))return null;stored.add(key);return {}; }),delete:vi.fn(async(key:string)=>{stored.delete(key);})};
 const images={info:vi.fn(async()=>({format:'image/png',width:320,height:180})),input:vi.fn(()=>({transform:()=>({output:async()=>({response:()=>new Response(bytes)})})}))};
 const env={IMAGES:images,IMAGES_BUCKET:bucket,IMAGES_PRIVATE_BUCKET:bucket,SUPABASE_URL:'https://api.festapp.net',SUPABASE_ANON_KEY:'fixture',IMAGE_PROCESSING_SERVICE_SECRET:'local-test-only-secret-not-a-production-key'} as unknown as Env;
 const request=()=>{const form=new FormData();form.set('file',new File([bytes],'fixture.png',{type:'image/png'}));form.set('projectId','default');form.set('occasionId','12');form.set('profile','blueprint-background');return new Request('https://image-api.festapp.net/upload',{method:'POST',headers:{Authorization:'Bearer local-test-only'},body:form});};
 return{bucket,stored,env,request};
}
describe('verified immutable background upload',()=>{
 it('keeps concurrent successfully registered bytes when another upload acknowledgement fails',async()=>{
  const f=setup();let rejectFirst!:()=>void;let firstStarted!:()=>void;
  const started=new Promise<void>(resolve=>{firstStarted=resolve;});let registrations=0;
  vi.stubGlobal('fetch',vi.fn(async(url:string,init:RequestInit)=>{
   if(url.endsWith('/register_blueprint_image_asset')){
    const body=JSON.parse(init.body as string);registrations++;
    if(registrations===1){firstStarted();await new Promise<void>(resolve=>{rejectFirst=resolve;});return new Response('{}',{status:502});}
    return Response.json(body.p_asset);
   }
   return Response.json(true);
  }));
  const first=handleUpload(f.request(),f.env);await started;
  const second=await handleUpload(f.request(),f.env);expect(second.status).toBe(200);const ready=await second.json() as {key:string};
  rejectFirst();expect((await first).status).toBe(502);
  expect(f.stored.has(ready.key)).toBe(true);expect(f.bucket.delete).not.toHaveBeenCalled();
  expect(f.bucket.put.mock.calls[0][0]).toBe(f.bucket.put.mock.calls[1][0]);
  expect((f.bucket.put.mock.calls[0] as unknown[])[0]).toMatch(/^images\/12\/blueprint\/[a-f0-9]{64}\.png$/);
 });
 it('separates the attestation owner and rejects active/external SVG including CSS escapes',()=>{
  const asset={assetRef:'image:'+ 'a'.repeat(64),hash:'a'.repeat(64),url:'https://img.festapp.net/images/12/blueprint/x.png',width:320,height:180,mimeType:'image/png',byteLength:100,state:'ready' as const};
  expect(imageAttestationMessage(12,'default',asset,1).split('\n')[1]).toBe('occasion:12');
  expect(imageAttestationMessage(null,'default',asset,1,12).split('\n')[1]).toBe('unit:12');
  for(const unsafe of ['<script/>','<image href="https://external.invalid/a"/>','<rect style="fill:u\\72l(https://external.invalid/a)"/>','<use href="&#104;ttps://external.invalid/a"/>'])expect(()=>validateBlueprintSvg(`<svg width="20" height="20">${unsafe}</svg>`)).toThrow();
 });
});
