import { GoogleWallet, walletHash, walletIds } from './googleWallet.ts';
export type WalletRpc=(name:string,params?:Record<string,unknown>)=>Promise<any>;
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
export async function issueTicketWallet(token:string,source:string,origin:string,rpc:WalletRpc,google:GoogleWallet) {
 const resolved=await rpc('resolve_ticket_wallet',{p_hash:await walletHash(token),p_source:await walletHash(source)});
 if(!resolved||resolved.webOrigin!==origin||!['ACTIVE','COMPLETED'].includes(resolved.projection?.state))return null;
 const ids=await walletIds(resolved);
 let claim=await rpc('claim_ticket_wallet',{p_ticket:resolved.ticketId,p_object:ids.objectId,p_class:ids.classId});
 if(!claim)throw new Error('wallet_busy');
 if(claim.kind==='class') {
  await synchronizeWallet(claim,rpc,google);
  claim=await rpc('claim_ticket_wallet',{p_ticket:resolved.ticketId});
  if(!claim)throw new Error('wallet_busy');
 }
 // Scope/state may have changed between resolve and claim.
 if(!['ACTIVE','COMPLETED'].includes(claim.projection?.state)) {
  await synchronizeWallet(claim,rpc,google);return null;
 }
 await synchronizeWallet(claim,rpc,google);
 return {url:await google.saveUrl(claim.objectId,origin),state:claim.projection.state};
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
