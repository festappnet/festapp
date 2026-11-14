import {authorizeRequest} from '../_shared/auth.ts';
import {walletRegistry} from '../_shared/wallet/runtime.ts';
Deno.serve(async req=>{
 const headers={'Cache-Control':'no-store'};
 if(req.method!=='POST')return new Response(null,{status:405,headers});
 try {
  const body=await req.json();if(!body.requestSecret)return Response.json({error:'unauthorized'},{status:401,headers});
  await authorizeRequest({requestSecret:body.requestSecret});
  return Response.json(await walletRegistry.reconcile(),{headers});
 }catch{return Response.json({error:'wallet_sync_unavailable'},{status:503,headers});}
});
