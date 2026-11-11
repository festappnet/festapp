/** Explicit consent durations, shared by issuer and first-party consent UI. */
export const CONNECTION_DURATION_DAYS = Object.freeze([7, 30, 90, 365]);
export const DEFAULT_CONNECTION_DURATION_DAYS = 7;
export const MAX_CONNECTION_DURATION_DAYS = 365;
export const DAY_SECONDS = 86400;

export const CONNECTION_IDLE_SECONDS = 30 * DAY_SECONDS;
/** One lifecycle predicate for resource access, refresh and management. */
export function connectionDeadline(grant) {
    return grant?.lifecycle === 'issued'
        ? Math.min(grant.expiresAt, grant.lastTokenExchangeAt + CONNECTION_IDLE_SECONDS * 1000)
        : grant?.expiresAt ?? 0;
}
export function connectionActive(grant, now = Date.now()) {
    return Boolean(grant && ['issued', 'legacy'].includes(grant.lifecycle) &&
        !grant.revoked && connectionDeadline(grant) > now);
}
export function connectionIssuable(grant, now = Date.now()) {
    return Boolean(grant?.lifecycle === 'pending' && !grant.revoked &&
        Math.min(grant.pendingExpiresAt, grant.expiresAt) > now);
}

export function connectionRefreshSeconds(grant, now = Date.now()) {
    return Math.max(1, Math.ceil(Math.min(grant.lifecycle === 'legacy' ? Infinity : CONNECTION_IDLE_SECONDS,
        (grant.expiresAt - now) / 1000)));
}

export const consentDeadline = (durationDays, now = Date.now()) => now + durationDays * DAY_SECONDS * 1000;
