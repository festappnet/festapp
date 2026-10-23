import {z} from 'zod';
import {check,upstream,OperationError} from '../errors.mjs';
const id=z.number().int().positive().max(Number.MAX_SAFE_INTEGER),revision=z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const spots=z.array(id).min(1).max(100).refine(a=>new Set(a).size===a.length);
const affected=z.array(id).min(1).max(1000).refine(a=>new Set(a).size===a.length);
const seat=z.strictObject({spotId:id,nodeId:z.uuid(),title:z.string().nullable(),productId:id.nullable(),productTitle:z.string().nullable(),selectionUnitId:z.uuid().nullable(),groupNodeId:z.uuid().nullable(),blocked:z.boolean(),state:z.enum(['available','selected','ordered','used']),canBlock:z.boolean()});
export const seatDataSchemas={
 'seats.list':z.strictObject({occasionId:id,blueprint:z.strictObject({id,title:z.string().nullable(),layoutRevision:revision}),seats:z.array(seat).max(100),nextCursor:id.nullable(),readAt:z.iso.datetime({offset:true})}),
 'seats.preview_block':z.strictObject({occasionId:id,blueprintId:id,layoutRevision:revision,requestedSpotIds:spots,affectedSpotIds:affected,blocked:z.boolean(),seats:z.array(seat).max(1000),canApply:z.boolean(),readAt:z.iso.datetime({offset:true})}),
 'seats.block':z.strictObject({occasionId:id,commandId:z.uuid(),status:z.enum(['applied','unchanged']),blueprintId:id,layoutRevision:revision,affectedSpotIds:affected,blocked:z.boolean()}),
};
export const seatDescriptors=[
 {id:'seats.list',name:'festapp_seats_list',description:'Inspect bounded addressed-seat rows using the same lifecycle facts as the administration map. Supply blueprintId or omit it for the first canonical plan, matching the current editor. Page by spot ID using nextCursor as after. blocked is a separate saved binding flag; selected means an active temporary hold, ordered is an allocated item, used a checked-in ticket. These states are not a checkout availability promise. No reservation secrets, order/customer IDs or geometry are returned.',input:z.strictObject({occasionId:id,blueprintId:id.optional(),after:id.optional(),limit:z.number().int().min(1).max(100).default(50)}),domainReadOnly:true},
 {id:'seats.preview_block',name:'festapp_seats_preview_block',description:'Preview blocking or unblocking selected addressed seats without saving. The canonical selection-unit owner expands complete atomic groups, including companions not explicitly requested. Review every affectedSpotId, current lifecycle and original layoutRevision; obtain approval for this exact expanded set and target blocked value before calling festapp_seats_block. canApply false means at least one member is ordered/used/held; no subset will be silently applied. At most 100 requested and 1000 expanded seats; larger selections reject without truncation.',input:z.strictObject({occasionId:id,blueprintId:id,spotIds:spots,blocked:z.boolean()}),domainReadOnly:true},
 {id:'seats.block',name:'festapp_seats_block',description:'Block or unblock an explicitly approved complete selection through the same canonical blueprint aggregate save owner as administration. First preview, then supply its requested spotIds, full affectedSpotIds, layoutRevision and blocked target. This saves one receipt and changes no geometry or other editor draft. Sold/used/held members, changed expansion or a stale revision reject the entire batch. Blocking is distinct from releasing a hold or cancelling a ticket. Retry an uncertain response with identical commandId and payload; rejection requires a new preview/decision.',input:z.strictObject({occasionId:id,blueprintId:id,spotIds:spots,affectedSpotIds:affected,layoutRevision:revision,blocked:z.boolean(),commandId:z.uuid()}),domainReadOnly:false,idempotent:true,destructive:true},
];
export async function invokeSeatOperation(owner,client,operation,args){
 const scope=await owner.delegatedContext(client,args.occasionId);
 const base={p_occasion:args.occasionId,p_organization:scope.organizationId,p_unit:scope.unitId,p_blueprint:args.blueprintId??null};
 const list=operation==='seats.list',write=operation==='seats.block';
 const {data,error}=await client.rpc(list?'get_blueprint_seats':write?'block_blueprint_seats':'preview_blueprint_seat_block',list?{...base,p_after:args.after??null,p_limit:args.limit}:{...base,p_spots:args.spotIds,p_blocked:args.blocked,...(write?{p_affected_spots:args.affectedSpotIds,p_expected_revision:args.layoutRevision,p_command_id:args.commandId}:{})});
 if(['40001','40P01'].includes(error?.code))throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND',true);
 if(['22023','23514','54000'].includes(error?.code))throw new OperationError('SEAT_SELECTION_REJECTED');
 upstream(error);
 if(!write){check(data?.occasionId===args.occasionId);return seatDataSchemas[operation].parse(data);}
 if(data?.code===410)throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
 if(data?.status==='rejected')throw new OperationError(data.data?.reason==='BLUEPRINT_REVISION_CONFLICT'?'SEAT_REVISION_CHANGED_RELOAD_REQUIRED':'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT');
 check(data?.code===200&&data?.mutation?.commandId===args.commandId&&data?.mutation?.receiptId===args.commandId);
 return seatDataSchemas[operation].parse({occasionId:args.occasionId,commandId:args.commandId,status:data.status,...data.data});
}
