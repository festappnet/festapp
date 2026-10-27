import { z } from 'zod';
import { check, upstream } from '../errors.mjs';
import { fingerprintDraft, layoutParameters } from './layout-contract.mjs';
const receipt = z.object({
    status: z.enum(['applied', 'unchanged', 'conflict', 'rejected']),
    code: z.number().int(),
    data: z.object({ version: z.number().int().nonnegative() }),
    mutation: z.object({
        commandId: z.uuid(),
        receiptId: z.uuid(),
        commitId: z.uuid().nullable(),
        replayed: z.boolean(),
        occurredAt: z.iso.datetime({ offset: true }),
    }),
    sync: z.object({
        replacements: z.array(z.record(z.string(), z.unknown())),
    }),
});
export class LayoutSave {
    constructor(store, { scopeFor } = {}) {
        this.store = store;
        this.scopeFor = scopeFor;
    }
    async save(client, context, request) {
        check(
            Buffer.byteLength(JSON.stringify(request)) <= 40000,
            'INVALID_INPUT',
        );
        check(
            fingerprintDraft(context.profile.binding, request) ===
                request.draftFingerprint,
            'DRAFT_PREVIEW_MISMATCH',
        );
        const intent = await this.store.claim(
            context.profile,
            context.userId,
            request,
        );
        return this.submit(client, context, intent);
    }
    async pending(context, occasionId) {
        return this.store.read(context.profile, context.userId, occasionId);
    }
    async resume(client, context, occasionId, commandId) {
        const intent = await this.pending(context, occasionId);
        check(intent && intent.commandId === commandId, 'PENDING_NOT_FOUND');
        return this.submit(client, context, intent);
    }
    async submit(client, context, intent) {
        const scope = await this.scopeFor?.(client, intent.request.occasionId);
        const { data, error } = await client.rpc(
            scope ? 'save_delegated_ticket_layout' : 'save_occasion_client_sync_v1',
            {
                ...layoutParameters(intent.request),
                ...(scope ? {p_organization:scope.organizationId,p_unit:scope.unitId} : {}),
                p_command_id: intent.commandId,
            },
        );
        upstream(error);
        check(
            !(data?.code === 410 && data?.mutation?.expired === true),
            'RECEIPT_EXPIRED',
        );
        const parsed = receipt.safeParse(data);
        check(parsed.success);
        const response = parsed.data;
        check(
            response.mutation.commandId === intent.commandId &&
                response.mutation.receiptId === intent.commandId,
        );
        check(
            (['applied', 'unchanged'].includes(response.status) &&
                response.code === 200) ||
                (response.status === 'conflict' && response.code === 409) ||
                (response.status === 'rejected' &&
                    response.code >= 400 &&
                    response.code < 500),
        );
        // Do not return the occasion-wide SQL payload from a narrow artwork tool.
        const result = {
            commandId: intent.commandId,
            status: response.status,
            code: response.code,
            version: response.data.version,
            draftFingerprint: intent.request.draftFingerprint,
            replayed: response.mutation.replayed,
        };
        await this.store.clear(
            context.profile,
            context.userId,
            intent.request.occasionId,
            intent.commandId,
        );
        return result;
    }
}
