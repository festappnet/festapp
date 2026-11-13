import { operationAuthentication } from '../auth/operation-policy.mjs';
import { API_SUMMARY_OPERATIONS } from './client-policy.mjs';
import { z } from 'zod';
import { catalogProjection, schemaProjection } from '../operations/contract-projection.mjs';
import { DELEGATED_OPERATIONS, scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';
export const API_COST_BUDGET = Object.freeze({documentPerOrgPerMinute:24,documentPerClientOrgPerMinute:16,concurrentDocuments:2,concurrentPerOrg:1});
export const API_JSON_LIMITS = Object.freeze({ bytes: 49152, depth: 32, nodes: 8192 });
export const operationIds = DELEGATED_OPERATIONS;
const catalogs = new Map();
export function publicCatalog(dataProfile = 'operator') {
    if (catalogs.has(dataProfile)) return catalogs.get(dataProfile);
    const catalog = Object.freeze(catalogProjection(operationIds, dataProfile === 'order-summary'));
    catalogs.set(dataProfile, catalog);
    return catalog;
}

// All adapters use the same validated Operations executor and SQL owners.
// Transport authentication is explicit; it does not replace SQL rights,
// confirmation fingerprints, aggregate versions or durable domain receipts.
export function readiness(descriptor, dataProfile = 'operator', proofProfile) {
    if (dataProfile === 'order-summary' && !API_SUMMARY_OPERATIONS.includes(descriptor.id))
        return { supported: false, reason: 'Not exposed by the read-only order-summary API profile.' };
    const authentication = operationAuthentication(descriptor.id);
    if (proofProfile === 'bearer' && authentication)
        return { supported: false, reason: 'Requires the registered DPoP + PAR profile and fresh GoTrue AAL2 authentication.', authentication };
    if (descriptor.domainReadOnly && !descriptor.requiresLayoutWriteContract)
        return { supported: true, retry: 'Read may be repeated. Keyset pages are not a snapshot.' };
    if (descriptor.id === 'ticket_layouts.preview') return {supported:true,retry:'Synthetic preview consumes document quota. Repeat explicitly with fresh proof; it does not save artwork. The PDF expires after 15 minutes and is bound to this active grant.'};
    return { supported: true, ...(authentication ? {authentication} : {}),
        ...(descriptor.requiresLayoutWriteContract ? { requiresLayoutWriteContract: true } : {}),
        retry: descriptor.requiresLayoutWriteContract
            ? 'Retain the complete original saveRequest: repeating it derives the same SQL command after a lost outward reply, including after reconnect. Pending/resume recovers unresolved upstream results for the same actor and tenant. Runtime negotiates the canonical SQL write contract before admission.'
            : 'Preserve the original command identity, payload, preview confirmation and expected aggregate version after an uncertain response. Replay uses the same SQL owner and current rights as MCP; it never implies a second business effect.' };
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
    409: ['AGENDA_CHANGED_RELOAD_REQUIRED', 'BLUEPRINT_CHANGED_RELOAD_REQUIRED', 'BLUEPRINT_HOLDS_CHANGED', 'BLUEPRINT_ORDER_CHANGED', 'BLUEPRINT_REVISION_CONFLICT', 'BLUEPRINT_SWAP_CHANGED', 'CONFIGURATION_CHANGED_RELOAD_REQUIRED', 'DRAFT_PREVIEW_MISMATCH', 'EMAIL_TEMPLATE_CHANGED_RELOAD_REQUIRED', 'FORM_CHANGED_RELOAD_REQUIRED', 'INVENTORY_CHANGED_RELOAD_REQUIRED', 'INVENTORY_ASSIGNMENT_CHANGED_RELOAD_REQUIRED', 'ORDER_CHANGED_RELOAD_REQUIRED', 'ORDER_CHANGED_REPREVIEW_REQUIRED', 'PEOPLE_CHANGED_RELOAD_REQUIRED', 'PRODUCT_CHANGED_RELOAD_REQUIRED', 'PRODUCT_SCHEDULE_CHANGED_RELOAD_REQUIRED', 'PROGRAM_CHANGED_RELOAD_REQUIRED', 'SEAT_CANCELLATION_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_HOLDS_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_ORDER_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_ORDER_REJECTED_NEW_PREVIEW_REQUIRED', 'SEAT_RELEASE_REJECTED_NEW_PREVIEW_REQUIRED', 'SEAT_REVISION_CHANGED_RELOAD_REQUIRED', 'SEAT_SWAP_CHANGED_NEW_PREVIEW_REQUIRED', 'SEAT_SWAP_REJECTED_NEW_PREVIEW_REQUIRED', 'SETUP_CHANGED_RELOAD_REQUIRED', 'WAITLIST_CHANGED_REFRESH_REQUIRED', 'PENDING_RECOVERY_REQUIRED'],
    410: ['COMMAND_EXPIRED_DO_NOT_REPLAY', 'RECEIPT_EXPIRED'],
    413: ['BODY_TOO_LARGE'], 415: ['UNSUPPORTED_MEDIA_TYPE'],
    422: ['INVALID_INPUT', 'AGENDA_CHANGE_REJECTED', 'ARTIFACT_TOO_LARGE', 'BANK_CHANGE_REJECTED', 'BLUEPRINT_DRAFT_REJECTED', 'CARD_OPERATION_REJECTED', 'CONFIGURATION_REJECTED', 'EMAIL_TEMPLATE_REJECTED', 'FORM_CHANGE_REJECTED', 'FORM_RESULT_TOO_LARGE', 'HISTORY_DELETION_REJECTED', 'HISTORY_ENTRY_OR_RANGE_REJECTED', 'HISTORY_UNAVAILABLE_OR_INVALID_RANGE', 'INVENTORY_INTENTION_REJECTED', 'LIFECYCLE_REJECTED', 'ORDER_CHANGE_REJECTED', 'ORDER_CREATION_REJECTED', 'ORDER_DELETION_REJECTED', 'ORDER_NOT_CREATABLE', 'PEOPLE_CHANGE_REJECTED', 'PRODUCT_CHANGE_REJECTED', 'PRODUCT_OPTION_PAGE_TOO_LARGE_USE_SMALLER_LIMIT', 'PRODUCT_SCHEDULE_REJECTED', 'PROGRAM_CHANGE_REJECTED', 'REFUND_DECISION_REJECTED', 'SCANNER_INTENT_REJECTED', 'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT', 'SEAT_CANCELLATION_REJECTED', 'SEAT_RELEASE_REJECTED', 'SEAT_SELECTION_REJECTED', 'SEAT_SWAP_CURRENCY_MISMATCH', 'SEAT_SWAP_GROUP_SIZE_MISMATCH', 'SEAT_SWAP_MONEY_UNAVAILABLE', 'SEAT_SWAP_PROTECTED', 'SEAT_SWAP_REJECTED', 'SEAT_SWAP_STRIPE_PRICE_IMMUTABLE', 'SEAT_SWAP_USED_ATOMIC_GROUP', 'SETUP_FINALIZATION_REJECTED', 'STANDING_INVENTORY_REJECTED'],
    429: ['TEMPORARILY_LIMITED', 'SCANNER_RATE_LIMITED_RETRY_SAME_OPERATION'],
    502: ['UPSTREAM_CONTRACT_FAILURE'],
    503: ['FAMILY_NOT_READY', 'UNAVAILABLE', 'LIFECYCLE_PENDING_RETRY_SAME_COMMAND', 'ORDER_RESULT_UNCERTAIN_RETRY_SAME_COMMAND', 'TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND', 'TEMPORARY_FAILURE_RETRY_SAME_COMMAND'],
    504: ['TIMEOUT'],
}).flatMap(([status, codes]) => codes.map(code => [code, Number(status)]))));
