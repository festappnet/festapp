import { z } from 'zod';
import { productAdminSchema } from './products.mjs';
import { check, upstream, OperationError } from '../errors.mjs';
const id=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const version=z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const capacity=z.number().int().min(0).max(1000000);
const preparation=z.strictObject({
 product:productAdminSchema.extend({occasion:id,type:z.literal('spot'),type_title:z.string().nullable()}),
 pool:z.object({id,occasion:id,title:z.string().nullable(),sellable_capacity:capacity.nullable(),aggregate_version:version,data:z.json()}),
 context:z.object({id,inventory_pool:id,title:z.string().nullable(),block_date:z.string().nullable()}),
 resource:z.object({id,inventory_pool:id,title:z.string(),capacity,aggregate_version:version,booking_rules:z.json()}),
 forms:z.array(z.strictObject({id,title:z.string().nullable()})).max(1000),
 readAt:z.iso.datetime({offset:true}),
});
export const inventoryDataSchemas={
 'inventory.prepare_standing':z.strictObject({occasionId:id,commandId:z.uuid(),status:z.enum(['applied','unchanged']),preparation}),
};
export const inventoryDescriptors=[{
 id:'inventory.prepare_standing',name:'festapp_inventory_prepare_standing',
 description:'Prepare standing admission stock for an existing spot-type product with no stock assignments, using the same single atomic command as blueprint administration. Supply its original aggregate version and exact capacity. Creates one pool/context/resource and assigns the product in one receipt; existing sold items are allocated by the canonical allocator and their orders/addressed seats stay intact. Insufficient capacity rejects the complete intention. Returns all saved IDs, versions and the operational product snapshot; does not save a plan or bind an area. Obtain approval of the exact product/capacity; retry an uncertain result with identical commandId and payload. A conflict requires a fresh read and decision.',
 input:z.strictObject({occasionId:id,productId:id,expectedVersion:version,capacity,commandId:z.uuid()}),domainReadOnly:false,idempotent:true,destructive:true,
}];
export async function invokeInventoryOperation(owner,client,operation,args) {
 const scope=await owner.delegatedContext(client,args.occasionId);
 const {data,error}=await client.rpc('prepare_standing_inventory',{
  p_occasion:args.occasionId,p_organization:scope.organizationId,p_unit:scope.unitId,
  p_product_id:args.productId,p_expected_version:args.expectedVersion,p_capacity:args.capacity,p_command_id:args.commandId,
 });
 if(['40001','40P01'].includes(error?.code)) throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND',true);
 if(error?.code==='22023') throw new OperationError('STANDING_INVENTORY_REJECTED');
 upstream(error);
 if(data?.status==='conflict') throw new OperationError('PRODUCT_CHANGED_RELOAD_REQUIRED');
 if(data?.code===410) throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
 if(data?.status==='rejected') throw new OperationError('STANDING_INVENTORY_REJECTED');
 check(data?.code===200 && data?.mutation?.commandId===args.commandId && data?.mutation?.receiptId===args.commandId);
 check(data?.data?.product?.id===args.productId && data.data.product.occasion===args.occasionId);
 return inventoryDataSchemas[operation].parse({occasionId:args.occasionId,commandId:args.commandId,status:data.status,
  preparation:{...data.data,product:{...data.data.product,price:data.data.product.price===null?null:String(data.data.product.price)}}});
}
