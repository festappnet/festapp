import { check } from '../errors.mjs';

export const STRONG_AUTHENTICATION_ACR = 'urn:festapp:aal2';
export const STEP_UP_MAX_AGE_SECONDS = 300;

/** Call only after this exact access token has been accepted by GoTrue getUser.
 * JWT iat is deliberately not authentication time: refresh must not renew MFA.
 * User metadata, request bodies and the downstream OAuth/DPoP token are not
 * sources of authentication assurance.
 */
export function verifiedSessionAssurance(accessToken, user, backendOrigin) {
    try {
        const payload = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url'));
        const now = Math.floor(Date.now() / 1000);
        // Canonical Festapp GoTrue config pins JWT issuer to the backend
        // origin; /auth/v1 is its REST route, not the token issuer.
        const issuer = new URL(backendOrigin).origin;
        if (payload.sub !== user.id || payload.iss !== issuer || payload.role !== 'authenticated' ||
            ![payload.aud].flat().includes('authenticated') || payload.aal !== 'aal2' ||
            !/^[a-f0-9-]{36}$/i.test(payload.session_id ?? '') ||
            !Number.isFinite(payload.exp) || payload.exp <= now ||
            !user.factors?.some(f => f.status === 'verified' && ['totp', 'webauthn'].includes(f.factor_type))) return null;
        const times = (Array.isArray(payload.amr) ? payload.amr : [])
            .filter(a => ['totp', 'webauthn'].includes(a.method) && Number.isInteger(a.timestamp) && a.timestamp > 0 && a.timestamp <= now + 30)
            .map(a => a.timestamp);
        if (!times.length) return null;
        return Object.freeze({ acr: STRONG_AUTHENTICATION_ACR, authTime: Math.max(...times),
            userId: user.id, sessionId: payload.session_id, issuer });
    } catch { return null; }
}

export function requireFreshStrongAuthentication(assurance, userId) {
    const now = Math.floor(Date.now() / 1000);
    check(assurance?.acr === STRONG_AUTHENTICATION_ACR && assurance.userId === userId &&
        Number.isInteger(assurance.authTime) && assurance.authTime <= now + 30 &&
        now - assurance.authTime <= STEP_UP_MAX_AGE_SECONDS, 'INSUFFICIENT_USER_AUTHENTICATION');
}
