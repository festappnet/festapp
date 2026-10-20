import { z } from 'zod';
import { digest } from '../context/profile.mjs';
const occasion = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const layoutSaveInput = z.strictObject({
    occasionId: occasion,
    expectedVersion: z.number().int().nonnegative(),
    expectedLayout: z.record(z.string(), z.unknown()).nullable(),
    nextLayout: z.record(z.string(), z.unknown()),
    appearance: z.strictObject({
        background: z.string().max(8192).nullable(),
        ticket_type: z.enum(['wide', 'named']),
    }),
    scenario: z.enum(['normal', 'long', 'missing']),
    draftFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
});
export function canonical(value) {
    return Array.isArray(value)
        ? value.map(canonical)
        : value && typeof value === 'object'
          ? Object.fromEntries(
                Object.keys(value)
                    .sort()
                    .map((key) => [key, canonical(value[key])]),
            )
          : value;
}
export function fingerprintDraft(profileBinding, request) {
    const { draftFingerprint, ...candidate } = request;
    return digest(JSON.stringify(canonical({ profileBinding, ...candidate })));
}
export function layoutParameters(request) {
    return {
        p_occasion: request.occasionId,
        p_expected_version: request.expectedVersion,
        p_config: {
            id: request.occasionId,
            ticket_layout_change: {
                expected: request.expectedLayout,
                next: request.nextLayout,
                appearance: request.appearance,
            },
        },
    };
}
export const pendingIntentSchema = z.strictObject({
    schemaVersion: z.literal(1),
    profileBinding: z.string(),
    userId: z.uuid(),
    commandId: z.uuid(),
    createdAt: z.iso.datetime(),
    request: layoutSaveInput,
});
export const saveResultSchema = z.strictObject({
    commandId: z.uuid(),
    status: z.enum(['applied', 'unchanged', 'conflict', 'rejected']),
    code: z.number().int(),
    version: z.number().int().nonnegative(),
    draftFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
    replayed: z.boolean(),
});
