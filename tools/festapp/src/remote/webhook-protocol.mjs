import { createHmac, randomBytes } from 'node:crypto';
import { z } from 'zod';

// Wire-level foundation only. Admission, persistence and dispatch belong to the
// existing hosted runner and domain SQL, not to this module.
export const WEBHOOK_TYPES = Object.freeze({
    orderCreated: 'net.festapp.order.created.v1',
    test: 'net.festapp.webhook.test.v1',
});
export const WEBHOOK_LIMITS = Object.freeze({
    bodyBytes: 262144, attempts: 16, lifetimeMs: 72 * 60 * 60 * 1000,
    initialBackoffMs: 5000, maxBackoffMs: 6 * 60 * 60 * 1000,
    timeoutMs: 10000, concurrency: 4,
});
const id = z.uuid();
const entityId = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
export const webhookEnvelopeSchema = z.strictObject({
    specversion: z.literal('1.0'),
    id,
    source: z.string().regex(/^https:\/\/api\.festapp\.net\/integrations\/organizations\/[1-9][0-9]*$/),
    type: z.enum(Object.values(WEBHOOK_TYPES)),
    subject: z.string().regex(/^(orders\/[1-9][0-9]*|webhooks\/test)$/),
    time: z.iso.datetime({ offset: true }),
    datacontenttype: z.literal('application/json'),
    // Domain snapshot validation is owned by the producer's dedicated contract.
    // A valid envelope alone is never admission to send private domain data.
    data: z.record(z.string(), z.json()),
}).superRefine((event, context) => {
    const order = event.type === WEBHOOK_TYPES.orderCreated;
    if (order !== event.subject.startsWith('orders/'))
        context.addIssue({ code: 'custom', path: ['subject'], message: 'Event type and subject disagree' });
});

/** Supply the persisted event ID and occurrence time; retries must not mint them. */
export function createWebhookEvent({ eventId, organizationId, orderId, type, occurredAt, data }) {
    entityId.parse(organizationId);
    if (type === WEBHOOK_TYPES.orderCreated) entityId.parse(orderId);
    else if (orderId !== undefined) throw new Error('INVALID_WEBHOOK_SUBJECT');
    return webhookEnvelopeSchema.parse({
        specversion: '1.0', id: eventId,
        source: `https://api.festapp.net/integrations/organizations/${organizationId}`,
        type, subject: type === WEBHOOK_TYPES.orderCreated ? `orders/${orderId}` : 'webhooks/test',
        time: occurredAt, datacontenttype: 'application/json', data,
    });
}

/** Persist this exact string once per delivery projection; never rebuild on retry. */
export function serializeWebhookEvent(event) {
    const body = JSON.stringify(webhookEnvelopeSchema.parse(event));
    if (Buffer.byteLength(body, 'utf8') > WEBHOOK_LIMITS.bodyBytes) throw new Error('WEBHOOK_BODY_TOO_LARGE');
    return body;
}

export function generateWebhookSecret() {
    return 'whsec_' + randomBytes(32).toString('base64');
}

function signingKey(secret) {
    if (typeof secret !== 'string' || !/^whsec_[A-Za-z0-9+/]{43}=$/.test(secret))
        throw new Error('INVALID_WEBHOOK_KEY');
    const encoded = secret.slice(6), key = Buffer.from(encoded, 'base64');
    if (key.length !== 32 || key.toString('base64') !== encoded) throw new Error('INVALID_WEBHOOK_KEY');
    return key;
}

/** Standard Webhooks v1: delivery ID is stable; send timestamp changes per attempt.
 * Rotation can pass current and retiring keys during a caller-enforced overlap.
 * Keys are never returned in the result. This method does not authorize sending.
 */
export function signWebhook({ deliveryId, body, secrets, timestamp }) {
    id.parse(deliveryId);
    if (!Number.isSafeInteger(timestamp) || timestamp < 0) throw new Error('INVALID_WEBHOOK_TIMESTAMP');
    if (typeof body !== 'string' || Buffer.byteLength(body, 'utf8') > WEBHOOK_LIMITS.bodyBytes)
        throw new Error('INVALID_WEBHOOK_BODY');
    if (!Array.isArray(secrets) || secrets.length < 1 || secrets.length > 2 || new Set(secrets).size !== secrets.length)
        throw new Error('INVALID_WEBHOOK_KEYS');
    const input = `${deliveryId}.${timestamp}.${body}`;
    const signatures = secrets.map(secret => 'v1,' + createHmac('sha256', signingKey(secret)).update(input, 'utf8').digest('base64'));
    return Object.freeze({
        'content-type': 'application/cloudevents+json',
        'webhook-id': deliveryId,
        'webhook-timestamp': String(timestamp),
        'webhook-signature': signatures.join(' '),
    });
}

/** No redirects are followed. A null status means a network/timeout failure. */
export function webhookResponseDisposition(status) {
    if (status !== null && (!Number.isInteger(status) || status < 200 || status > 599))
        throw new Error('INVALID_WEBHOOK_STATUS');
    if (status !== null && status < 300) return 'succeeded';
    if (status === 410) return 'disabled';
    return 'retry';
}

/** Return the next absolute due time, or null when the series is exhausted.
 * attempt is the count of completed attempts, starting at 1. Retry-After is an
 * already parsed delta in seconds; invalid external values are ignored upstream.
 */
export function nextWebhookAttempt({ attempt, firstAttemptAt, now, jitter = Math.random(), retryAfterSeconds = 0 }) {
    if (!Number.isInteger(attempt) || attempt < 1 ||
        !Number.isSafeInteger(firstAttemptAt) || firstAttemptAt < 0 ||
        !Number.isSafeInteger(now) || now < firstAttemptAt ||
        !Number.isFinite(jitter) || jitter < 0 || jitter > 1 ||
        !Number.isFinite(retryAfterSeconds) || retryAfterSeconds < 0)
        throw new Error('INVALID_WEBHOOK_RETRY');
    const deadline = firstAttemptAt + WEBHOOK_LIMITS.lifetimeMs;
    if (!Number.isSafeInteger(deadline)) throw new Error('INVALID_WEBHOOK_RETRY');
    if (attempt >= WEBHOOK_LIMITS.attempts || now >= deadline) return null;
    const base = Math.min(WEBHOOK_LIMITS.maxBackoffMs, WEBHOOK_LIMITS.initialBackoffMs * 2 ** (attempt - 1));
    const backoff = Math.min(WEBHOOK_LIMITS.maxBackoffMs, Math.ceil(base * (0.75 + jitter * 0.5)));
    const due = now + Math.max(backoff, Math.ceil(retryAfterSeconds * 1000));
    return Number.isSafeInteger(due) && due < deadline ? due : null;
}
