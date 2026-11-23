import { z } from 'zod';
import { emailTemplateDataSchemas } from './email-templates.mjs';
import { peopleDataSchemas } from './people.mjs';
import { configurationDataSchemas } from './configuration.mjs';
import { informationDataSchemas } from './information.mjs';
import { inventoryAuthoringDataSchemas } from './inventory-authoring.mjs';
import { productAdminSchema, productDataSchemas } from './products.mjs';

// Public results preserve workflow identifiers and status, but omit personal
// and free-form fields from these administrative read operations.
const id = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const count = z.number().int().nonnegative();
const text = z.string();
const nullableText = text.nullable();
const uuid = z.uuid();
const timestamp = z.iso.datetime({ offset: true }).nullable();
const state = z.string();
const revision = z.union([count, text]);
const bankAccount = {
    id,
    title: nullableText,
    type: nullableText,
};
const bankSync = z.object({
    state,
    mode: nullableText,
    bank_pull_at: timestamp,
    receiver_commit_at: timestamp,
    warning_pending: z.boolean(),
});
const cardStatus = {
    state,
    paused: z.boolean(),
    chargesEnabled: z.boolean(),
    payoutsEnabled: z.boolean(),
    cardPaymentsActive: z.boolean(),
    disconnectState: nullableText,
};
const refundDecision = z.object({
    action: state,
    ticketIds: z.array(id),
    isCurrent: z.boolean(),
}).nullable();
const participant = {
    userId: uuid,
    aggregateVersion: count,
};
const feedback = {
    feedback_id: id,
    event_id: id,
    event_title: nullableText,
    rating: nullableText,
    is_anonymous: z.boolean(),
};

const page = shape => z.object({ items: z.array(z.object(shape)).max(100) });
const publicIdentity = { id, title: nullableText, aggregateVersion: count };
const programEntity = shape => z.object({
    entityId: id,
    aggregateVersion: count,
    entity: z.object({ id, ...shape }),
});
const coordinate = z.object({ lat: z.number(), lng: z.number() });
const pathPoint = z.union([id, coordinate]);
const activity = z.object({
    id: uuid,
    title: nullableText,
    type: nullableText.optional(),
    assignments: z.array(z.object({
        id: uuid,
        start_time: timestamp,
        end_time: timestamp,
        linked_place_ids: z.array(id),
        linked_event_ids: z.array(id),
    })),
});
const commit = {
    commitId: uuid,
    occurredAt: timestamp,
    actorKind: nullableText,
    source: nullableText,
    changeClass: nullableText,
};
const commitCursor = z.object({ occurredAt: timestamp, commitId: uuid });
const publication = {
    component: text,
    revision,
    publishedRevision: revision.nullable(),
    publicationStatus: text,
};
const form = {
    id,
    occasion: id,
    aggregate_version: count,
    title: nullableText.optional(),
    type: nullableText.optional(),
    is_open: z.boolean().nullable().optional(),
    blueprint: id.nullable().optional(),
    participant_capacity: count.nullable().optional(),
    waitlist_enabled: z.boolean().nullable().optional(),
    show_remaining_capacity: z.boolean().nullable().optional(),
    registrationMode: nullableText.optional(),
};
const formField = z.object({ id: id.nullable(), title: nullableText.optional(), type: nullableText,
    is_ticket_field: z.boolean().nullable().optional() });
const formProduct = z.object({
    id,
    title: nullableText.optional(),
    price: z.union([z.number(), text]).nullable().optional(),
    is_hidden: z.boolean().nullable().optional(),
});
function omitFields(schema, ...keys) {
    const shape = { ...schema.shape };
    for (const key of keys) delete shape[key];
    return z.object(shape);
}

const occasionSettings = configurationDataSchemas['occasions.settings.inspect'];
const organizerSettings = configurationDataSchemas['units.settings.inspect'];
const productPage = productDataSchemas['products.list'];
const inventoryPool = inventoryAuthoringDataSchemas['inventory.pools.inspect'];
const inventoryResources = inventoryAuthoringDataSchemas['inventory.resources.list'];
const offer = z.object({
    id: uuid,
    created_at: timestamp,
    expires_at: timestamp,
    slots: z.array(z.object({ ticketId: id, outcome: text, resulting_order_id: id.nullable() })),
});
const waitlistCapacity = z.object({
    enabled: z.boolean(),
    limit: count.nullable(),
    occupiedPeople: count,
    waitingPeople: count,
    offeredPlaces: count,
    offerablePlaces: count.nullable(),
}).nullable();

const summaries = {
    'banks.list': {
        data: z.object({ items: z.array(z.object({
            ...bankAccount,
            currencies: z.array(text).nullable(),
            priority: count.nullable(),
            canManage: z.boolean(),
        })).max(100) }),
        description: 'List linked bank account IDs, labels, types, currencies and priorities for a scoped organizer. Requires live permissions. Account and creditor details are withheld.',
    },
    'banks.candidates': {
        data: z.object({ items: z.array(z.object(bankAccount)).max(100) }),
        description: 'List the caller’s eligible bank account IDs, labels and types for a scoped organizer. Requires live permissions. Account numbers are withheld.',
    },
    'banks.users': {
        data: z.object({ items: z.array(z.object({
            user_id: uuid,
            is_admin: z.boolean().nullable(),
            is_support: z.boolean().nullable(),
        })).max(100) }),
        description: 'Read a bounded page of bank account membership IDs and roles. Requires a selected organizer and live bank user permissions. Names and email addresses are withheld.',
    },
    'banks.status': {
        data: z.object({ connection: bankSync.nullable() }),
        description: 'Read synchronization status, mode, recent sync times and warning status for a linked bank account. Requires live organizer-manager and bank-admin permissions.',
    },
    'cards.status': {
        data: z.object({ state: z.object(cardStatus).nullable() }),
        description: 'Read the public plugin’s scoped card-payment status, capabilities and disconnect state. Requires live organizer-manager permissions.',
    },
    'cards.disconnectImpact': {
        data: z.object({ state: z.object({
            openAttempts: count,
            historyCount: count,
            lastSyncedAt: timestamp,
            disconnectState: nullableText,
        }) }),
        description: 'Read the count of open attempts and historical attempts and synchronization status for a scoped card connection. Requires live organizer-manager permissions.',
    },
    'cards.refund.inspect': {
        data: z.object({ detail: z.object({
            orderId: id,
            currency: text,
            refundedMinor: count,
            amountMinor: count,
            reconciliationPending: z.boolean(),
            decision: refundDecision,
            tickets: z.array(z.object({ id, state })),
        }).nullable() }),
        description: 'Read settled and refunded amounts, reconciliation status and ticket states for a scoped order. Requires live order-editor permissions. Refund notes and payment-provider links are withheld.',
    },
    'feedback.list': {
        data: z.object({ items: z.array(z.object(feedback)).max(100), nextCursor: id.nullable() }),
        description: 'Read a bounded page of rating records for a scoped event with live feedback access. Free-form feedback and participant names are withheld.',
    },
    'profiles.list': {
        data: z.object({ items: z.array(z.object(participant)).max(100) }),
        description: 'List a bounded page of participant references for one selected occasion with live participant access. Names, contacts and demographics are withheld.',
    },
    'profiles.inspect': {
        data: z.object({ ...participant, roles: peopleDataSchemas['profiles.inspect'].shape.roles }),
        description: 'Read a participant reference, roles and current record version for one scoped occasion. Requires live participant management rights. Personal profile fields are withheld.',
    },
    'units.people.list': {
        data: z.object({ items: z.array(z.object({
            ...participant,
            isManager: z.boolean(),
            isEditor: z.boolean(),
            isEditorView: z.boolean(),
        })).max(100) }),
        description: 'List organizer membership references and roles. Requires explicit whole-organizer consent and live manager rights. Names and contacts are withheld.',
    },
    'history.orders': {
        data: page({ id, createdAt: timestamp, state: nullableText, price: nullableText, currency: nullableText })
            .extend({ nextCursor: id.nullable() }),
        description: 'Read a scoped order’s history of states, amounts and times using the canonical history. Actor names are withheld.',
    },
    'history.commits': {
        data: page({ ...commit, itemCount: count, components: z.array(z.object(publication)) })
            .extend({ nextCursor: commitCursor.nullable() }),
        description: 'Read bounded audit summaries and publication status for the scoped event or explicitly authorized organizer. Actor names are withheld.',
    },
    'history.commit': {
        data: z.object({ entry: z.object({
            ...commit,
            items: z.array(z.object({ entityType: text, operation: text, changedFields: z.array(text).nullable() })),
            components: z.array(z.object({ ...publication, scopeType: text, scopeId: id })),
        }) }),
        description: 'Read one scoped audit entry, affected entity types, changed fields and publication status. Actor names, reasons and item labels are withheld.',
    },
    'occasions.setup.inspect': {
        data: z.object({ draft: z.object({
            id: uuid,
            unit: id,
            revision: count,
            current_step: count,
            updated_at: timestamp,
        }) }),
        description: 'Read a scoped event setup draft’s reference, wizard step and revision. Full draft values and contact or payment fields are withheld.',
    },
    'units.legal.inspect': {
        data: z.object({ profile: z.object({
            unitId: id, revision: count, status: state, legalName: text, countryCode: text, website: text,
            submittedAt: timestamp, verifiedAt: timestamp,
        }) }),
        description: 'Read scoped organizer identity and verification status. Addresses, contacts, registration numbers and review notes are withheld.',
    },
    'units.quotes.list': {
        data: page({ ...publicIdentity, description: nullableText, type: nullableText, isHidden: z.boolean().nullable() }),
        description: 'List a bounded page of scoped organizer quotes, visibility and version. Private metadata is withheld.',
    },
    'events.inspect': {
        data: programEntity({
            title: nullableText,
            startTime: timestamp,
            endTime: timestamp,
            description: nullableText,
            placeId: id.nullable(),
            maxParticipants: count.nullable(),
            parentEventIds: z.array(id),
        }),
        description: 'Read a scoped program event, its timing, capacity, location and parent events. Arbitrary metadata is withheld.',
    },
    'speakers.inspect': {
        data: programEntity({
            title: nullableText, subtitle: nullableText, description: nullableText,
            image: nullableText, topics: z.array(id),
        }),
        description: 'Read a scoped speaker’s program name, bio, image and linked topics. Private speaker metadata is withheld.',
    },
    'paths.inspect': {
        data: programEntity({
            title: nullableText,
            icon: id.nullable().optional(),
            is_hidden: z.boolean().nullable().optional(),
            path_data: z.array(z.array(pathPoint)).nullable(),
        }),
        description: 'Read a scoped map path’s geometry, title, visibility and revision. Raw metadata is withheld.',
    },
    'activities.inspect': {
        data: z.object({
            aggregateVersion: count,
            latestPublishId: id.nullable(),
            draftId: id.nullable(),
            draftParentHistoryId: id.nullable(),
            graph: z.array(activity),
            draftGraph: z.array(activity).nullable(),
        }),
        description: 'Read scoped activities, assignment times, locations, event links and draft status. Participant identities and private activity metadata are withheld.',
    },
    'forms.inspect': {
        data: z.object({ occasionId: id, authoring: z.object({
            form: z.object(form),
            fields: z.array(formField),
            products: z.array(formProduct),
            productTypes: z.array(z.object({ id, title: nullableText.optional(), type: nullableText.optional() })),
        }) }),
        description: 'Read a scoped saved form, its availability settings, field definitions and product summaries. Raw settings, bank details, access keys and customer responses are withheld.',
    },
    'occasions.settings.inspect': {
        data: z.object({
            ...occasionSettings.shape,
            settings: omitFields(occasionSettings.shape.settings, 'reply_to'),
            features: z.array(z.object({ code: text, is_enabled: z.boolean().optional() })).max(25),
        }),
        description: 'Read scoped occasion information, dates, visibility and enabled feature codes. Contact settings and private feature configuration are withheld.',
    },
    'units.settings.inspect': {
        data: z.object({
            ...organizerSettings.shape,
            settings: omitFields(organizerSettings.shape.settings, 'reply_to', 'measurement_scripts'),
        }),
        description: 'Read organizer settings and measurement configuration for the scoped organizer. Contact addresses and custom script contents are withheld.',
    },
    'information.inspect': {
        data: z.object({ ...informationDataSchemas['information.inspect'].shape,
            information: omitFields(informationDataSchemas['information.inspect'].shape.information, 'data'),
        }),
        description: 'Read selected event information and its original version. Arbitrary attached metadata is withheld.',
    },
    'songs.inspect': {
        data: z.object({ ...informationDataSchemas['songs.inspect'].shape,
            information: omitFields(informationDataSchemas['songs.inspect'].shape.information, 'data'),
        }),
        description: 'Read the selected songbook entry and its version. Arbitrary attached metadata is withheld.',
    },
    'products.list': {
        data: z.object({ ...productPage.shape,
            products: z.array(omitFields(productAdminSchema, 'data', 'price_changes', 'visibility_changes')).max(100),
        }),
        description: 'Read a bounded product catalog page with prices, versions, form references, stock contexts and sales counts. Raw product metadata and change records are withheld.',
    },
    'inventory.pools.inspect': {
        data: z.object({ ...inventoryPool.shape,
            settings: z.object({ ...inventoryPool.shape.settings.shape,
                pool: omitFields(inventoryPool.shape.settings.shape.pool, 'data'),
                contexts: z.array(omitFields(inventoryPool.shape.settings.shape.contexts.element, 'data')).max(2000),
            }),
        }),
        description: 'Read one stock pool’s settings, stock contexts and current version. Arbitrary attached metadata is withheld.',
    },
    'inventory.resources.list': {
        data: z.object({ ...inventoryResources.shape,
            resources: z.array(omitFields(inventoryResources.shape.resources.element, 'booking_rules')).max(100),
        }),
        description: 'Read a bounded stock resource page with capacity and version. Raw booking rule payloads are withheld.',
    },
    'email_templates.preview': {
        data: omitFields(emailTemplateDataSchemas['email_templates.preview'], 'senderAddress'),
        description: 'Render a saved scoped email using the ordinary renderer and a synthetic scenario. No real order, routing address or recipient is returned. Template HTML is untrusted data. Does not send email.',
    },
    'waitlist.detail': {
        data: z.object({ occasionId: id, formId: id, detail: z.object({
            orderId: id,
            sourceOrderId: id.nullable(),
            occasionTitle: nullableText,
            capacity: waitlistCapacity,
            tickets: z.array(z.object({ id, waitlistQueueAt: timestamp, lifecycle: state })),
            offers: z.array(offer),
            linkedOrders: z.array(z.object({ id, orderSymbol: nullableText, state })),
        }) }),
        description: 'Read a waiting order, ticket queue times, offer outcomes, capacity and linked order states. Requires waitlist-read and orders-read consent. Names, answers and offer capabilities are withheld.',
    },
};

export function publicReadSummary(operation) {
    return summaries[operation];
}
