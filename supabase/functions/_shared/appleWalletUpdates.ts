import {appleWalletSerial,type AppleWallet} from './appleWallet.ts';
import {walletHash} from './wallet/identity.ts';
import {openEmail,sealEmail} from './emailPayload.ts';
import type {WalletRpc} from './wallet/contracts.ts';

export async function applePassAuthentication(context:any) {
 const source=await openEmail<any>(context.authSealed);
 if(source.purpose!=='apple_wallet_auth'||source.serial!==context.serial||source.passTypeIdentifier!==context.passTypeIdentifier||
  typeof source.token!=='string'||await walletHash(source.token)!==context.authHash)throw new Error('wallet_apple_source');
 return source.token as string;
}
export async function registerApplePass(resolved:any,capabilityHash:string,rpc:WalletRpc,apple:AppleWallet) {
 const serial=await appleWalletSerial(resolved);
 const params={p_capability_hash:capabilityHash,p_serial:serial,p_pass_type:apple.credentials.passTypeIdentifier,p_team:apple.credentials.teamIdentifier};
 let context=await rpc('register_apple_ticket_wallet',params);
 if(!context) {
  const token=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
  const sealed=await sealEmail({purpose:'apple_wallet_auth',serial,passTypeIdentifier:apple.credentials.passTypeIdentifier,token});
  context=await rpc('register_apple_ticket_wallet',{...params,p_auth_hash:await walletHash(token),p_sealed:sealed});
 }
 if(!context)return null;
 return {context,authenticationToken:await applePassAuthentication(context)};
}
export async function reconcileAppleTicketWallet(rpc:WalletRpc,apple:AppleWallet,limit=25) {
 let synced=0,failed=0;const deadline=Date.now()+40000;
 for(let count=0;count<limit&&Date.now()<deadline;count++) {
  const claim=await rpc('claim_apple_ticket_wallet');if(!claim)break;
  const params={p_ticket:claim.ticketId,p_lease:claim.lease};
  try {
   if(claim.passTypeIdentifier!==apple.credentials.passTypeIdentifier||claim.teamIdentifier!==apple.credentials.teamIdentifier)throw new Error('wallet_apple_identity');
   const targets=await rpc('apple_wallet_push_targets',params);
   for(const target of targets) {
    if(Date.now()>=deadline)break;
    // Confirm the lease immediately before every external request, including retries.
    await rpc('apple_wallet_push_targets',params);
    const result=await apple.push(target.pushToken);
    if(!await rpc('finish_apple_wallet_push',{...params,p_push_token:target.pushToken,p_tag:claim.updateTag,p_invalid:result==='invalid'}))throw new Error('wallet_lease_lost');
   }
   if(!await rpc('finish_apple_ticket_wallet',{...params,p_ok:true}))throw new Error('wallet_lease_lost');
   synced++;
  }catch{await rpc('finish_apple_ticket_wallet',{...params,p_ok:false});failed++;}
 }
 return {synced,failed};
}
