import {z} from 'zod';
import {check,upstream,OperationError,commandEdgeResponse} from '../errors.mjs';
const id=z.number().int().positive().max(Number.MAX_SAFE_INTEGER), version=z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const scope={unitId:id}, target={...scope,accountId:id}, command={commandId:z.uuid()};
const page={limit:id.max(100).default(50),after:id.optional()};
const items=z.strictObject({items:z.array(z.json()).max(100)});
const mutation=z.strictObject({commandId:z.uuid(),status:z.enum(['applied','unchanged']),data:z.json(),detailsSync:z.enum(['not-required','pending','attempted']).optional()});
const descriptors=[],schemas={};
function add(op,input,description,schema=mutation){const read=schema!==mutation;descriptors.push({id:op,name:'festapp_'+op.replaceAll('.','_').replace(/[A-Z]/g,c=>'_'+c.toLowerCase()),input:z.strictObject(input),description,domainReadOnly:read,...(!read?{idempotent:true,destructive:true}:{})});schemas[op]=schema;}
const approve=' Obtain approval for the exact operation. Preserve commandId and payload across uncertain responses. Original SQL owns permissions, validation, receipts and provider intents. Never infer successful external completion from an accepted local command.';
add('banks.list',{...scope,...page},'List a bounded page of this organizer\'s linked bank accounts. Account numbers are explicit banking data. No credentials or pairing addresses.',items);
add('banks.candidates',{...scope,...page},'List a bounded page of the caller\'s own administrated bank accounts eligible for linking to this organizer. A tenant admin is not a bank admin.',items);
add('banks.users',{...target,limit:page.limit,afterUser:z.uuid().optional()},'Read a bounded bank-member page including email and admin/support roles. Requires an actual selected-unit link and the existing bank-user read permission.',items);
add('banks.status',target,'Read the persisted BankSync connection status for an actually linked account, with both live account-admin and linked non-demo unit-manager roles. No credentials, pairing address or raw provider errors.',z.strictObject({connection:z.json()}));
add('banks.operations',{...target,limit:page.limit,before:z.strictObject({createdAt:z.iso.datetime({offset:true}),id:z.uuid()}).optional()},'Read a bounded page of durable BankSync operation IDs and states for this linked account. No raw requests, provider results or encrypted credentials.',items);
add('banks.observations',{...target,limit:page.limit},'Read bounded unresolved quarantined delivery metadata from the canonical bank observation owner. No bank transaction payload or mail content.',items);
add('banks.save',{...scope,...command,accountId:id.nullable(),accountNumber:z.string().trim().min(1).max(128),title:z.string().max(120),type:z.enum(['FIO','OTHER']),currencies:z.array(z.string().regex(/^[A-Z]{3}$/)).min(1).max(20),displayNumber:z.string().max(200).nullable(),creditorName:z.string().max(200).nullable()},'Create and link a bank account, or save exact current details through the same receipted owner as Flutter. Existing connection identity cannot be changed. An update queues its durable provider details intent atomically.'+approve);
add('banks.link',{...target,...command,priority:z.number().int().min(0).max(100000).nullable(),force:z.boolean().default(false)},'Link/reorder a bank account, or unlink with priority null. Linking requires account-admin AND target-unit manager. Reordering/unlinking retains the UI\'s manager rule and currency dependency checks; force must be explicitly approved.'+approve);
add('banks.user',{...target,...command,email:z.email().max(254),isAdmin:z.boolean(),isSupport:z.boolean()},'Set exact bank-member flags for an existing user by email. Both false removes access. Requires bank-admin AND actual linked unit-manager; never substitutes a tenant-admin role.'+approve);
for(const action of ['sync','suspend','resume'])add('banks.'+action,{...target,...command},'Request the existing BankSync '+action+' operation through its durable request/lease/recovery owner. Credential setup and pairing remain in the human UI.'+approve);
for(const action of ['status','disconnectImpact'])add('cards.'+action,scope,'Read canonical card-provider '+action+' for this explicitly consented organizer, using the ordinary manager boundary and server-selected provider mode. No OAuth secrets.',z.strictObject({state:z.json()}));
add('cards.pause',{...scope,...command,paused:z.boolean()},'Set the organizer card-payment pause to the explicit desired state through stripe-connect. Uses the shared immutable UI receipt; replay returns the original result without reapplying an older pause over a newer decision. Does not change provider-observed charge or payout facts.'+approve);
add('cards.disconnect',{...scope,...command,connectionId:z.uuid()},'Disconnect the inspected card connection using the existing durable disconnect intent, dependency checks and provider recovery. Inspect disconnect impact first. A pending intent is not completed disconnection.'+approve);
add('cards.refund.inspect',{occasionId:id,orderId:id},'Inspect provider-observed partial refund and current local admission decision for one stored scoped order. Ticket symbols and provider dashboard identifiers are withheld. This does not issue a refund.',z.strictObject({detail:z.json()}));
add('cards.refund.decide',{occasionId:id,orderId:id,...command,action:z.enum(['keep','cancel_selected']),ticketIds:z.array(id).max(1000),note:z.string().trim().min(3).max(500),expectedRefundedMinor:version},'Record the existing local admission decision after an observed partial card refund: keep tickets, or cancel the exact selected tickets. Original SQL verifies provider revision and eligibility. This does not move money or issue a provider refund.'+approve);
add('history.delete',{occasionId:id,orderId:id,historyId:id,...command},'Delete exactly one persisted order-history entry through the same receipted UI owner. This removes audit evidence, not the order, payment or current-state projection. Requires explicit approval and current organizer-manager rights; never infer this from history-read consent.'+approve);
add('orders.deletion.inspect',{occasionId:id,orderId:id},'Inspect canonical physical-deletion eligibility and the current order revision. Distinct from cancellation. Returns whether the organizer has Fakturoid configured; never returns provider credentials or invoice identifiers.',z.strictObject({revision:z.string().regex(/^[a-f0-9]{64}$/),hasFakturoid:z.boolean()}));
add('orders.delete',{occasionId:id,orderId:id,...command,expectedRevision:z.string().regex(/^[a-f0-9]{64}$/),deleteInvoice:z.boolean()},'Physically delete the approved exact order through the canonical UI owner. Distinct from cancelling tickets. Explicit deleteInvoice true uses the existing Fakturoid deletion gateway and recovery before SQL deletion; false leaves the external invoice untouched. Preserve the inspected revision and immutable commandId. The original waitlist, queue, batch and payment/dependency restrictions remain authoritative.'+approve);
export const financeDescriptors=descriptors,financeDataSchemas=schemas;
export async function invokeFinanceOperation(owner,client,op,args){
 const bound=(op.startsWith('cards.refund.')||op.startsWith('orders.')||op==='history.delete')?await owner.delegatedContext(client,args.occasionId):await owner.delegatedUnitContext(client,args.unitId);
 if(op==='history.delete'){
  const {data,error}=await client.rpc('delete_order_history_client_sync_v1',{p_history_id:args.historyId,p_command_id:args.commandId,p_occasion:args.occasionId,p_organization:bound.organizationId,p_unit:bound.unitId,p_order:args.orderId});upstream(error);check(data?.code===200&&data.mutation?.commandId===args.commandId,'HISTORY_DELETION_REJECTED');return{commandId:args.commandId,status:data.status,data:data.data};
 }
 if(op.startsWith('orders.')){
  const base={p_occasion:args.occasionId,p_organization:bound.organizationId,p_unit:bound.unitId,p_order:args.orderId};
  if(op==='orders.deletion.inspect'){const {data,error}=await client.rpc('get_delegated_order_deletion_context',base);upstream(error);return{revision:data.revision,hasFakturoid:data.hasFakturoid};}
  let result;
  if(args.deleteInvoice){result=commandEdgeResponse(await client.functions.invoke('delete-order',{body:{orderId:args.orderId,commandId:args.commandId,deleteFakturoidInvoice:true,delegatedScope:{occasionId:args.occasionId,...bound,expectedRevision:args.expectedRevision}}}),args.commandId);}
  else{const {data,error}=await client.rpc('delete_delegated_order_client_sync_v1',{...base,p_command_id:args.commandId,p_expected_revision:args.expectedRevision});upstream(error);result=data;}
  check(result?.code===200&&result.mutation?.commandId===args.commandId,'ORDER_DELETION_REJECTED');return{commandId:args.commandId,status:result.status,data:{orderId:args.orderId}};
 }
 if(op.startsWith('banks.')){
  const action=op.slice(6),{unitId,commandId,...payload}=args;
  if(['sync','suspend','resume'].includes(action)){
   const response=await client.functions.invoke('bank-sync-manage',{body:{account_id:args.accountId,operation:action,operation_id:commandId,delegatedScope:bound}});
   const data=commandEdgeResponse(response,commandId);check(!data?.error,'TEMPORARY_FAILURE_RETRY_SAME_COMMAND');
   // The original owner stores completion; require a fresh safe readback.
   const {data:state,error}=await client.rpc('manage_bank_authoring',{p_unit:unitId,p_organization:bound.organizationId,p_action:'status',p_payload:{accountId:args.accountId}});upstream(error);
   return{commandId,status:'applied',data:state};
  }
  const {data,error}=await client.rpc('manage_bank_authoring',{p_unit:unitId,p_organization:bound.organizationId,p_action:action,p_payload:payload,p_command_id:commandId??null});
  if(['22023','23514','P0001'].includes(error?.code))throw new OperationError('BANK_CHANGE_REJECTED');upstream(error);
  if(!commandId)return schemas[op].parse(data);
  if(data?.code===410)throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
  check(data?.code===200&&data.mutation?.commandId===commandId,'BANK_CHANGE_REJECTED');
  let detailsSync='not-required';
  if(data.data?.detailsSyncPending){detailsSync='pending';try{const response=await client.functions.invoke('bank-sync-manage',{body:{operation:'update_details',account_id:data.data.accountId,delegatedScope:bound}});if(!response.error&&!response.data?.error)detailsSync='attempted';}catch{/* Committed canonical intent remains pending for existing recovery. */}}
  return{commandId,status:data.status,data:data.data,detailsSync};
 }
 if(op.startsWith('cards.refund.')){
  const write=op.endsWith('.decide');const {data,error}=await client.rpc('manage_card_refund_authoring',{p_occasion:args.occasionId,p_organization:bound.organizationId,p_unit:bound.unitId,p_order:args.orderId,p_payload:write?{action:args.action,ticketIds:args.ticketIds,note:args.note,expectedRefundedMinor:args.expectedRefundedMinor}:null,p_command_id:args.commandId??null});upstream(error);
  if(write){check(data?.code===200&&data.mutation?.commandId===args.commandId,'REFUND_DECISION_REJECTED');return{commandId:args.commandId,status:data.status,data:{orderId:args.orderId}};}
  return{detail:data};
 }
 const action=op==='cards.pause'?(args.paused?'pause':'resume'):op==='cards.disconnectImpact'?'disconnect-impact':op.slice(6);
 // The Edge owner verifies unit manager and selects test/live mode itself.
 const response=await client.functions.invoke('stripe-connect',{body:{unitId:args.unitId,action,...(args.commandId?{commandId:args.commandId}:{}),...(args.connectionId?{connectionId:args.connectionId}:{})}});
 const data=commandEdgeResponse(response,args.commandId);check(!data?.error,'CARD_OPERATION_REJECTED');
 if(args.commandId){check(data?.code===200&&data.mutation?.commandId===args.commandId,'CARD_OPERATION_REJECTED');return{commandId:args.commandId,status:data.status,data:data.data};}
 return{state:data};
}
