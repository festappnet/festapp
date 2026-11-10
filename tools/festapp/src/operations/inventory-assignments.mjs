import { z } from 'zod';
import { check, upstream, OperationError } from '../errors.mjs';

const id = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const page = { after: id.optional(), limit: z.number().int().min(1).max(100).default(50) };
const change = z.strictObject({ resource_id: id, resource_slot_id: id.nullable(), inventory_context_id: id.nullable(),
    old_spot_id: id.nullable(), new_spot_id: id.nullable() }).refine(c => c.old_spot_id !== null || c.new_spot_id !== null);
const spot = z.strictObject({ id, title: z.string().nullable(), inventoryContextId: id,
    resourceId: id.nullable(), resourceSlotId: id.nullable(), allocated: z.boolean(), held: z.boolean() });
export const inventoryAssignmentDataSchemas = {
    'inventory.spots.list': z.strictObject({ occasionId: id, poolId: id, spots: z.array(spot).max(100),
        nextCursor: id.nullable(), readAt: z.iso.datetime({ offset: true }) }),
    'inventory.slots.list': z.strictObject({ occasionId: id, resourceId: id,
        slots: z.array(z.strictObject({ id, resourceId: id, title: z.string().nullable() })).max(100),
        nextCursor: id.nullable(), readAt: z.iso.datetime({ offset: true }) }),
    'inventory.assignments.save': z.strictObject({ occasionId: id, commandId: z.uuid(),
        status: z.enum(['applied', 'unchanged']), changedCount: z.number().int().nonnegative().max(1000) }),
};
export const inventoryAssignmentDescriptors = [
    { id: 'inventory.spots.list', name: 'festapp_inventory_spots_list', domainReadOnly: true,
        input: z.strictObject({ occasionId: id, poolId: id, ...page }),
        description: 'Read a bounded ID page of physical stock spots and their current context/resource/slot assignments. Includes allocation/active-hold flags, not customer data, ticket capabilities or hold secrets. Use these IDs and original assignments with inventory.assignments.save. Pages are read-time facts, not a frozen snapshot or reservation promise.' },
    { id: 'inventory.slots.list', name: 'festapp_inventory_slots_list', domainReadOnly: true,
        input: z.strictObject({ occasionId: id, resourceId: id, ...page }),
        description: 'Read a bounded ID page of named slots belonging to one authorized stock resource. The same resource-slot identities are used by the administration assignment editor. Continue with nextCursor; no customers or reservation credentials.' },
    { id: 'inventory.assignments.save', name: 'festapp_inventory_assignments_save', domainReadOnly: false, idempotent: true, destructive: true,
        input: z.strictObject({ occasionId: id, commandId: z.uuid(), changes: z.array(change).min(1).max(1000) }),
        description: 'Apply an explicitly approved batch of stock spot assignments through the same atomic command and receipt as the administration editor. Each change supplies the original old_spot_id and requested new_spot_id (null clears), target resource_id, nullable resource_slot_id and inventory_context_id. Preserve original IDs; do not replace a stale baseline with a fresh one before saving. The domain owner enforces context, slot, holds, capacity and all-or-nothing changes. Retry an uncertain result with the identical command UUID and payload. An assignment-changed conflict requires rereading and a new decision. Does not create orders, alter ticket ownership, charge or send email.' },
];

export async function invokeInventoryAssignmentOperation(owner, client, operation, args) {
    const scope = await owner.delegatedContext(client, args.occasionId);
    const base = { p_occasion: args.occasionId, p_organization: scope.organizationId, p_unit: scope.unitId };
    const write = operation === 'inventory.assignments.save';
    const name = write ? 'manage_inventory_assignments' : operation === 'inventory.spots.list'
        ? 'get_inventory_spot_page' : 'get_inventory_resource_slot_page';
    const params = write ? { ...base, p_changes: args.changes, p_command_id: args.commandId }
        : { ...base, ...(operation === 'inventory.spots.list' ? { p_pool: args.poolId } : { p_resource: args.resourceId }),
            p_after: args.after ?? null, p_limit: args.limit };
    const { data, error } = await client.rpc(name, params);
    if (error?.code === '40001' && error.message === 'original spot assignment changed; reload editor')
        throw new OperationError('INVENTORY_ASSIGNMENT_CHANGED_RELOAD_REQUIRED');
    if (['40001', '40P01'].includes(error?.code)) throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND', true);
    if (['22023', '23514', '55000', '54000'].includes(error?.code)) throw new OperationError('INVENTORY_INTENTION_REJECTED');
    upstream(error);
    if (!write) {
        check(data?.occasionId === args.occasionId && (operation === 'inventory.spots.list' ? data.poolId === args.poolId : data.resourceId === args.resourceId));
        return inventoryAssignmentDataSchemas[operation].parse(data);
    }
    if (data?.code === 410) throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
    check(data?.code === 200 && data?.mutation?.commandId === args.commandId && data?.mutation?.receiptId === args.commandId);
    return inventoryAssignmentDataSchemas[operation].parse({ occasionId: args.occasionId,
        commandId: args.commandId, status: data.status, changedCount: data.data?.changedCount });
}
