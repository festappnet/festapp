import type {WalletIssueInput,WalletRpc,WalletPlan} from './contracts.ts';
import {walletHash} from './identity.ts';
/** Authorization and bounded selection are shared by all providers. IDs never come from the browser. */
export async function resolveWallet(input:WalletIssueInput,rpc:WalletRpc,provider:string) {
 const params={p_hash:await walletHash(input.token),p_source:await walletHash(input.source)};
 const scope=await rpc('resolve_ticket_wallet',params);
 if(!scope||scope.webOrigin!==input.origin||scope.providers?.[provider]===false||
  !['ACTIVE','COMPLETED'].includes(scope.state??scope.projection?.state))return null;
 return {scope,params};
}
export function walletMembers(scope:any):any[]{return scope.tickets??[scope];}
export function walletPlan(scope:any,parts:any[][]):WalletPlan {
 return {kind:scope.kind??'ticket',revision:scope.revision,ticketCount:scope.ticketCount??1,originalCount:scope.originalCount??1,
  state:scope.state??scope.projection?.state,parts:parts.map(items=>items.length)};
}
export async function walletSelection(input:WalletIssueInput,rpc:WalletRpc,provider:string,partition:(scope:any)=>Promise<any[][]>) {
 const resolved=await resolveWallet(input,rpc,provider);if(!resolved)return null;
 const {scope,params}=resolved;
 if(scope.kind!=='collection'){
  if((input.part??0)!==0||(input.revision!==undefined&&input.revision!==scope.revision))return null;
  return {scope,params,items:walletMembers(scope)};
 }
 // Old cached clients cannot accidentally download only the first part of an order.
 if(!input.revision||input.revision!==scope.revision)return null;
 const part=(await partition(scope))[input.part??0];if(!part)return null;
 const items=await rpc('get_ticket_wallet_projections',{p_hash:params.p_hash,p_tickets:part.map(item=>item.ticketId),p_revision:scope.revision});
 return Array.isArray(items)&&items.length===part.length?{scope,params,items}:null;
}
export function chunks<T>(items:T[],size=10):T[][] {
 return Array.from({length:Math.ceil(items.length/size)},(_,i)=>items.slice(i*size,(i+1)*size));
}
export async function walletUnchanged(selection:{scope:any;params:any;items:any[]},rpc:WalletRpc) {
 const current=await rpc('resolve_ticket_wallet',selection.params);
 if(JSON.stringify(current)!==JSON.stringify(selection.scope))return false;
 if(selection.scope.kind!=='collection')return true;
 const items=await rpc('get_ticket_wallet_projections',{p_hash:selection.params.p_hash,p_tickets:selection.items.map(item=>item.ticketId),p_revision:selection.scope.revision});
 return JSON.stringify(items)===JSON.stringify(selection.items);
}
