import { z } from 'zod';
import { check, upstream } from '../errors.mjs';

const id = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const occasionCreateInput = z.strictObject({
    commandId: z.uuid(), unitId: id,
    title: z.string().trim().min(1).max(240),
    start: z.iso.datetime({ offset: true }), end: z.iso.datetime({ offset: true }),
    description: z.string().max(20000).default(''),
}).refine(v => Date.parse(v.end) >= Date.parse(v.start));
export const occasionCreateResult = z.strictObject({
    commandId: z.uuid(), occasionId: id, unitId: id, title: z.string(),
    hidden: z.literal(true), salesOpen: z.literal(false),
});
export async function createOccasion(client, profile, args) {
    // The UI's canonical command owns defaults, links, admission, audit and
    // idempotency. A timed-out call must retry this exact commandId and payload.
    const { data, error } = await client.rpc('create_occasion_client_sync_v1', {
        p_command_id: args.commandId,
        p_config: { unit: args.unitId, organization: profile.organizationId,
            title: args.title, description: args.description,
            start_time: args.start, end_time: args.end, is_hidden: true, is_open: false },
    });
    upstream(error);
    check(data?.status === 'applied' && data.code === 200 &&
        data.mutation?.commandId === args.commandId && data.mutation.receiptId === args.commandId &&
        typeof data.mutation.replayed === 'boolean' &&
        data.data?.occasion?.unit === args.unitId && data.data.occasion.organization === profile.organizationId &&
        data.data.occasion.is_hidden === true && data.data.occasion.is_open === false);
    return occasionCreateResult.parse({ commandId: args.commandId, occasionId: data.data.occasionId,
        unitId: args.unitId, title: data.data.occasion.title,
        hidden: true, salesOpen: false });
}
