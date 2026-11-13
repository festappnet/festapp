import type {WalletRegistry} from '../_shared/wallet/registry.ts';
export function walletHandler(registry:WalletRegistry,origins:string[]) {
 return async(req:Request)=>{
  const origin=req.headers.get('origin')||'';
  const headers:Record<string,string>={'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Vary':'Origin','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'content-type, apikey, authorization, x-client-info'};
  if(!origins.includes(origin))return Response.json({error:'wallet_unavailable'},{status:403,headers});
  headers['Access-Control-Allow-Origin']=origin;
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(req.method!=='POST')return new Response(null,{status:405,headers});
  try {
   if(Number(req.headers.get('content-length'))>1024)return Response.json({error:'wallet_unavailable'},{status:400,headers});
   const reader=req.body?.getReader();if(!reader)throw new SyntaxError();
   const chunks:Uint8Array[]=[];let total=0;
   try {
    while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>1024){await reader.cancel();throw new SyntaxError();}chunks.push(value);}
   }finally{reader.releaseLock();}
   const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   const text=new TextDecoder().decode(bytes);
   const isForm=req.headers.get('content-type')?.split(';')[0]==='application/x-www-form-urlencoded';
   const form=isForm?new URLSearchParams(text):null;
   const body=form?Object.fromEntries(form):JSON.parse(text);
   if(!body||typeof body.token!=='string'||! /^[a-f0-9]{64}$/.test(body.token)||Object.keys(body).some(k=>!['token','provider'].includes(k))||
    (body.provider!==undefined&&!registry.has(body.provider))||
    (form&&(form.getAll('token').length!==1||form.getAll('provider').length!==1)))return Response.json({error:'wallet_unavailable'},{status:400,headers});
   // The trusted gateway must replace, rather than append arbitrary client IP headers.
   const source=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
   const connector=registry.resolve(body.provider??registry.defaultId);
   if(form&&connector.delivery!=='file')return Response.json({error:'wallet_unavailable'},{status:400,headers});
   const result=await connector.issue({token:body.token,source,origin});
   if(!result)return Response.json({error:'wallet_unavailable'},{status:404,headers});
   if(result.kind==='file'){
    if(!/^[a-zA-Z0-9_.-]+$/.test(result.filename))throw new Error('wallet_filename');
    return new Response(result.bytes,{headers:{...headers,'Content-Type':result.contentType,'Content-Disposition':`attachment; filename="${result.filename}"`,'X-Content-Type-Options':'nosniff'}});
   }
   return Response.json({url:result.url,state:result.state},{headers});
  }catch(error){return Response.json({error:error instanceof SyntaxError?'wallet_unavailable':'wallet_retry'},{status:error instanceof SyntaxError?400:503,headers});}
 };
}
