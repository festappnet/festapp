import { z } from 'zod';
import { check, upstream } from '../errors.mjs';

const id = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const accessSchema = z.discriminatedUnion('type', [
    z.strictObject({ type: z.literal('occasions'), occasionIds: z.array(id).min(1).max(100) }),
    z.strictObject({ type: z.literal('unit'), unitId: id, canCreateOccasions: z.boolean() }),
    z.strictObject({ type: z.literal('selection'),
        units: z.array(z.strictObject({ unitId: id, canCreateOccasions: z.boolean() })).max(100),
        occasionIds: z.array(id).max(100),
    }).refine(a => a.units.length + a.occasionIds.length > 0),
]);

// Existing connections retain their original scope; new consent can combine
// several whole organizers with individually selected occasions.
export function accessSelection(access) {
    if (access.type === 'selection') return access;
    return { type: 'selection', units: access.type === 'unit'
        ? [{ unitId: access.unitId, canCreateOccasions: access.canCreateOccasions }] : [],
        occasionIds: access.type === 'occasions' ? access.occasionIds : [] };
}

export const canCreateWithAccess = access => accessSelection(access).units.some(u => u.canCreateOccasions);
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
    const selection = accessSelection(access);
    check(selection.occasionIds.every(id => available.occasions.some(o => o.id === id)), 'FORBIDDEN');
    check(new Set(selection.units.map(u => u.unitId)).size === selection.units.length, 'FORBIDDEN');
    for (const requested of selection.units) {
        const unit = available.units.find(u => u.id === requested.unitId);
        check(unit && (!requested.canCreateOccasions || (unit.canCreateOccasions && canRequestCreate)), 'FORBIDDEN');
    }
    if ('occasionIds' in access) access.occasionIds = [...new Set(access.occasionIds)];
    return access;
}
