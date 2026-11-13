import express from 'express';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import { check, safeError } from '../errors.mjs';
import { API_PREFIX, API_DATA_PROFILES, API_PROOF_PROFILES, apiProjectionDirectory } from './endpoints.mjs';
import { publicCatalog, readiness, artifactInput, errorStatuses, API_JSON_LIMITS } from './api-contract.mjs';
const known = new Map(publicCatalog().map(d => [d.id, d]));
export function sendProblem(res, error, { requestId = randomUUID(), endpoint, outcome = 'unknown', authScheme = 'Bearer' } = {}) {
    const safe = error?.code && errorStatuses[error.code] ? error : safeError(error);
    const status = errorStatuses[safe.code] ?? 502;
    if (status === 401 && endpoint) res.set('WWW-Authenticate', `${authScheme === 'DPoP' ? 'DPoP' : 'Bearer'} resource_metadata="${new URL(endpoint.publicBase).origin}/.well-known/oauth-protected-resource/integrations", error="${safe.code === 'INSUFFICIENT_USER_AUTHENTICATION' ? 'insufficient_user_authentication' : 'invalid_token'}"`);
    if (status === 429 && error?.retryAfter) res.set('Retry-After', String(error.retryAfter));
    if (status === 405) res.set('Allow', 'POST');
    return res.status(status).set({ 'X-Request-Id': requestId, 'Cache-Control': 'no-store' }).type('application/problem+json').json({
        type: 'https://api.festapp.net/integrations/problems/' + safe.code.toLowerCase(),
        title: safe.code, status, code: safe.code, requestId, retryable: Boolean(safe.retryable), outcome,
    });
}
export function installApi(app, { config, run }) {
    // Immutable build artifacts are loaded once, never generated per request.
    const docs = new Map();
    for (const endpoint of config.endpoints ?? []) for (const profile of API_DATA_PROFILES) for (const proof of API_PROOF_PROFILES) {
        const directory = new URL(`../../contracts/api-v1/${apiProjectionDirectory(endpoint.endpointId,profile,proof)}/`, import.meta.url);
        const files = new Map();
        for (const name of ['openapi.json', 'manifest.json', 'docs/index.html']) {
            const url = new URL(name, directory);
            if (existsSync(url)) files.set(name, name === 'manifest.json' ? readFileSync(url) : url);
        }
        docs.set(endpoint.endpointId + ':' + profile + ':' + proof, files);
    }
    app.get('/.well-known/oauth-protected-resource/integrations', (req, res) => {
        const endpoint = req.integrationEndpoint;
        check(endpoint, 'INVALID_INGRESS');
        res.set('Access-Control-Allow-Origin', '*').json({ resource: endpoint.resource, authorization_servers: [endpoint.issuer] });
    });
    app.get([API_PREFIX + '/openapi.json', API_PREFIX + '/manifest.json', API_PREFIX + '/docs/', API_PREFIX + '/contracts/:digest/openapi.json', API_PREFIX + '/profiles/:profile/openapi.json', API_PREFIX + '/profiles/:profile/manifest.json', API_PREFIX + '/profiles/:profile/docs/', ...['/proofs/:proof','/profiles/:profile/proofs/:proof'].flatMap(prefix => ['/openapi.json','/manifest.json','/docs/'].map(suffix => API_PREFIX + prefix + suffix))], (req, res) => {
        const endpoint = req.integrationEndpoint;
        if (req.params.digest) {
            if (!/^[a-f0-9]{64}$/.test(req.params.digest)) return sendProblem(res, { code: 'NOT_FOUND_OR_INACCESSIBLE' });
            const snapshot = new URL(`../../contracts/api-v1/${endpoint.endpointId}/contracts/${req.params.digest}/openapi.json`, import.meta.url);
            if (!existsSync(snapshot)) return sendProblem(res, { code: 'NOT_FOUND_OR_INACCESSIBLE' });
            return res.set({ ETag: '"' + req.params.digest + '"', 'Cache-Control': 'public,max-age=31536000,immutable' }).type('json').sendFile(snapshot.pathname);
        }
        const files = docs.get(endpoint?.endpointId + ':' + (req.params.profile ?? 'operator') + ':' + (req.params.proof ?? 'bearer'));
        const name = req.path.endsWith('/docs/') ? 'docs/index.html' : req.path.endsWith('/manifest.json') ? 'manifest.json' : 'openapi.json';
        const bytes = files?.get(name);
        if (!bytes) return sendProblem(res, { code: 'NOT_FOUND_OR_INACCESSIBLE' });
        const manifest = files.get('manifest.json');
        if (req.params.digest && (!manifest || JSON.parse(manifest).projectionDigest !== req.params.digest)) return sendProblem(res, { code: 'NOT_FOUND_OR_INACCESSIBLE' });
        const etag = '"' + (name !== 'manifest.json' ? JSON.parse(manifest).projectionDigest : createHash('sha256').update(bytes).digest('hex')) + '"';
        res.set({ ETag: etag, 'Cache-Control': req.params.digest ? 'public,max-age=31536000,immutable' : 'public,max-age=0,must-revalidate' });
        if (req.headers['if-none-match'] === etag) return res.sendStatus(304);
        if (name.endsWith('.html')) res.set('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; base-uri 'none'; frame-ancestors 'none'");
        if (name !== 'manifest.json') return res.type(name.endsWith('.html') ? 'html' : 'json').sendFile(bytes.pathname);
        res.type('json').send(bytes);
    });
    const parser = express.json({ limit: '48kb', strict: true });
    const route = [API_PREFIX + '/operations/:operation', API_PREFIX + '/artifacts/read'];
    app.post(route, (req, res, next) => {
        if (!req.is('application/json')) return sendProblem(res, { code: 'UNSUPPORTED_MEDIA_TYPE' }, { outcome: 'rejected' });
        parser(req, res, error => {
            if (error) return sendProblem(res, { code: error.type === 'entity.too.large' ? 'BODY_TOO_LARGE' : 'MALFORMED_JSON' }, { outcome: 'rejected' });
            const stack = [[req.body, 0]];
            let nodes = 0;
            while (stack.length) {
                const [value, depth] = stack.pop();
                if (++nodes > API_JSON_LIMITS.nodes || depth > API_JSON_LIMITS.depth)
                    return sendProblem(res, { code: 'BODY_TOO_LARGE' }, { outcome: 'rejected' });
                if (value && typeof value === 'object') for (const child of Object.values(value)) stack.push([child, depth + 1]);
            }
            next();
        });
    }, async (req, res) => {
        const endpoint = req.integrationEndpoint;
        const requestId = randomUUID();
        let accepted = false;
        try {
            check(endpoint, 'INVALID_INGRESS');
            return await run(req, endpoint, 'api', async ({ operations, owner }) => {
                const id = req.params.operation;
                if (!id) {
                    check(!owner.orderSummaryOnly, 'FORBIDDEN');
                    const parsed = artifactInput.safeParse(req.body);
                    check(parsed.success, 'INVALID_INPUT');
                    accepted = true;
                    const result = await operations.readArtifact(parsed.data.uri);
                    const content = result.contents[0];
                    return res.set({ 'X-Request-Id': requestId, 'Cache-Control': 'no-store' }).type(content.mimeType).send(Buffer.from(content.blob, 'base64'));
                }
                check(known.has(id), 'UNKNOWN_OPERATION');
                check(owner.permitsOperation(id), 'FORBIDDEN');
                check(readiness(known.get(id)).supported, 'FAMILY_NOT_READY');
                accepted = true;
                const result = await operations.invoke(id, req.body);
                if (!result.ok) return sendProblem(res, result.error, { requestId: result.meta.requestId, endpoint, authScheme: req.integrationAuthScheme, outcome: known.get(id).domainReadOnly ? 'rejected' : 'unknown' });
                const descriptor = publicCatalog(owner.orderSummaryOnly ? 'order-summary' : 'operator').find(d => d.id === id);
                check(descriptor.output.safeParse(result).success, 'UPSTREAM_CONTRACT_FAILURE');
                return res.set({ 'X-Request-Id': result.meta.requestId, 'Cache-Control': 'no-store' }).json(result);
            });
        } catch (error) { return sendProblem(res, error, { requestId, endpoint, authScheme: req.integrationAuthScheme, outcome: accepted ? 'unknown' : 'rejected' }); }
    });
    app.all(route, (_req, res) => sendProblem(res, { code: 'METHOD_NOT_ALLOWED' }, { outcome: 'rejected' }));
    app.use(API_PREFIX, (_req, res) => sendProblem(res, { code: 'UNKNOWN_OPERATION' }, { outcome: 'rejected' }));
}
