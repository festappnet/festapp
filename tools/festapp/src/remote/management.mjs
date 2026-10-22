import express from 'express';
import { timingSafeEqual, randomUUID } from 'node:crypto';
import { check } from '../errors.mjs';
import { digest } from '../context/profile.mjs';
import { accessSelection } from '../operations/access.mjs';
import { ORDER_SCOPES } from './config.mjs';

/** Account management uses a transient ordinary-user proof, never a consent
 * request, a new backend session, or a second grant store. */
export function tenantConnections(app, { config, storage, brokerSecret, owner, audit }) {
    if (!config.tenantOrigin) return;
    app.post('/tenant-connections', express.json({ limit: '12kb' }), async (req, res) => {
        const secret = req.headers['x-festapp-mcp-broker'];
        check(typeof secret === 'string' && typeof brokerSecret === 'string' &&
            timingSafeEqual(Buffer.from(digest(secret)), Buffer.from(digest(brokerSecret))), 'FORBIDDEN');
        const body = req.body;
        const fields = ['operation', 'accessToken', 'tenantId', 'tenantOrigin', 'organizationId', ...(body?.operation === 'revoke' ? ['connectionId'] : [])];
        check(body && Object.keys(body).every(k => fields.includes(k)), 'FORBIDDEN');
        check(body?.tenantId === config.profile.tenantId && body.organizationId === config.profile.organizationId &&
            body.tenantOrigin === config.tenantOrigin && ['list', 'revoke'].includes(body.operation), 'FORBIDDEN');
        const owns = (grant, userId) => grant?.userId === userId && grant.profileBinding === config.profile.binding;
        return owner(`management:${randomUUID()}`).withAccessToken(body.accessToken, async (_client, { userId }) => {
            if (body.operation === 'list') {
                const connections = storage.values('Delegation')
                    .filter(g => owns(g, userId) && !g.revoked && g.expiresAt > Date.now())
                    .sort((a, b) => b.expiresAt - a.expiresAt || a.id.localeCompare(b.id))
                    .map(g => ({ id: g.id, client: config.clients.find(c => c.id === g.clientId)?.name ?? g.clientId,
                        expiresAt: new Date(g.expiresAt).toISOString(), access: accessSelection(g.access),
                        permissions: ORDER_SCOPES.filter(p => g.permissions?.includes(p)) }));
                return res.json({ connections });
            }
            check(typeof body.connectionId === 'string' && /^[A-Za-z0-9_-]{1,200}$/.test(body.connectionId), 'FORBIDDEN');
            const grant = storage.get('Delegation', body.connectionId);
            check(owns(grant, userId), 'FORBIDDEN');
            storage.revoke(grant.id);
            audit({ event: 'revoked', connection: digest(grant.id) });
            return res.json({ connectionId: grant.id, revoked: true });
        });
    });
}
