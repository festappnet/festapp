import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import {
    WEBHOOK_TYPES, WEBHOOK_LIMITS, webhookEnvelopeSchema, createWebhookEvent,
    serializeWebhookEvent, generateWebhookSecret, signWebhook,
    webhookResponseDisposition, nextWebhookAttempt,
} from '../src/remote/webhook-protocol.mjs';

// Public synthetic fixtures, never live endpoint credentials.
const eventId = '11111111-1111-4111-8111-111111111111';
const deliveryId = '22222222-2222-4222-8222-222222222222';
const occurredAt = '2026-11-14T12:00:00.123456Z';
const secret = 'whsec_' + Buffer.from('0123456789abcdef0123456789abcdef').toString('base64');
const secondSecret = 'whsec_' + Buffer.alloc(32, 42).toString('base64');
const input = () => ({ eventId, organizationId: 3, orderId: 7,
    type: WEBHOOK_TYPES.orderCreated, occurredAt,
    data: { customer: { name: 'Jana', surname: 'Nová', email: 'jana@example.invalid' },
        responses: [{ '48': 'Bezlepková strava', '49': true, '50': ['A', 'B'] }] },
});

async function verifies(headers, body, key = secret) {
    const cryptoKey = await webcrypto.subtle.importKey('raw', Buffer.from(key.slice(6), 'base64'),
        { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    const bytes = Buffer.from(`${headers['webhook-id']}.${headers['webhook-timestamp']}.${body}`, 'utf8');
    const results = await Promise.all(headers['webhook-signature'].split(' ').map(signature =>
        webcrypto.subtle.verify('HMAC', cryptoKey, Buffer.from(signature.slice(3), 'base64'), bytes)));
    return results.some(Boolean);
}

test('CloudEvents keeps persisted identity, occurrence precision, stable field IDs and typed values', () => {
    const event = createWebhookEvent(input());
    assert.equal(event.specversion, '1.0');
    assert.equal(event.id, eventId);
    assert.equal(event.source, 'https://api.festapp.net/integrations/organizations/3');
    assert.equal(event.subject, 'orders/7');
    assert.equal(event.time, occurredAt);
    assert.deepEqual(event.data.responses, input().data.responses);
    const body = serializeWebhookEvent(event);
    assert.deepEqual(JSON.parse(body), event);
    assert.ok(body.includes('Nová'));
    assert.equal(event.datacontenttype, 'application/json');
});

test('synthetic test is distinguishable from a real order', () => {
    const args = { ...input(), type: WEBHOOK_TYPES.test }; delete args.orderId;
    const event = createWebhookEvent(args);
    assert.equal(event.subject, 'webhooks/test');
    assert.equal(event.type, WEBHOOK_TYPES.test);
    assert.throws(() => createWebhookEvent({ ...args, orderId: 7 }), /INVALID_WEBHOOK_SUBJECT/);
    assert.equal(webhookEnvelopeSchema.safeParse({ ...event, subject: 'orders/7' }).success, false);
    assert.equal(webhookEnvelopeSchema.safeParse({ ...createWebhookEvent(input()), subject: 'webhooks/test' }).success, false);
});

test('event creation rejects missing identity/time, unsafe numeric IDs and unregistered event types', () => {
    for (const change of [
        { eventId: undefined }, { eventId: 'not-an-id' }, { occurredAt: undefined },
        { occurredAt: '2026-11-14' }, { type: 'net.festapp.order.paid.v1' },
        { organizationId: 0 }, { organizationId: '3' }, { organizationId: Number.MAX_SAFE_INTEGER + 1 },
        { orderId: -1 }, { orderId: undefined }, { orderId: 7.5 }, { data: [] },
    ]) assert.throws(() => createWebhookEvent({ ...input(), ...change }));
    assert.equal(webhookEnvelopeSchema.safeParse({ ...createWebhookEvent(input()), token: 'unwanted' }).success, false);
    assert.equal(webhookEnvelopeSchema.safeParse({ ...createWebhookEvent(input()), source: 'https://other.invalid/3' }).success, false);
});

test('payload cap measures UTF-8 bytes including the envelope, and accepts the exact limit', () => {
    const event = createWebhookEvent({ ...input(), data: { text: '' } });
    const overhead = Buffer.byteLength(serializeWebhookEvent(event));
    event.data.text = 'a'.repeat(WEBHOOK_LIMITS.bodyBytes - overhead);
    assert.equal(Buffer.byteLength(serializeWebhookEvent(event)), WEBHOOK_LIMITS.bodyBytes);
    event.data.text += 'a';
    assert.throws(() => serializeWebhookEvent(event), /WEBHOOK_BODY_TOO_LARGE/);
    event.data.text = 'ě'.repeat(Math.floor((WEBHOOK_LIMITS.bodyBytes - overhead) / 2) + 1);
    assert.throws(() => serializeWebhookEvent(event), /WEBHOOK_BODY_TOO_LARGE/);
});

test('Standard Webhooks signature interoperates with an independent WebCrypto receiver', async () => {
    const body = serializeWebhookEvent(createWebhookEvent(input()));
    const headers = signWebhook({ deliveryId, body, secrets: [secret], timestamp: 1794657600 });
    assert.equal(headers['content-type'], 'application/cloudevents+json');
    assert.equal(headers['webhook-id'], deliveryId);
    assert.equal(headers['webhook-timestamp'], '1794657600');
    assert.equal(await verifies(headers, body), true);
    assert.equal(await verifies(headers, body.replace('Jana', 'Eva')), false);
    assert.equal(await verifies({ ...headers, 'webhook-timestamp': '1794657601' }, body), false);
    assert.equal(await verifies({ ...headers, 'webhook-id': eventId }, body), false);
    assert.equal(await verifies(headers, body, secondSecret), false);
    assert.equal(Object.values(headers).some(value => value.includes(secret)), false);
});

test('signature matches a frozen Python hmac/hashlib UTF-8 fixture', () => {
    const headers = signWebhook({ deliveryId: eventId, body: '{"hello":"svět"}', secrets: [secret], timestamp: 1794657600 });
    assert.equal(headers['webhook-signature'], 'v1,JtVxIq/ifFoIhcOYwNB9XdDawHtquQ6ydV4Q2WhsPwg=');
});

test('signing preserves exact UTF-8 bytes and refuses oversized bodies', async () => {
    const body = '{ "text": "svět" }\n';
    const headers = signWebhook({ deliveryId, body, secrets: [secret], timestamp: 42 });
    assert.equal(await verifies(headers, body), true);
    assert.equal(await verifies(headers, JSON.stringify(JSON.parse(body))), false);
    assert.throws(() => signWebhook({ deliveryId, body: 'ě'.repeat(WEBHOOK_LIMITS.bodyBytes), secrets: [secret], timestamp: 42 }), /INVALID_WEBHOOK_BODY/);
});

test('retry changes send signature/time while preserving original event, occurrence time and delivery identity', () => {
    const body = serializeWebhookEvent(createWebhookEvent(input()));
    const first = signWebhook({ deliveryId, body, secrets: [secret], timestamp: 100 });
    const retry = signWebhook({ deliveryId, body, secrets: [secret], timestamp: 200 });
    assert.equal(first['webhook-id'], retry['webhook-id']);
    assert.notEqual(first['webhook-signature'], retry['webhook-signature']);
    assert.equal(JSON.parse(body).time, occurredAt);
    assert.equal(JSON.parse(body).id, eventId);
});

test('rotation signs with both keys and both receivers verify during overlap', async () => {
    const body = serializeWebhookEvent(createWebhookEvent(input()));
    const headers = signWebhook({ deliveryId, body, secrets: [secondSecret, secret], timestamp: 10 });
    assert.equal(headers['webhook-signature'].split(' ').length, 2);
    assert.equal(await verifies(headers, body, secret), true);
    assert.equal(await verifies(headers, body, secondSecret), true);
    const retired = signWebhook({ deliveryId, body, secrets: [secondSecret], timestamp: 11 });
    assert.equal(await verifies(retired, body, secret), false);
});

test('generated signing keys have canonical 32-byte random encoding', () => {
    const keys = new Set(Array.from({ length: 16 }, generateWebhookSecret));
    assert.equal(keys.size, 16);
    for (const key of keys) {
        assert.match(key, /^whsec_[A-Za-z0-9+/]{43}=$/);
        assert.equal(Buffer.from(key.slice(6), 'base64').length, 32);
        signWebhook({ deliveryId, body: '{}', secrets: [key], timestamp: 1 });
    }
});

test('invalid or ambiguous signing inputs fail closed', () => {
    const base = { deliveryId, body: '{}', secrets: [secret], timestamp: 1 };
    for (const change of [
        { secrets: [] }, { secrets: [secret, secret] }, { secrets: [secret, secondSecret, secret] },
        { secrets: ['whsec_' + 'A'.repeat(44)] }, { secrets: [secret.slice(0, -1)] },
        { secrets: [secret + '\n'] }, { secrets: ['whsec_' + Buffer.alloc(24).toString('base64')] },
        { secrets: null }, { body: undefined }, { body: {} }, { timestamp: '1' },
        { timestamp: NaN }, { timestamp: -1 }, { timestamp: 0.5 }, { timestamp: Infinity },
        { deliveryId: deliveryId + '\r\nx: yes' },
    ]) assert.throws(() => signWebhook({ ...base, ...change }));
    // Node's base64 decoder tolerates nonzero padding bits; our format does not.
    const canonical = 'whsec_' + Buffer.alloc(32).toString('base64');
    const noncanonical = canonical.slice(0, -2) + 'B=';
    assert.throws(() => signWebhook({ ...base, secrets: [noncanonical] }), /INVALID_WEBHOOK_KEY/);
});

test('only 2xx succeeds, 410 disables, all other final statuses and network failures retry', () => {
    for (const status of [200, 202, 204, 299]) assert.equal(webhookResponseDisposition(status), 'succeeded');
    assert.equal(webhookResponseDisposition(410), 'disabled');
    for (const status of [null, 300, 301, 307, 400, 401, 403, 404, 408, 429, 500, 503, 599])
        assert.equal(webhookResponseDisposition(status), 'retry');
    for (const status of [undefined, '200', 0, 100, 199, 600, 200.5])
        assert.throws(() => webhookResponseDisposition(status), /INVALID_WEBHOOK_STATUS/);
});

test('backoff has bounded jitter, exponential growth and a six-hour cap', () => {
    const base = { firstAttemptAt: 1000, now: 1000 };
    assert.equal(nextWebhookAttempt({ ...base, attempt: 1, jitter: 0 }), 4750);
    assert.equal(nextWebhookAttempt({ ...base, attempt: 1, jitter: 1 }), 7250);
    assert.equal(nextWebhookAttempt({ ...base, attempt: 2, jitter: 0.5 }), 11000);
    assert.equal(nextWebhookAttempt({ ...base, attempt: 15, jitter: 1 }), 1000 + WEBHOOK_LIMITS.maxBackoffMs);
    assert.equal(nextWebhookAttempt({ ...base, attempt: 1, jitter: 0, retryAfterSeconds: 60 }), 61000);
});

test('retry exhaustion respects attempt limit, lifetime and Retry-After without early retry', () => {
    const base = { firstAttemptAt: 1000, now: 1000, attempt: 1, jitter: 0.5 };
    assert.equal(nextWebhookAttempt({ ...base, attempt: WEBHOOK_LIMITS.attempts }), null);
    assert.equal(nextWebhookAttempt({ ...base, now: 1000 + WEBHOOK_LIMITS.lifetimeMs }), null);
    assert.equal(nextWebhookAttempt({ ...base, now: 1000 + WEBHOOK_LIMITS.lifetimeMs - 5000 }), null);
    assert.equal(nextWebhookAttempt({ ...base, retryAfterSeconds: WEBHOOK_LIMITS.lifetimeMs / 1000 }), null);
    assert.equal(nextWebhookAttempt({ ...base, retryAfterSeconds: Number.MAX_VALUE }), null);
});

test('retry accounting rejects corrupt persisted values', () => {
    const base = { firstAttemptAt: 1000, now: 1000, attempt: 1, jitter: 0.5 };
    for (const change of [
        { firstAttemptAt: -1 }, { firstAttemptAt: Number.MAX_SAFE_INTEGER, now: Number.MAX_SAFE_INTEGER },
        { now: 999 }, { now: NaN }, { attempt: 0 }, { attempt: 0.5 },
        { jitter: -0.1 }, { jitter: 1.1 }, { jitter: NaN },
        { retryAfterSeconds: -1 }, { retryAfterSeconds: Infinity },
    ]) assert.throws(() => nextWebhookAttempt({ ...base, ...change }), /INVALID_WEBHOOK_RETRY/);
});
