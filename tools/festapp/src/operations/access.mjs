import { z } from 'zod';
import { check, upstream } from '../errors.mjs';

const id = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const accessSchema = z.discriminatedUnion('type', [
    z.strictObject({ type: z.literal('occasions'), occasionIds: z.array(id).min(1).max(100) }),
    z.strictObject({ type: z.literal('unit'), unitId: id, canCreateOccasions: z.boolean() }),
]);
export const accessProjection = z.strictObject({
    units: z.array(z.strictObject({ id, title: z.string(), canCreateOccasions: z.boolean() })),
    occasions: z.array(z.strictObject({ id, title: z.string(), unitId: id,
        capabilities: z.strictObject({ 'ticket_layouts.read': z.boolean() }),
    })),
});
export async function operatorAccess(client, profile, { unitId, occasionId } = {}) {
    const { data, error } = await client.rpc('get_operator_access_v1', {
        p_organization: profile.organizationId, p_unit: unitId ?? null, p_occasion: occasionId ?? null,
    });
    upstream(error);
    const parsed = accessProjection.safeParse(data);
    check(parsed.success);
    return parsed.data;
}
export function verifySelection(raw, available, canRequestCreate) {
    const parsed = accessSchema.safeParse(raw);
    check(parsed.success, 'FORBIDDEN');
    const access = parsed.data;
    if (access.type === 'occasions') {
        check(access.occasionIds.every(id => available.occasions.some(o => o.id === id)), 'FORBIDDEN');
        access.occasionIds = [...new Set(access.occasionIds)];
    } else {
        const unit = available.units.find(u => u.id === access.unitId);
        check(unit && (!access.canCreateOccasions || (unit.canCreateOccasions && canRequestCreate)), 'FORBIDDEN');
    }
    return access;
}
