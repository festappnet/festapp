import {APPLE_PASS_MIME,type AppleWallet} from '../_shared/appleWallet.ts';
import {applePassAuthentication} from '../_shared/appleWalletUpdates.ts';
import {walletHash} from '../_shared/wallet/identity.ts';
import type {WalletRpc} from '../_shared/wallet/contracts.ts';
const headers={'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'};
async function boundedJson(req:Request) {
 const reader=req.body?.getReader();if(!reader)throw new SyntaxError();let size=0;const chunks:Uint8Array[]=[];
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>16384){await reader.cancel();throw new SyntaxError();}chunks.push(value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 return JSON.parse(new TextDecoder().decode(bytes));
}
export function appleWalletHandler(rpc:WalletRpc,configured:()=>Promise<AppleWallet>) {
 return async(req:Request)=>{
  const response=(status:number)=>new Response(null,{status,headers});
  try {
   const url=new URL(req.url);const parts=url.pathname.replace(/^.*\/apple-wallet\/?/,'').split('/').filter(Boolean).map(decodeURIComponent);
   if(parts[0]!=='v1')return response(404);
   const source=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
   if(!await rpc('allow_apple_wallet_request',{p_source:await walletHash(source)}))return response(429);
   if(parts.length===2&&parts[1]==='log'&&req.method==='POST'){await boundedJson(req);return response(200);} // Discard logs: no QR, tokens or device data in logs.
   const auth=/^ApplePass ([a-f0-9]{64})$/.exec(req.headers.get('authorization')||'');
   if(parts[1]==='devices'&&parts[3]==='registrations'&&parts.length===6&&['POST','DELETE'].includes(req.method)) {
    if(!auth)return response(401);
    const body=req.method==='POST'?await boundedJson(req):null;
    if(body&&(!body.pushToken||Object.keys(body).some(k=>k!=='pushToken')))return response(400);
    return response(await rpc('register_apple_wallet_device',{p_device:parts[2],p_pass_type:parts[4],p_serial:parts[5],p_auth_hash:await walletHash(auth[1]),p_push_token:body?.pushToken??null,p_remove:req.method==='DELETE'}));
   }
   if(parts[1]==='devices'&&parts[3]==='registrations'&&parts.length===5&&req.method==='GET') {
    const result=await rpc('list_apple_wallet_updates',{p_device:parts[2],p_pass_type:parts[4],p_since:url.searchParams.get('passesUpdatedSince')});
    return result?Response.json(result,{headers}):response(204);
   }
   if(parts[1]==='passes'&&parts.length===4&&req.method==='GET') {
    if(!auth)return response(401);
    const context=await rpc('get_apple_ticket_wallet',{p_pass_type:parts[2],p_serial:parts[3],p_auth_hash:await walletHash(auth[1])});
    if(!context)return response(401);
    const etag='"'+context.updateTag+'"';
    const lastModified=new Date(context.updatedAt).toUTCString();
    if(req.headers.get('if-none-match')===etag||(!req.headers.has('if-none-match')&&Date.parse(req.headers.get('if-modified-since')||'')>=Date.parse(lastModified)))return new Response(null,{status:304,headers:{...headers,ETag:etag,'Last-Modified':lastModified}});
    const apple=await configured();
    if(context.passTypeIdentifier!==apple.credentials.passTypeIdentifier||context.teamIdentifier!==apple.credentials.teamIdentifier)return response(503);
    const bytes=await apple.issue(context,context.projection,{authenticationToken:await applePassAuthentication(context)});
    const current=await rpc('get_apple_ticket_wallet',{p_pass_type:parts[2],p_serial:parts[3],p_auth_hash:await walletHash(auth[1])});
    if(!current||current.updateTag!==context.updateTag)return response(503);
    return new Response(bytes,{headers:{...headers,'Content-Type':APPLE_PASS_MIME,'Content-Disposition':'attachment; filename="ticket.pkpass"','Last-Modified':lastModified,ETag:etag}});
   }
   return response(404);
  }catch(error){return response(error instanceof SyntaxError||error instanceof URIError?400:503);}
 };
}
