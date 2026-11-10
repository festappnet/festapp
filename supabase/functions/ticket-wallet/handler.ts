import { issueTicketWallet, type WalletRpc } from '../_shared/ticketWallet.ts';
import type { GoogleWallet } from '../_shared/googleWallet.ts';
export function walletHandler(rpc:WalletRpc,google:()=>Promise<GoogleWallet>,origins:string[]) {
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
   const body=JSON.parse(text);
   if(!body||typeof body.token!=='string'||! /^[a-f0-9]{64}$/.test(body.token)||Object.keys(body).some(k=>k!=='token'))return Response.json({error:'wallet_unavailable'},{status:400,headers});
   // The trusted gateway must replace, rather than append arbitrary client IP headers.
   const source=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
   const result=await issueTicketWallet(body.token,source,origin,rpc,await google());
   return Response.json(result??{error:'wallet_unavailable'},{status:result?200:404,headers});
  }catch(error){return Response.json({error:error instanceof SyntaxError?'wallet_unavailable':'wallet_retry'},{status:error instanceof SyntaxError?400:503,headers});}
 };
}
