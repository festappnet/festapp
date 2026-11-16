import { jwtVerify, importJWK, calculateJwkThumbprint } from 'jose';
import { createHash } from 'node:crypto';
import { check, OperationError } from '../errors.mjs';

const hash = value => createHash('sha256').update(value).digest('base64url');
/** Bounded replay evidence is retained for the entire acceptance window. At
 * capacity reject new proofs; never evict an unexpired proof to admit work. */
export function createProofVerifier({ capacity = 4096, now = Date.now, storage } = {}) {
    const replay = new Map();
    return async (req, token, credential, endpoint, client) => {
        if (!token.jkt) {
            check(client.proofProfile !== 'dpop' && !token.isSenderConstrained?.() &&
                !token['x5t#S256'] && req.headers.authorization.startsWith('Bearer ') && !req.headers.dpop, 'AUTHENTICATION_REQUIRED');
            return;
        }
        check(req.headers.authorization.startsWith('DPoP ') && client.proofProfile === 'dpop', 'AUTHENTICATION_REQUIRED');
        const proof = req.headers.dpop;
        check(typeof proof === 'string' && proof.length <= 8192, 'AUTHENTICATION_REQUIRED');
        let result;
        try {
            result = await jwtVerify(proof, async header => {
                check(['ES256', 'EdDSA', 'Ed25519'].includes(header.alg) && header.jwk &&
                    !['d', 'k', 'p', 'q'].some(k => k in header.jwk), 'AUTHENTICATION_REQUIRED');
                return importJWK(header.jwk, header.alg);
            }, { typ: 'dpop+jwt', algorithms: ['ES256', 'EdDSA', 'Ed25519'], currentDate: new Date(now()) });
        } catch { check(false, 'AUTHENTICATION_REQUIRED'); }
        const { payload: p, protectedHeader: h } = result;
        const expected = new URL(endpoint.publicBase).origin + req.path;
        let actual;
        try { actual = new URL(p.htu); actual.hash = ''; actual.search = ''; } catch { check(false, 'AUTHENTICATION_REQUIRED'); }
        check(p.htm === req.method && actual.href === expected && p.ath === hash(credential) &&
            Number.isInteger(p.iat) && Math.abs(now() / 1000 - p.iat) <= 60 &&
            typeof p.jti === 'string' && p.jti.length > 0 && p.jti.length <= 200 && p.nonce === undefined &&
            await calculateJwkThumbprint(h.jwk) === token.jkt, 'AUTHENTICATION_REQUIRED');
        const time = now();
        for (const [key, expiry] of replay) if (expiry < time) replay.delete(key);
        const key = hash(JSON.stringify([token.jkt, p.jti]));
        check(!replay.has(key) && !storage?.get('DPoPResourceReplay', key), 'AUTHENTICATION_REQUIRED');
        if (replay.size >= capacity || (storage?.stats().byModel.DPoPResourceReplay ?? 0) >= capacity) {
            const error = new OperationError('TEMPORARILY_LIMITED', true);
            throw error;
        }
        storage?.putUntil('DPoPResourceReplay', key, { seen: true }, (p.iat + 60) * 1000);
        // A proof 60s in the future remains acceptable for 120s from receipt.
        replay.set(key, (p.iat + 60) * 1000);
    };
}
