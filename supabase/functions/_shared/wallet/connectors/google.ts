import { GoogleWallet,walletIds } from '../../googleWallet.ts';
import type {WalletRpc,WalletConnector} from '../contracts.ts';
export async function synchronizeWallet(claim:any,rpc:WalletRpc,google:GoogleWallet) {
 try {
  await (claim.kind==='class'?google.synchronizeClass.bind(google):google.synchronize.bind(google))(claim,claim.projection,async()=>{
   const wait=await rpc('reserve_ticket_wallet_request',{p_ticket:claim.ticketId,p_lease:claim.lease});
   if(wait>0)await new Promise(resolve=>setTimeout(resolve,wait));
  });
  if(!await rpc('finish_ticket_wallet',{p_ticket:claim.ticketId,p_lease:claim.lease,p_ok:true}))throw new Error('wallet_lease_lost');
 }catch(error){
  await rpc('finish_ticket_wallet',{p_ticket:claim.ticketId,p_lease:claim.lease,p_ok:false,p_error:error instanceof Error?error.message:null});
  throw error;
 }
}
import {resolveWallet,walletMembers,walletPlan,walletSelection,walletUnchanged} from '../collection.ts';
import type {WalletIssueInput} from '../contracts.ts';
/** Google limits the signed save URL, not a fixed number of tickets. Measure the real JWT. */
async function partition(scope:any,google:GoogleWallet):Promise<any[][]> {
 const parts:any[][]=[];let part:any[]=[];
 for(const item of walletMembers(scope)){
  const candidate=[...part,item];
  try{
   if(candidate.length>10)throw new Error('wallet_link_length');
   await google.saveUrl(await Promise.all(candidate.map(async member=>(await walletIds(member)).objectId)),scope.webOrigin);
   part=candidate;
  }catch(error){
   if(!(error instanceof Error)||error.message!=='wallet_link_length'||!part.length)throw error;
   parts.push(part);part=[item];
   await google.saveUrl([(await walletIds(item)).objectId],scope.webOrigin);
  }
 }
 if(part.length)parts.push(part);return parts;
}
async function issueGoogle(input:WalletIssueInput,rpc:WalletRpc,google:GoogleWallet) {
 const selection=await walletSelection(input,rpc,'google',scope=>partition(scope,google));if(!selection)return null;
 const objectIds:string[]=[];
 for(const resolved of selection.items){
  const ids=await walletIds(resolved);
  let claim=await rpc('claim_ticket_wallet',{p_ticket:resolved.ticketId,p_object:ids.objectId,p_class:ids.classId});
  if(!claim)throw new Error('wallet_busy');
  if(claim.kind==='class') {
   await synchronizeWallet(claim,rpc,google);
   claim=await rpc('claim_ticket_wallet',{p_ticket:resolved.ticketId});
   if(!claim)throw new Error('wallet_busy');
  }
  if(!['ACTIVE','COMPLETED'].includes(claim.projection?.state)) {await synchronizeWallet(claim,rpc,google);return null;}
  await synchronizeWallet(claim,rpc,google);objectIds.push(claim.objectId);
 }
 if(!await walletUnchanged(selection,rpc))return null;
 return {url:await google.saveUrl(selection.scope.kind==='collection'?objectIds:objectIds[0],input.origin),state:selection.scope.state??selection.scope.projection.state};
}
export async function issueTicketWallet(token:string,source:string,origin:string,rpc:WalletRpc,google:GoogleWallet) {
 return await issueGoogle({token,source,origin},rpc,google);
}
export async function reconcileTicketWallet(rpc:WalletRpc,google:GoogleWallet,limit=200) {
 await rpc('maintain_ticket_wallet',{p_limit:100});
 let synced=0,failed=0;
 const deadline=Date.now()+45000;
 for(let n=0;n<limit && Date.now()<deadline;n++) {
  const claim=await rpc('claim_ticket_wallet',{});if(!claim)break;
  try{await synchronizeWallet(claim,rpc,google);synced++;}catch{failed++;}
 }
 return {synced,failed};
}


export function googleWalletConnector(rpc:WalletRpc,configured:()=>Promise<GoogleWallet>):WalletConnector {
 return {id:'google',delivery:'redirect',
  async plan(input){const resolved=await resolveWallet(input,rpc,'google');return resolved?walletPlan(resolved.scope,await partition(resolved.scope,await configured())):null;},
  async issue(input){const result=await issueGoogle(input,rpc,await configured());return result?{kind:'redirect',...result}:null;},
  async reconcile(limit){return await reconcileTicketWallet(rpc,await configured(),limit);}};
}
