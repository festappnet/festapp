import { check } from '../errors.mjs';
import { STRONG_AUTHENTICATION_ACR, STEP_UP_MAX_AGE_SECONDS, requireFreshStrongAuthentication } from './assurance.mjs';

const privileged = new Set([
    'banks.save', 'banks.link', 'banks.user', 'banks.sync', 'banks.suspend', 'banks.resume',
    'cards.pause', 'cards.disconnect', 'cards.refund.decide', 'payments.record',
    'history.delete', 'orders.delete', 'orders.mark_paid', 'occasions.delete',
    'occasions.setup.finalize', 'lifecycle.resume', 'units.delete',
    'units.people.create', 'units.people.roles', 'units.people.revoke', 'profiles.roles', 'profiles.delete',
]);
export function operationAuthentication(operation) {
    return privileged.has(operation) ? Object.freeze({ proofProfile: 'dpop', requirePar: true,
        acr: STRONG_AUTHENTICATION_ACR, maxAgeSeconds: STEP_UP_MAX_AGE_SECONDS }) : null;
}
export function authorizeApiAuthentication(operation, { token, client, userId, authentication }) {
    if (!operationAuthentication(operation)) return;
    check(token.jkt && client.proofProfile === 'dpop' && client.requirePar === true,
        'INSUFFICIENT_USER_AUTHENTICATION');
    requireFreshStrongAuthentication(authentication, userId);
}
