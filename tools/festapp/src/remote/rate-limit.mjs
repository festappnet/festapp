import { isIP } from 'node:net';
import { performance } from 'node:perf_hooks';
import { digest } from '../context/profile.mjs';
import { OperationError } from '../errors.mjs';

// Synchronous fixed windows in the single owning process. Never evict a live
// identity: doing so would reset its quota under cardinality pressure.
export function createRateLimiter({ now = () => performance.now(), capacity = 20000, windowMs = 60000 } = {}) {
    const buckets = new Map();
    return (type, identity, max) => {
        const time = now();
        const key = digest(JSON.stringify([type, identity]));
        let bucket = buckets.get(key);
        if (!bucket || bucket.expiresAt <= time) {
            for (const [id, value] of buckets) if (value.expiresAt <= time) buckets.delete(id);
            if (buckets.size >= capacity) {
                const earliest = Math.min(...[...buckets.values()].map(v => v.expiresAt));
                const error = new OperationError('TEMPORARILY_LIMITED', true);
                error.retryAfter = Math.max(1, Math.ceil((earliest - time) / 1000));
                throw error;
            }
            bucket = { count: 0, expiresAt: time + windowMs };
            buckets.set(key, bucket);
        }
        if (bucket.count >= max) {
            const error = new OperationError('TEMPORARILY_LIMITED', true);
            error.retryAfter = Math.max(1, Math.ceil((bucket.expiresAt - time) / 1000));
            throw error;
        }
        bucket.count++;
    };
}

export function clientIdentity(req, canonical) {
    if (!canonical) return req.socket.remoteAddress;
    const entries = req.rawHeaders.filter((_, i) => i % 2 === 0)
        .filter(name => name.toLowerCase() === 'x-festapp-client-ip');
    const ip = req.headers['x-festapp-client-ip'];
    if (entries.length !== 1 || typeof ip !== 'string' || !isIP(ip) || ip.includes('%'))
        throw new OperationError('FORBIDDEN');
    if (isIP(ip) === 4) return ip;
    const normalized = new URL(`http://[${ip}]/`).hostname.slice(1, -1);
    const mapped = normalized.match(/^::ffff:([a-f0-9]+):([a-f0-9]+)$/);
    return mapped ? [parseInt(mapped[1],16) >>> 8, parseInt(mapped[1],16) & 255,
        parseInt(mapped[2],16) >>> 8, parseInt(mapped[2],16) & 255].join('.') : normalized;
}
