import { CONNECTION_DURATION_DAYS, DEFAULT_CONNECTION_DURATION_DAYS, DAY_SECONDS } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
import { digest } from '../context/profile.mjs';
import { z } from 'zod';
import { check } from '../errors.mjs';
import { accessSelection } from '../operations/access.mjs';

export const connectionChoice = z.strictObject({
    mode: z.enum(['replace', 'new']),
    durationDays: z.union(CONNECTION_DURATION_DAYS.map(days => z.literal(days))).default(DEFAULT_CONNECTION_DURATION_DAYS),
    connectionId: z.string().regex(/^[A-Za-z0-9_-]{1,200}$/).optional(),
    name: z.string().trim().max(80).refine(s => !/[\u0000-\u001f\u007f]/u.test(s)).optional(),
});
const owns = (g, userId, clientId, profileBinding) => g && g.userId === userId &&
    g.clientId === clientId && g.profileBinding === profileBinding;
// Only legacy records lack createdAt; their historical duration was seven days.
const creationTime = grant => grant.createdAt ??
    grant.expiresAt - (grant.durationDays ?? DEFAULT_CONNECTION_DURATION_DAYS) * DAY_SECONDS * 1000;
export function activeConnections(storage, userId, clientId, profileBinding) {
    return storage.values('Delegation').filter(g => owns(g, userId, clientId, profileBinding) && !g.revoked && g.expiresAt > Date.now())
        .sort((a, b) => creationTime(b) - creationTime(a) || a.id.localeCompare(b.id))
        .map(g => ({ id: g.id, name: g.name || null, expiresAt: new Date(g.expiresAt).toISOString(),
            access: accessSelection(g.access), permissions: g.permissions ?? [] }));
}
export function verifyConnectionChoice(raw, storage, userId, clientId, profileBinding) {
    if (raw === undefined) return { durationDays: DEFAULT_CONNECTION_DURATION_DAYS }; // Legacy requests always create an independent connection.
    const parsed = connectionChoice.safeParse(raw);
    check(parsed.success, 'FORBIDDEN');
    const { mode, connectionId, name, durationDays } = parsed.data;
    let inheritedName;
    if (mode === 'replace') {
        check(typeof connectionId === 'string', 'FORBIDDEN');
        const old = storage.get('Delegation', connectionId);
        check(owns(old, userId, clientId, profileBinding) && !old.revoked && old.expiresAt > Date.now(), 'FORBIDDEN');
        inheritedName = old.name;
    } else {
        check(connectionId === undefined, 'FORBIDDEN');
        if (activeConnections(storage, userId, clientId, profileBinding).length) check(Boolean(name), 'FORBIDDEN');
    }
    return { durationDays, name: name || inheritedName || undefined, replaces: mode === 'replace' ? connectionId : undefined };
}

// EventEmitter listeners must be synchronous and contain every exception: a
// cleanup failure cannot turn already-issued tokens into a failed token response.
export function installConnectionReplacement(provider, storage, audit) {
    provider.on('grant.success', ctx => {
        try {
            if (ctx.oidc.params.grant_type !== 'authorization_code') return;
            const id = ctx.oidc.entities.AuthorizationCode?.grantId;
            const grant = id && storage.get('Delegation', id);
            if (!grant?.replaces || grant.revoked || grant.expiresAt <= Date.now()) return;
            const old = storage.get('Delegation', grant.replaces);
            check(owns(old, grant.userId, grant.clientId, grant.profileBinding), 'FORBIDDEN');
            storage.revoke(old.id);
            audit({ event: 'revoked', connection: digest(old.id) });
        } catch { try { audit({ event: 'replacement_failed' }); } catch { /* Never break issuance. */ } }
    });
}
