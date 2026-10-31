import {bankSyncRemote,bankSyncAccountError,bankSyncErrorCode} from './bankSyncRemote.ts';
type Claim = {id:number; token:string; remoteId:string};
type Rpc = (name:string,args:Record<string,unknown>)=>PromiseLike<{data:unknown;error:unknown}>;
/** Refreshes BankSync health only. Does not poll a bank or run control operations. */
export async function refreshNotificationCenterHealth(rpc:Rpc, remote=bankSyncRemote, now=()=>new Date()) {
 const {data,error}=await rpc('claim_notification_center_bank_health',{p_limit:4});
 if(error) throw new Error('notification_health_claim_failed');
 let completed=0;
 for(const claim of (data??[]) as Claim[]){
  let success:string|null=null, reason:string|null=null;
  try{
   if(!/^[0-9]+$/.test(claim.remoteId)) throw Error('invalid_mapping');
   const status=await remote(`/bank-accounts/${claim.remoteId}`);
   reason=bankSyncAccountError(status.api_last_error);
   success=typeof status.api_last_success_at==='string'?status.api_last_success_at:null;
  }catch(error){
   const code=bankSyncErrorCode(error);
   reason=code==='fio_token_invalid_or_inactive'||code==='fio_receiving_account_mismatch'?code:'transport_unavailable';
  }
  const saved=await rpc('complete_notification_center_bank_health',{
   p_connection:claim.id,p_token:claim.token,p_success_at:success,p_reason:reason,p_at:now().toISOString(),
  });
  if(saved.error) throw new Error('notification_health_commit_failed');
  completed++;
 }
 return completed;
}
