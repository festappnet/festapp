import { API_SUMMARY_OPERATIONS } from './client-policy.mjs';
import { z } from 'zod';
import { catalogProjection, schemaProjection } from '../operations/contract-projection.mjs';
import { READ_OPERATIONS, MCP_PERMISSIONS, scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
export const API_COST_BUDGET = Object.freeze({documentPerOrgPerMinute:24,documentPerClientOrgPerMinute:16,concurrentDocuments:2,concurrentPerOrg:1});
export const API_JSON_LIMITS = Object.freeze({ bytes: 49152, depth: 32, nodes: 8192 });
export const operationIds = Object.freeze([...new Set([...READ_OPERATIONS, 'occasions.create', ...Object.values(MCP_PERMISSIONS).flatMap(p => p.operations)])]);
const catalogs = new Map();
export function publicCatalog(dataProfile = 'operator') {
    if (catalogs.has(dataProfile)) return catalogs.get(dataProfile);
    const catalog = Object.freeze(catalogProjection(operationIds, dataProfile === 'order-summary'));
    catalogs.set(dataProfile, catalog);
    return catalog;
}

// Qualification boundaries are explicit per owning family. A catalog entry is
// not permission to bypass its durable intent, preview or stronger login proof.
const mutationGaps = Object.freeze({
    occasions: 'Occasion create/copy/settings/public-link commands need HTTP durable receipt, concurrent version and reconnect qualification; delete/finalize also require the lifecycle proof policy.',
    lifecycle: 'Destructive lifecycle resume requires DPoP, trusted fresh step-up and original durable pending intent; GoTrue bridge currently supplies no qualified acr/auth_time evidence.',
    units: 'Organizer configuration, legal submission and people/role changes need command-specific HTTP version, receipt, reconnect and revocation qualification; privilege changes require trusted step-up.',
    banks: 'Bank control requires DPoP plus trusted fresh step-up, stored linked-unit scope and durable provider reconciliation. The current bridge cannot prove the required acr/auth_time.',
    cards: 'Card disconnect/refund decisions require DPoP plus trusted fresh step-up and provider unknown-outcome reconciliation; neither body claims nor preview prove MFA.',
    history: 'History deletion requires DPoP plus trusted fresh step-up and bounded deletion/receipt qualification; the current bridge cannot prove the login strength.',
    orders: 'Order updates, cancellation, deletion, paid transitions and ticket queue actions need exact preview/confirmation, committed retry and email/payment-intent counts under HTTP revocation races.',
    agenda: 'Agenda/program commands need original aggregate versions and real SQL HTTP create/edit/delete replay, stale revision and reconnect qualification.',
    scanner: 'Admission requires the original scanner operation ID, same-operation rate-limit retry and real SQL concurrent admission/revocation qualification.',
    blueprints: 'Blueprint geometry/text writes require bounded owned media, original revisions and durable prepare/save recovery through HTTP.',
    profiles: 'Person/profile/role/import commands require bounded rows, original versions, partial-result recovery and permission-revoked receipt qualification; role escalation requires trusted step-up.',
    groups: 'Group assignments require versioned replacement semantics and real SQL committed replay/reconnect qualification without duplicate memberships.',
    forms: 'Form create/save/duplicate/delete/checkout needs canonical capacity/payment owner evidence, current aggregate version and committed HTTP replay with no duplicate order or queue intent.',
    waitlist: 'Waitlist decisions/send/withdraw require original ticket IDs, proposal fingerprint and queue fencing; real SQL HTTP replay must prove no duplicate offer or mail intent.',
    email_templates: 'Template changes require exact preview fingerprint and policy/template epoch fencing with committed retry and HTTP revocation evidence.',
    payments: 'Payment recording requires DPoP, trusted fresh step-up, original financial command identity and exact ledger/queue count qualification; the current bridge has no qualified login proof.',
    products: 'Product deletion needs real HTTP usage-guard, original version and committed delete/replay/reconnect qualification; product save is qualified separately.',
    product_schedules: 'Price-wave changes require frozen schedule version and canonical product/order lock, committed replay and stale-preview qualification.',
    inventory: 'Inventory/standing preparation needs existing intent identity, blueprint/order scope locks, no partial stock effect and committed HTTP recovery qualification.',
    seats: 'Seat block/hold/release/swap/order/cancel requires original preview fingerprint, exact command identity, concurrent seat-lock and committed replay with payment/email-intent count evidence.',
});
const agendaFamilies = new Set(['events','exclusiveGroups','places','placeTypes','paths','speakers','topics','attendance','eventSpeakers','counseling','activities','services']);

export function readiness(descriptor, dataProfile = 'operator') {
    if (dataProfile === 'order-summary' && !API_SUMMARY_OPERATIONS.includes(descriptor.id)) return { supported: false, reason: 'Not exposed by the read-only order-summary API profile.' };
    if (descriptor.requiresLayoutWriteContract) return { supported: false, reason: 'Layout contract, bounded media and recovery evidence required.' };
    if (descriptor.domainReadOnly) return { supported: true, retry: 'Read may be repeated. Keyset pages are not a snapshot.' };
    if (descriptor.id === 'ticket_layouts.preview') return {supported:true,retry:'Synthetic preview consumes document quota. Repeat explicitly with fresh proof; it does not save artwork. The PDF expires after 15 minutes and is bound to this active grant.'};
    if (descriptor.id === 'products.save') return { supported: true, retry: 'Keep commandId, payload and expected aggregate version unchanged. Reconnect requires an authorized administrator to establish the original outcome.' };
    const family=descriptor.id.split('.')[0];
    const reason=mutationGaps[agendaFamilies.has(family)?'agenda':family];
    if (!reason) throw new Error('Missing explicit API mutation qualification: '+descriptor.id);
    return { supported: false, reason };
}
export const artifactInput = z.strictObject({ uri: z.string().max(2048).regex(/^festapp-(?:export|preview):\/\/[A-Za-z0-9/_-]+(?:\.[A-Za-z0-9]+)?$/) });
export const problemSchema = z.strictObject({
    type: z.url(), title: z.string(), status: z.number().int(), code: z.string(),
    requestId: z.string().min(1).max(128), retryable: z.boolean(), outcome: z.enum(['rejected', 'unknown']),
});
export const jsonSchema = schemaProjection;
export { scopesForOperation };

// Explicit operation errors; never infer semantics from substrings at runtime.
export const errorStatuses = Object.freeze(Object.fromEntries(Object.entries({
    400: ['MALFORMED_JSON', 'INVALID_INGRESS'],
    401: ['AUTHENTICATION_REQUIRED', 'MFA_REQUIRED', 'INSUFFICIENT_USER_AUTHENTICATION'],
    403: ['FORBIDDEN', 'INSUFFICIENT_SCOPE', 'ORGANIZER_CONSENT_REQUIRED'],
    404: ['NOT_FOUND_OR_INACCESSIBLE', 'UNKNOWN_OPERATION', 'PENDING_NOT_FOUND'],
    405: ['METHOD_NOT_ALLOWED'],
    409: ['AGENDA_CHANGED_RELOAD_REQUIRED', 'BLUEPRINT_CHANGED_RELOAD_REQUIRED', 'BLUEPRINT_HOLDS_CHANGED', 'BLUEPRINT_ORDER_CHANGED', 'BLUEPRINT_REVISION_CONFLICT', 'BLUEPRINT_SWAP_CHANGED', 'CONFIGURATION_CHANGED_RELOAD_REQUIRED', 'DRAFT_PREVIEW_MISMATCH', 'EMAIL_TEMPLATE_CHANGED_RELOAD_REQUIRED', 'FORM_CHANGED_RELOAD_REQUIRED', 'INVENTORY_CHANGED_RELOAD_REQUIRED', 'ORDER_CHANGED_RELOAD_REQUIRED', 'ORDER_CHANGED_REPREVIEW_REQUIRED', 'PEOPLE_CHANGED_RELOAD_REQUIRED', 'PRODUCT_CHANGED_RELOAD_REQUIRED', 'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED', 'PROGRAM_CHANGED_RELOAD_REQUIRED', 'SEAT_CANCELLATION_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_HOLDS_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_ORDER_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_ORDER_REJECTED_NEW_PREVIEW_REQUIRED', 'SEAT_RELEASE_REJECTED_NEW_PREVIEW_REQUIRED', 'SEAT_REVISION_CHANGED_RELOAD_REQUIRED', 'SEAT_SWAP_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_SWAP_REJECTED_NEW_PREVIEW_REQUIRED', 'SETUP_CHANGED_RELOAD_REQUIRED', 'WAITLIST_CHANGED_REFRESH_REQUIRED', 'PENDING_RECOVERY_REQUIRED'],
    410: ['COMMAND_EXPIRED_DO_NOT_REPLAY', 'RECEIPT_EXPIRED'],
    413: ['BODY_TOO_LARGE'], 415: ['UNSUPPORTED_MEDIA_TYPE'],
    422: ['INVALID_INPUT', 'AGENDA_CHANGE_REJECTED', 'ARTIFACT_TOO_LARGE', 'BANK_CHANGE_REJECTED', 'BLUEPRINT_DRAFT_REJECTED', 'CARD_OPERATION_REJECTED', 'CONFIGURATION_REJECTED', 'EMAIL_TEMPLATE_REJECTED', 'FORM_CHANGE_REJECTED', 'FORM_RESULT_TOO_LARGE', 'HISTORY_DELETION_REJECTED', 'HISTORY_ENTRY_OR_RANGE_REJECTED', 'HISTORY_UNAVAILABLE_OR_INVALID_RANGE', 'INVENTORY_INTENTION_REJECTED', 'LIFECYCLE_REJECTED', 'ORDER_CHANGE_REJECTED', 'ORDER_CREATION_REJECTED', 'ORDER_DELETION_REJECTED', 'ORDER_NOT_CREATABLE', 'PEOPLE_CHANGE_REJECTED', 'PRODUCT_CHANGE_REJECTED', 'PRODUCT_OPTION_PAGE_TOO_LARGE_USE_SMALLER_LIMIT', 'PRODUCT_SCHEDULE_REJECTED', 'PROGRAM_CHANGE_REJECTED', 'REFUND_DECISION_REJECTED', 'SCANNER_INTENT_REJECTED', 'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT', 'SEAT_CANCELLATION_REJECTED', 'SEAT_RELEASE_REJECTED', 'SEAT_SELECTION_REJECTED', 'SEAT_SWAP_CURRENCY_MISMATCH', 'SEAT_SWAP_GROUP_SIZE_MISMATCH', 'SEAT_SWAP_MONEY_UNAVAILABLE', 'SEAT_SWAP_PROTECTED', 'SEAT_SWAP_REJECTED', 'SEAT_SWAP_STRIPE_PRICE_IMMUTABLE', 'SEAT_SWAP_USED_ATOMIC_GROUP', 'SETUP_FINALIZATION_REJECTED', 'STANDING_INVENTORY_REJECTED'],
    429: ['TEMPORARILY_LIMITED', 'SCANNER_RATE_LIMITED_RETRY_SAME_OPERATION'],
    502: ['UPSTREAM_CONTRACT_FAILURE'],
    503: ['FAMILY_NOT_READY', 'UNAVAILABLE', 'LIFECYCLE_PENDING_RETRY_SAME_COMMAND', 'ORDER_RESULT_UNCERTAIN_RETRY_SAME_COMMAND', 'TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND', 'TEMPORARY_FAILURE_RETRY_SAME_COMMAND'],
    504: ['TIMEOUT'],
}).flatMap(([status, codes]) => codes.map(code => [code, Number(status)]))));
