import { fingerprintDraft } from '../src/operations/layout-contract.mjs';
export function request(profile, patch = {}) {
    const value = {
        occasionId: 7,
        expectedVersion: 3,
        expectedLayout: null,
        nextLayout: { schemaVersion: 3, templates: {} },
        appearance: { background: null, ticket_type: 'named' },
        scenario: 'normal',
        ...patch,
    };
    return {
        ...value,
        draftFingerprint: fingerprintDraft(profile.binding, value),
    };
}
export function receipt(
    id,
    { status = 'applied', code = 200, version = 4, replayed = false } = {},
) {
    return {
        status,
        code,
        data: { version, occasion: { private_data: 'must not escape' } },
        sync: { replacements: [] },
        mutation: {
            commandId: id,
            receiptId: id,
            commitId: id,
            replayed,
            occurredAt: '2026-10-20T10:00:00+00:00',
        },
    };
}
