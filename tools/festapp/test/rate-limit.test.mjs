import test from 'node:test';
import assert from 'node:assert/strict';
import { createRateLimiter, clientIdentity } from '../src/remote/rate-limit.mjs';

test('fixed windows retain expiry, independent buckets and bounded cardinality', () => {
    let time = 0;
    const limit = createRateLimiter({ now: () => time, capacity: 3 });
    for (let i = 0; i < 240; i++) limit('http', 'a', 240);
    assert.throws(() => limit('http', 'a', 240), e => e.retryAfter === 60);
    time = 59001;
    assert.throws(() => limit('http', 'a', 240), e => e.retryAfter === 1);
    limit('http', 'b', 240); limit('grant', 'a', 60);
    assert.throws(() => limit('http', 'c', 240));
    assert.throws(() => limit('http', 'a', 240));
    time = 60000; limit('http', 'a', 240);
});
test('canonical IP requires one valid trusted header; local cannot opt in', () => {
    const req = { socket: { remoteAddress: '127.0.0.1' }, headers: { 'x-festapp-client-ip': '::ffff:192.0.2.1' }, rawHeaders: ['X-Festapp-Client-IP','::ffff:192.0.2.1'] };
    assert.equal(clientIdentity(req, true), '192.0.2.1');
    assert.equal(clientIdentity(req, false), '127.0.0.1');
    for (const value of ['', '1.2.3.4, 5.6.7.8', 'fake', 'fe80::1%eth0']) assert.throws(() => clientIdentity({ ...req, headers: { 'x-festapp-client-ip': value } }, true));
    assert.throws(() => clientIdentity({ ...req, rawHeaders: [...req.rawHeaders,...req.rawHeaders] }, true));
    assert.throws(() => clientIdentity({ ...req, rawHeaders: [] }, true));
});
