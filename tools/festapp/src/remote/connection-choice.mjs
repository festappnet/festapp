import { CONNECTION_DURATION_DAYS, DEFAULT_CONNECTION_DURATION_DAYS, DAY_SECONDS, connectionActive, connectionDeadline } from '../../../../packages/festapp_contracts/mcp-connection.mjs';
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
    return storage.values('Delegation').filter(g => owns(g, userId, clientId, profileBinding) && connectionActive(g))
        .sort((a, b) => creationTime(b) - creationTime(a) || a.id.localeCompare(b.id))
        .map(g => ({ id: g.id, name: g.name || null, expiresAt: new Date(connectionDeadline(g)).toISOString(),
            access: accessSelection(g.access), permissions: g.permissions ?? [], defaultEligible: g.lifecycle === 'issued' || Boolean(g.clientConnectedAt) }));
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
        check(owns(old, userId, clientId, profileBinding) && connectionActive(old), 'FORBIDDEN');
        inheritedName = old.name;
    } else {
        check(connectionId === undefined, 'FORBIDDEN');
        if (activeConnections(storage, userId, clientId, profileBinding).length) check(Boolean(name), 'FORBIDDEN');
    }
    return { durationDays, name: name || inheritedName || undefined, replaces: mode === 'replace' ? connectionId : undefined };
}

// EventEmitter executes this synchronously inside the provider's error boundary.
export function installConnectionActivation(provider, storage, audit) {
    provider.on('grant.success', ctx => {
        const type = ctx.oidc.params.grant_type;
        if (!['authorization_code', 'refresh_token'].includes(type)) return;
        const id = (type === 'authorization_code' ? ctx.oidc.entities.AuthorizationCode : ctx.oidc.entities.RefreshToken)?.grantId;
        let result;
        try { result = type === 'authorization_code' ? storage.activateConnection(id) : storage.refreshConnection(id); }
        catch (error) {
            if (type === 'authorization_code') {
                try { storage.discardUnissuedTokens(id); } catch { /* Pending remains unusable even if cleanup fails. */ }
            }
            throw error;
        }
        try { audit({ event: type === 'authorization_code' ? 'issued' : 'refreshed', connection: digest(id),
            ...(result.replaces ? { replaced: digest(result.replaces) } : {}) }); } catch { /* Audit cannot undo a committed transaction. */ }
    });
}
