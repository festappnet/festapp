// Coverage is issued by the server for managed exports. Explicit integrations
// retain the cutoff and age they configured; a saved CMP choice cannot widen it.
const instant = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
export function consentValidity(config) {
    if (!instant(config.consentValidFrom) || !Number.isSafeInteger(config.maxAgeSeconds) ||
        config.maxAgeSeconds <= 0 || config.maxAgeSeconds > 365 * 86400) return null;
    const from = Date.parse(config.consentValidFrom), age = config.maxAgeSeconds * 1000;
    return (timestamp, now) => Number.isSafeInteger(timestamp) && timestamp >= from &&
        timestamp <= now + 60000 && now - timestamp < age;
}
