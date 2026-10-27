import {z} from 'zod';
import {check,upstream,OperationError} from '../errors.mjs';
const id=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const fingerprint=z.string().regex(/^[a-f0-9]{64}$/);
export const scannerDescriptors=[
 {id:'scanner.inspect',name:'festapp_scanner_inspect',domainReadOnly:true,input:z.strictObject({occasionId:id,ticketId:id}),description:'Read one issued ticket admission state and original eligibility fingerprint through the existing scanner projection and live scanner editor right. No QR, ticket symbol, customer details or session token. Does not admit anyone.'},
 {id:'scanner.admit',name:'festapp_scanner_admit',domainReadOnly:false,idempotent:true,destructive:true,input:z.strictObject({occasionId:id,ticketId:id,operationId:z.uuid(),eligibilityFingerprint:fingerprint,settingsRevision:id,confirmUnpaid:z.boolean(),capturedAt:z.iso.datetime({offset:true})}),description:'Explicitly admit the exact inspected ticket through existing scanner operation receipts, eligibility, unpaid confirmation and admission rules. Obtain approval before recording entry. Never infer unpaid approval. Retry uncertainty with identical operationId and the original complete payload, including capturedAt. Conflict requires a fresh inspection and decision. No scanner credentials leave SQL; this does not mark payment or send tickets.'},
];
export const scannerDataSchemas={
 'scanner.inspect':z.strictObject({ticketId:id,state:z.string(),settingsRevision:id,admissionAllowed:z.boolean(),requiresUnpaidConfirmation:z.boolean(),eligibilityFingerprint:fingerprint}),
 'scanner.admit':z.strictObject({operationId:z.uuid(),ticketId:id,outcome:z.enum(['accepted','conflict','rejected']),reason:z.string(),committedAt:z.string(),replayed:z.boolean()}),
};
export async function invokeScannerOperation(owner,client,operation,args){
 const scope=await owner.delegatedContext(client,args.occasionId);const {occasionId,...payload}=args;
 const {data,error}=await client.rpc('manage_scanner_authoring',{p_occasion:occasionId,p_organization:scope.organizationId,p_unit:scope.unitId,p_action:operation.split('.')[1],p_payload:payload});
 if(error?.code==='22023')throw new OperationError('SCANNER_INTENT_REJECTED');
 if(['40001','40P01'].includes(error?.code))throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND',true);
 upstream(error);
 if(operation==='scanner.inspect')return scannerDataSchemas[operation].parse(data);
 if(data?.code===429)throw new OperationError('SCANNER_RATE_LIMITED_RETRY_SAME_OPERATION',true);
 const receipt=data?.data?.[0];check(data?.code===200&&receipt?.operation_id===args.operationId&&receipt?.ticket_id===args.ticketId);
 return scannerDataSchemas[operation].parse({operationId:receipt.operation_id,ticketId:receipt.ticket_id,outcome:receipt.outcome,reason:receipt.reason,committedAt:receipt.committed_at,replayed:receipt.replayed??false});
}
