import type {AppleWallet} from '../../appleWallet.ts';
import {APPLE_PASS_MIME} from '../../appleWallet.ts';
import {registerApplePass,reconcileAppleTicketWallet} from '../../appleWalletUpdates.ts';
import type {WalletRpc,WalletConnector} from '../contracts.ts';
import {zipSync} from 'npm:fflate@0.8.3';
import {chunks,resolveWallet,walletMembers,walletPlan,walletSelection,walletUnchanged} from '../collection.ts';
import type {WalletIssueInput} from '../contracts.ts';
const partition=async(scope:any)=>chunks(walletMembers(scope));
async function issueApple(input:WalletIssueInput,rpc:WalletRpc,apple:AppleWallet) {
 const selection=await walletSelection(input,rpc,'apple',partition);if(!selection)return null;
 const {scope,items}=selection;
 if(scope.providers?.apple!==true)return null;
 if(scope.applePassTypeIdentifier!==apple.credentials.passTypeIdentifier||scope.appleTeamIdentifier!==apple.credentials.teamIdentifier)throw new Error('wallet_apple_identity');
 const passes:Uint8Array<ArrayBuffer>[]=[];
 for(const item of items){
  const registered=await registerApplePass(item,item.capabilityHash??selection.params.p_hash,rpc,apple);
  if(!registered)return null;
  passes.push(await apple.issue(item,item.projection,{authenticationToken:registered.authenticationToken}));
 }
 // Recheck every selected projection after signing/artwork I/O, including QR/seat changes.
 if(!await walletUnchanged(selection,rpc))return null;
 if(scope.kind!=='collection')return {kind:'file' as const,bytes:passes[0],contentType:APPLE_PASS_MIME,filename:'ticket.pkpass'};
 const bytes=zipSync(Object.fromEntries(passes.map((pass,index)=>[`ticket-${index+1}.pkpass`,pass])),{level:0});
 if(bytes.length>150_000_000)throw new Error('wallet_bundle_size');
 return {kind:'file' as const,bytes,contentType:'application/vnd.apple.pkpasses',filename:'tickets.pkpasses'};
}
/** Existing single-ticket callers keep their exact byte contract. */
export async function issueAppleTicketWallet(token:string,source:string,origin:string,rpc:WalletRpc,apple:AppleWallet) {
 return (await issueApple({token,source,origin},rpc,apple))?.bytes??null;
}

export function appleWalletConnector(rpc:WalletRpc,configured:()=>Promise<AppleWallet>):WalletConnector {
 return {id:'apple',delivery:'file',
  async plan(input){const resolved=await resolveWallet(input,rpc,'apple');return resolved?walletPlan(resolved.scope,await partition(resolved.scope)):null;},
  async issue(input){return await issueApple(input,rpc,await configured());},
  async reconcile(limit){return await reconcileAppleTicketWallet(rpc,await configured(),limit);}};
}
