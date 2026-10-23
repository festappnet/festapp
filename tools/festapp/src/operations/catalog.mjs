import {seatOrderDescriptors,seatOrderDataSchemas,invokeSeatOrderOperation} from './seat-orders.mjs';
import {seatSwapDescriptors,seatSwapDataSchemas,invokeSeatSwapOperation} from './seat-swaps.mjs';
import {seatHoldDescriptors,seatHoldDataSchemas,invokeSeatHoldOperation} from './seat-holds.mjs';
import {seatDescriptors,seatDataSchemas,invokeSeatOperation} from './seats.mjs';
import { inventoryAuthoringDescriptors, inventoryAuthoringDataSchemas, invokeInventoryAuthoringOperation } from './inventory-authoring.mjs';
import { inventoryDescriptors, inventoryDataSchemas, invokeInventoryOperation } from './inventory.mjs';
import { productScheduleDescriptors, productScheduleDataSchemas, invokeProductScheduleOperation } from './product-schedules.mjs';
import { productDescriptors, productDataSchemas, invokeProductOperation } from './products.mjs';
import { orderDataSchemas, orderDescriptors, invokeOrderOperation } from './orders.mjs';
import { operatorAccess, accessProjection } from './access.mjs';
import { occasionCreateInput, occasionCreateResult, createOccasion } from './occasion-create.mjs';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { digest } from '../context/profile.mjs';
import { check, safeError, upstream } from '../errors.mjs';
import { rasterizePdf, PreviewArtifacts } from './preview.mjs';
import {
    layoutSaveInput,
    pendingIntentSchema,
    saveResultSchema,
    fingerprintDraft,
} from './layout-contract.mjs';
import { FileIntentStore } from './intent-store.mjs';
import { LayoutSave } from './layout-save.mjs';
const occasion = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const projection = z
    .object({
        occasion,
        aggregate_version: z.number().int().nonnegative(),
        schemaVersion: z.literal(3),
        appearance: z
            .object({
                layout: z.unknown().optional(),
                background: z.string().nullable().optional(),
                ticket_type: z.string().nullable().optional(),
            })
            .strict(),
        images: z.array(z.string().max(8192)).max(500),
    })
    .strict();
const dataSchemas = {
    ...orderDataSchemas,
    ...productDataSchemas,
    ...productScheduleDataSchemas,
    ...inventoryDataSchemas,
    ...seatDataSchemas,
    ...seatHoldDataSchemas,
    ...seatSwapDataSchemas,
    ...seatOrderDataSchemas,
    ...inventoryAuthoringDataSchemas,
    'occasions.create': occasionCreateResult,
    'access.inspect': accessProjection,
    'context.inspect': z.strictObject({
        userId: z.uuid(),
        backend: z.url(),
        enabledOperations: z.array(z.string()),
        writesEnabled: z.boolean(),
    }),
    'ticket_layouts.inspect': projection.extend({
        presets: z.record(z.string(), z.unknown()),
        fonts: z
            .array(
                z.strictObject({
                    id: z.string(),
                    family: z.string(),
                    weight: z.number(),
                }),
            )
            .max(500),
    }),
    'ticket_layouts.save': saveResultSchema,
    'ticket_layouts.resume': saveResultSchema,
    'ticket_layouts.pending': z.strictObject({
        intent: pendingIntentSchema.nullable(),
    }),
    'ticket_layouts.preview': z.strictObject({
        saveRequest: layoutSaveInput,
        draftFingerprint: z.string().regex(/^[a-f0-9]{64}$/),
        sourceAggregateVersion: z.number().int().nonnegative(),
        scenario: z.enum(['normal', 'long', 'missing']),
        type: z.enum(['wide', 'named']),
        occasionId: occasion,
        warnings: z.array(z.unknown()).max(500),
        image: z
            .strictObject({
                mimeType: z.literal('image/png'),
                data: z.string().max(6 * 1024 * 1024),
            })
            .optional(),
        pdf: z.strictObject({
            uri: z
                .string()
                .regex(/^festapp-preview:\/\/artifact\/[a-f0-9]{64}\.pdf$/),
            mimeType: z.literal('application/pdf'),
        }),
    }),
};
const metaSchema = z.strictObject({
    contractVersion: z.literal(1),
    requestId: z.uuid(),
    profile: z.string(),
    tenantId: z.string(),
    organizationId: occasion,
    readAt: z.iso.datetime(),
});
const resultSchema = (id) =>
    z.strictObject({
        ok: z.boolean(),
        operation: z.literal(id),
        data: dataSchemas[id].optional(),
        error: z
            .strictObject({
                code: z.string(),
                message: z.string(),
                retryable: z.boolean(),
            })
            .optional(),
        meta: metaSchema,
    });
const descriptors = [
    ...[...orderDescriptors, ...productDescriptors, ...productScheduleDescriptors, ...inventoryDescriptors, ...inventoryAuthoringDescriptors, ...seatDescriptors, ...seatHoldDescriptors, ...seatSwapDescriptors, ...seatOrderDescriptors].map(d => ({ ...d, requiresDelegatedAccess: true })),
    { id: 'access.inspect', name: 'festapp_access_inspect', description: 'List currently accessible organizers and occasions within this connection. Permissions are checked live; organizer access includes future occasions.', input: z.strictObject({}), domainReadOnly: true },
    { id: 'occasions.create', name: 'festapp_occasions_create',
      description: 'Create a hidden occasion with sales closed for an explicitly authorized organizer. Uses the canonical application command. Obtain user approval of the details first. On timeout retry the identical commandId and payload; never generate a new ID for an uncertain outcome.',
      input: occasionCreateInput, domainReadOnly: false, idempotent: true, requiresDelegatedCreate: true },
    {
        id: 'context.inspect',
        name: 'festapp_context_inspect',
        description:
            'Inspect the pinned tenant and authenticated ordinary-user identity. No domain changes.',
        input: z.strictObject({}),
        domainReadOnly: true,
    },
    {
        id: 'ticket_layouts.inspect',
        name: 'festapp_ticket_layouts_inspect',
        description:
            'Read scoped ticket artwork, original aggregate version, owned images, renderer presets and registered font metadata.',
        input: z.strictObject({ occasionId: occasion }),
        domainReadOnly: true,
    },
    {
        id: 'ticket_layouts.preview',
        name: 'festapp_ticket_layouts_preview',
        description:
            'Explicitly render an unsaved synthetic ticket using the canonical PDF renderer. Returns a viewable PNG and an expiring PDF resource. Consumes preview quota; never saves artwork or sends mail.',
        input: z.strictObject({
            occasionId: occasion,
            type: z.enum(['wide', 'named']),
            scenario: z.enum(['normal', 'long', 'missing']).default('normal'),
            layout: z.record(z.string(), z.unknown()).optional(),
            background: z.string().max(8192).nullable().optional(),
        }),
        domainReadOnly: false,
    },
    {
        id: 'ticket_layouts.save',
        name: 'festapp_ticket_layouts_save',
        description:
            'Save the exact reviewed artwork through the canonical occasion command. Original versions and a durable pending identity are required. Enabled only after the backend write contract is verified.',
        input: layoutSaveInput,
        domainReadOnly: false,
        requiresLayoutWriteContract: true,
    },
    {
        id: 'ticket_layouts.pending',
        name: 'festapp_ticket_layouts_pending',
        description:
            'Inspect the original unresolved artwork intent for this actor and occasion. Does not clear or rebase it.',
        input: z.strictObject({ occasionId: occasion }),
        domainReadOnly: true,
        requiresLayoutWriteContract: true,
    },
    {
        id: 'ticket_layouts.resume',
        name: 'festapp_ticket_layouts_resume',
        description:
            'Explicitly replay the original stored artwork request and command ID. Never reads a new editor baseline.',
        input: z.strictObject({ occasionId: occasion, commandId: z.uuid() }),
        domainReadOnly: false,
        requiresLayoutWriteContract: true,
    },
];
export class Operations {
    constructor(
        owner,
        { rasterize = rasterizePdf, artifacts = new PreviewArtifacts() } = {},
    ) {
        this.owner = owner;
        this.writeReady = false;
        this.rasterize = rasterize;
        this.artifacts = artifacts;
        this.layoutSave = new LayoutSave(new FileIntentStore(owner.root));
    }
    get catalog() {
        return descriptors
            .filter(
                (descriptor) =>
                    (!this.owner.allowedOperations || this.owner.allowedOperations.includes(descriptor.id)) &&
                    (!descriptor.requiresLayoutWriteContract || this.writeReady) &&
                    (!descriptor.requiresDelegatedAccess || this.owner.allowedOperations?.includes(descriptor.id) === true) &&
                    (!descriptor.requiresDelegatedCreate || this.owner.allowedOperations?.includes('occasions.create') === true),
            )
            .map((descriptor) => ({
                ...descriptor,
                output: resultSchema(descriptor.id),
            }));
    }
    setWriteReady(value) {
        if (this.writeReady === value) return;
        this.writeReady = value;
        this.onWriteReadinessChanged?.(value);
    }
    async verifyWriteContract(client) {
        try {
            const { data, error } = await client.rpc(
                'get_ticket_layout_write_contract_v1',
            );
            const parsed = z
                .strictObject({
                    family: z.literal('ticket_layouts'),
                    contractVersion: z.literal(1),
                    ready: z.boolean(),
                })
                .safeParse(data);
            const ready = !error && parsed.success && parsed.data.ready;
            this.setWriteReady(Boolean(ready));
            check(ready, 'FAMILY_NOT_READY');
        } catch (error) {
            this.setWriteReady(false);
            check(false, 'FAMILY_NOT_READY');
        }
    }
    async prepare() {
        try {
            await this.owner.authorized((client) =>
                this.verifyWriteContract(client),
            );
        } catch {
            this.setWriteReady(false);
        }
    }
    async inspect(client, id) {
        const scope = await this.owner.delegatedContext?.(client, id);
        const { data, error } = await client.rpc(
            scope ? 'get_delegated_ticket_layout_for_authoring_v1' : 'get_ticket_layout_for_authoring_v1',
            { p_occasion: id, ...(scope ? { p_organization: scope.organizationId, p_unit: scope.unitId } : {}) },
        );
        upstream(error);
        const parsed = projection.safeParse(data);
        check(parsed.success && parsed.data.occasion === id);
        return parsed.data;
    }
    async preview(client, body) {
        check(
            Buffer.byteLength(JSON.stringify(body)) <= 40000,
            'INVALID_INPUT',
        );
        const { data, error } = await client.functions.invoke(
            'preview-ticket-layout',
            { body },
        );
        upstream(error);
        check(data && !data.error);
        return data;
    }
    async invoke(id, raw) {
        const meta = {
            contractVersion: 1,
            requestId: randomUUID(),
            profile: this.owner.profile.name,
            tenantId: this.owner.profile.tenantId,
            organizationId: this.owner.profile.organizationId,
            readAt: new Date().toISOString(),
        };
        try {
            if (
                [
                    'ticket_layouts.save',
                    'ticket_layouts.pending',
                    'ticket_layouts.resume',
                ].includes(id)
            )
                check(this.writeReady, 'FAMILY_NOT_READY');
            const descriptor = this.catalog.find((d) => d.id === id);
            check(descriptor, 'INVALID_INPUT');
            const parsed = descriptor.input.safeParse(raw);
            check(parsed.success, 'INVALID_INPUT');
            const args = parsed.data;
            await this.owner.authorizeOperation?.(id, args);
            return await this.owner.authorized(async (client, context) => {
                if (descriptor.requiresLayoutWriteContract)
                    await this.verifyWriteContract(client);
                let data;
                if (id === 'context.inspect')
                    data = {
                        userId: context.userId,
                        backend: this.owner.profile.backendOrigin,
                        enabledOperations: this.catalog.map((d) => d.id),
                        writesEnabled: this.writeReady || this.owner.allowedOperations?.some(id => id === 'occasions.create' || [...orderDescriptors, ...productDescriptors, ...productScheduleDescriptors, ...inventoryDescriptors, ...inventoryAuthoringDescriptors, ...seatDescriptors, ...seatHoldDescriptors, ...seatSwapDescriptors, ...seatOrderDescriptors].some(d => d.id === id && !d.domainReadOnly)) === true,
                    };
                else if (id === 'access.inspect') data = this.owner.listAccess ? await this.owner.listAccess(client) : await operatorAccess(client, this.owner.profile);
                else if (seatOrderDataSchemas[id]) data = await invokeSeatOrderOperation(this.owner, client, id, args, context);
                else if (seatSwapDataSchemas[id]) data = await invokeSeatSwapOperation(this.owner, client, id, args);
                else if (seatHoldDataSchemas[id]) data = await invokeSeatHoldOperation(this.owner, client, id, args);
                else if (seatDataSchemas[id]) data = await invokeSeatOperation(this.owner, client, id, args);
                else if (inventoryAuthoringDataSchemas[id]) data = await invokeInventoryAuthoringOperation(this.owner, client, id, args);
                else if (inventoryDataSchemas[id]) data = await invokeInventoryOperation(this.owner, client, id, args);
                else if (productScheduleDataSchemas[id]) data = await invokeProductScheduleOperation(this.owner, client, id, args);
                else if (productDataSchemas[id]) data = await invokeProductOperation(this.owner, client, id, args);
                else if (orderDataSchemas[id]) data = await invokeOrderOperation(this.owner, client, id, args);
                else if (id === 'occasions.create') data = await createOccasion(client, this.owner.profile, args, { delegated: Boolean(this.owner.delegatedContext) });
                else if (id === 'ticket_layouts.save') {
                    await this.inspect(client, args.occasionId); // Permission only; never replace the original version.
                    data = await this.layoutSave.save(client, context, args);
                } else if (id === 'ticket_layouts.pending') {
                    await this.inspect(client, args.occasionId);
                    data = {
                        intent: await this.layoutSave.pending(
                            context,
                            args.occasionId,
                        ),
                    };
                } else if (id === 'ticket_layouts.resume')
                    data = await this.layoutSave.resume(
                        client,
                        context,
                        args.occasionId,
                        args.commandId,
                    );
                else if (id === 'ticket_layouts.inspect') {
                    const current = await this.inspect(client, args.occasionId);
                    const resolved = await this.preview(client, {
                        occasionId: args.occasionId,
                        type:
                            current.appearance.ticket_type === 'named'
                                ? 'named'
                                : 'wide',
                        mode: 'resolve',
                        fontProtocol: 2,
                        borrowResourcesOnly: true,
                    });
                    check(
                        resolved.presets &&
                            typeof resolved.presets === 'object',
                    );
                    data = {
                        ...current,
                        presets: resolved.presets,
                        fonts: Object.values(resolved.fonts ?? {}).map(
                            ({ id, family, weight }) => ({
                                id,
                                family,
                                weight,
                            }),
                        ),
                    };
                } else {
                    const current = await this.inspect(client, args.occasionId);
                    check(
                        Buffer.byteLength(JSON.stringify(args)) <= 40000,
                        'INVALID_INPUT',
                    );
                    let layout = args.layout;
                    let background = Object.hasOwn(args, 'background')
                        ? args.background
                        : (current.appearance.background ?? null);
                    if (!layout) {
                        const resolved = await this.preview(client, {
                            ...args,
                            mode: 'resolve',
                            fontProtocol: 2,
                        });
                        check(
                            resolved.template &&
                                Object.hasOwn(resolved, 'backgroundUrl'),
                        );
                        layout = {
                            schemaVersion: current.schemaVersion,
                            templates: {
                                ...(current.appearance.layout?.templates ?? {}),
                                [args.type]: resolved.template,
                            },
                        };
                        background = resolved.backgroundUrl;
                    }
                    // Freeze the resolved candidate before PDF rendering, so its
                    // fingerprint never depends on a later saved-layout lookup.
                    const body = {
                        ...args,
                        layout,
                        background,
                        mode: 'pdf',
                        fontProtocol: 2,
                    };
                    const result = await this.preview(client, body);
                    check(
                        typeof result.file === 'string' &&
                            result.file.length <= 12 * 1024 * 1024 &&
                            /^[A-Za-z0-9+/]*={0,2}$/.test(result.file),
                    );
                    const pdf = Buffer.from(result.file, 'base64');
                    check(
                        pdf.length <= 8 * 1024 * 1024 &&
                            pdf.subarray(0, 5).toString() === '%PDF-',
                    );
                    const png = await this.rasterize(pdf);
                    const saveRequest = {
                        occasionId: args.occasionId,
                        expectedVersion: current.aggregate_version,
                        expectedLayout: current.appearance.layout ?? null,
                        nextLayout: layout,
                        appearance: { background, ticket_type: args.type },
                        scenario: args.scenario,
                    };
                    const fingerprint = fingerprintDraft(
                        this.owner.profile.binding,
                        saveRequest,
                    );
                    saveRequest.draftFingerprint = fingerprint;
                    const uri = this.artifacts.put(digest(pdf), {
                        pdf,
                        userId: context.userId,
                        occasionId: args.occasionId,
                    });
                    data = {
                        saveRequest,
                        draftFingerprint: fingerprint,
                        sourceAggregateVersion: current.aggregate_version,
                        scenario: args.scenario,
                        type: args.type,
                        occasionId: args.occasionId,
                        warnings: Array.isArray(result.warnings)
                            ? result.warnings
                            : [],
                        image: {
                            mimeType: 'image/png',
                            data: png.toString('base64'),
                        },
                        pdf: { uri, mimeType: 'application/pdf' },
                    };
                }
                check(dataSchemas[id].safeParse(data).success);
                return { ok: true, operation: id, data, meta };
            });
        } catch (error) {
            return { ok: false, operation: id, error: safeError(error), meta };
        }
    }
    async readArtifact(uri) {
        return this.owner.authorized(async (client, { userId }) => {
            const item = this.artifacts.get(uri);
            check(item.userId === userId, 'FORBIDDEN');
            await this.inspect(client, item.occasionId);
            return {
                contents: [
                    {
                        uri,
                        mimeType: 'application/pdf',
                        blob: item.pdf.toString('base64'),
                    },
                ],
            };
        });
    }
}
