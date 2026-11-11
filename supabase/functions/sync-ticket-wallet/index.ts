import { authorizeRequest } from '../_shared/auth.ts';
import { emailRpc } from '../_shared/emailQueueClient.ts';
import { configuredGoogleWallet } from '../_shared/googleWallet.ts';
import { reconcileTicketWallet } from '../_shared/ticketWallet.ts';
Deno.serve(async req=>{
 const headers={'Cache-Control':'no-store'};
 if(req.method!=='POST')return new Response(null,{status:405,headers});
 try {
  const body=await req.json();if(!body.requestSecret)return Response.json({error:'unauthorized'},{status:401,headers});
  await authorizeRequest({requestSecret:body.requestSecret});
  return Response.json(await reconcileTicketWallet(emailRpc,await configuredGoogleWallet()),{headers});
 }catch{return Response.json({error:'wallet_sync_unavailable'},{status:503,headers});}
});
