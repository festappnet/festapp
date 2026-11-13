import type {AppleWallet} from '../../appleWallet.ts';
import {APPLE_PASS_MIME} from '../../appleWallet.ts';
import {registerApplePass,reconcileAppleTicketWallet} from '../../appleWalletUpdates.ts';
import {walletHash} from '../identity.ts';
import type {WalletRpc,WalletConnector} from '../contracts.ts';
export async function issueAppleTicketWallet(token:string,source:string,origin:string,rpc:WalletRpc,apple:AppleWallet) {
 const params={p_hash:await walletHash(token),p_source:await walletHash(source)};
 const resolved=await rpc('resolve_ticket_wallet',params);
 if(!resolved||resolved.webOrigin!==origin||resolved.providers?.apple!==true||!['ACTIVE','COMPLETED'].includes(resolved.projection?.state))return null;
 if(resolved.applePassTypeIdentifier!==apple.credentials.passTypeIdentifier||resolved.appleTeamIdentifier!==apple.credentials.teamIdentifier)throw new Error('wallet_apple_identity');
 const registered=await registerApplePass(resolved,params.p_hash,rpc,apple);
 if(!registered)return null;
 const bytes=await apple.issue(resolved,resolved.projection,{authenticationToken:registered.authenticationToken});
 // Signing/artwork I/O must not expose a pass after a concurrent storno or scope change.
 const current=await rpc('resolve_ticket_wallet',params);
 if(JSON.stringify(current)!==JSON.stringify(resolved))return null;
 return bytes;
}

export function appleWalletConnector(rpc:WalletRpc,configured:()=>Promise<AppleWallet>):WalletConnector {
 return {id:'apple',delivery:'file',
  async issue(input){const bytes=await issueAppleTicketWallet(input.token,input.source,input.origin,rpc,await configured());return bytes?{kind:'file',bytes,contentType:APPLE_PASS_MIME,filename:'ticket.pkpass'}:null;},
  async reconcile(limit){return await reconcileAppleTicketWallet(rpc,await configured(),limit);}};
}
