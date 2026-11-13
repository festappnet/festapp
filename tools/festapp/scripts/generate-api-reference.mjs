import { operationExamples } from './api-examples.mjs';
import { PUBLIC_API_FACADES, API_DATA_PROFILES, API_PROOF_PROFILES, apiProjectionDirectory } from '../src/remote/endpoints.mjs';
import { ARTIFACT_MEDIA_TYPES } from '../src/operations/preview.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { publicCatalog, readiness, jsonSchema, scopesForOperation, problemSchema, artifactInput, errorStatuses, API_JSON_LIMITS, API_COST_BUDGET } from '../src/remote/api-contract.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'))).version;
const sourceSha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
const sourceFiles = fs.readdirSync(path.join(root, 'src'), { recursive: true }).filter(f => f.endsWith('.mjs')).sort();
const contractFiles = ['package.json','pnpm-lock.yaml',...fs.readdirSync(path.join(root,'scripts')).filter(f=>f.endsWith('.mjs')).map(f=>'scripts/'+f), '../../packages/festapp_contracts/mcp-permissions.mjs'];
const inputs = new Set();
const visit = file => {
    if (inputs.has(file)) return;
    inputs.add(file);
    if (!/\.[cm]?js$/.test(file)) return;
    for (const [,relative] of fs.readFileSync(path.join(root,file),'utf8').matchAll(/\b(?:from\s*|import\s*)['"](\.[^'"]+)['"]/g))
        visit(path.relative(root,path.resolve(root,path.dirname(file),relative)));
};
[...sourceFiles.map(f=>'src/'+f),...contractFiles].forEach(visit);
const sourceDigest = hash([...inputs].sort().map(f=>f+'\0'+fs.readFileSync(path.join(root,f))).join('\0'));
export const facades = PUBLIC_API_FACADES;
export function specification(endpoint, dataProfile, proofProfile = 'bearer') {
    const security = scopes => [{oauth:scopes,...(proofProfile === 'dpop' ? {dpop:[]} : {})}];
    const proofParameters = proofProfile === 'dpop' ? [{name:'DPoP',in:'header',required:true,description:'Fresh RFC 9449 proof bound to the access-token key, public htu, htm and ath. Use Authorization: DPoP, never Bearer.',schema:{type:'string',minLength:20,maxLength:8192}}] : [];
    const schemas = {};
    const register = (value, key, io = 'input') => {
        const schema = jsonSchema(value, io);
        const rebase = node => {
            if (!node || typeof node !== 'object') return;
            if (typeof node.$ref === 'string' && node.$ref.startsWith('#/')) node.$ref = '#/components/schemas/' + key + '/' + node.$ref.slice(2);
            for (const child of Object.values(node)) rebase(child);
        };
        rebase(schema);
        schemas[key] = schema;
        return { $ref: '#/components/schemas/' + key };
    };
    const catalog = publicCatalog(dataProfile);
    const supported = catalog.filter(d => readiness(d,dataProfile).supported);
    const errors = Object.fromEntries([...new Set(Object.values(errorStatuses))].sort((a,b)=>a-b).map(status => [status, {
        description: `RFC 9457 problem (${status}). On an uncertain write outcome retain the original commandId and payload.`,
        headers: { 'X-Request-Id': { $ref: '#/components/headers/RequestId' },
            ...(status === 401 || status === 403 ? { 'WWW-Authenticate': { schema: { type: 'string' }, description: 'Resource-specific OAuth challenge.' } } : {}),
            ...(status === 405 ? { Allow: { schema: { type: 'string', const: 'POST' }, description: 'Supported method.' } } : {}),
            ...(status === 429 ? { 'Retry-After': { schema: { type: 'integer', minimum: 1 }, description: 'Actual limiter delay in seconds when provided.' } } : {}) },
        content: { 'application/problem+json': { schema: register(problemSchema, 'Problem'), example: { type: 'https://api.festapp.net/integrations/problems/forbidden', title: 'FORBIDDEN', status: 403, code: 'FORBIDDEN', requestId: '11111111-1111-4111-8111-111111111111', retryable: false, outcome: 'rejected' } } },
    }]));
    // Per-status example status and code must be truthful.
    for (const [status, response] of Object.entries(errors)) {
        const example = response.content['application/problem+json'].example;
        const code = Object.keys(errorStatuses).find(k => errorStatuses[k] === Number(status));
        Object.assign(example, { status: Number(status), code, title: code, type: 'https://api.festapp.net/integrations/problems/' + code.toLowerCase() });
    }
    const paths = Object.fromEntries(supported.map(d => {
        const examples = operationExamples(d, jsonSchema(d.input), jsonSchema(d.output, 'output'));
        return ['/operations/' + d.id, { post: {
        operationId: d.id, summary: d.id, description: d.description + '\n\n' + readiness(d).retry,
        tags: [d.id.split('.')[0]], security: security(scopesForOperation(d.id)), ...(proofParameters.length ? {parameters:proofParameters} : {}),
        'x-cost-class': d.costClass ?? 'ordinary', 'x-domain-read-only': d.domainReadOnly, 'x-data-profile': dataProfile,
        'x-runtime-refinements': 'Runtime validation remains authoritative, including cross-field, scope, preview and aggregate version conditions.',
        requestBody: { required: true, content: { 'application/json': { schema: register(d.input, d.id + '.Input'), example: examples.request } } },
        responses: { 200: { description: 'Validated canonical operation result. Private data is never cached.', headers: { 'X-Request-Id': { $ref: '#/components/headers/RequestId' }, 'Cache-Control': { schema: { type: 'string', const: 'no-store' }, description: 'Private response policy.' } }, content: { 'application/json': { schema: register(d.output, d.id + '.Output', 'output'), example: examples.response } } }, ...errors },
    } }]; }));
    if (dataProfile === 'operator') paths['/artifacts/read'] = { post: { operationId: 'artifacts.read', summary: 'Read an authorized artifact', tags: ['artifacts'], security: security([]), ...(proofParameters.length ? {parameters:proofParameters} : {}),
        description: 'Requires the original operation scopes, active grant, actor and session binding. Artifacts expire after 15 minutes; cache holds at most 8 items/16 MiB and is lost on restart. Recreate missing read exports through their read operation. No arbitrary URL fetching.',
        requestBody: { required: true, content: { 'application/json': { schema: register(artifactInput, 'ArtifactInput') } } },
        responses: { 200: { description: 'Authorized binary content.', headers: { 'X-Request-Id': { $ref: '#/components/headers/RequestId' }, 'Cache-Control': { schema: { type: 'string', const: 'no-store' }, description: 'Private response policy.' } }, content: Object.fromEntries(Object.values(ARTIFACT_MEDIA_TYPES).map(mime => [mime, { schema: { contentMediaType: mime } }])) }, ...errors } } };
    return { openapi: '3.2.1', info: { title: endpoint.brand + ' integrations API', version,
        description: 'Delegated personal OAuth, code + PKCE S256, explicit resource and consent. Not an autonomous organization identity. Read-only POSTs may be repeated; keyset pages are not a snapshot. Decimal money remains a string. Never generate a new commandId after a timeout. Refresh once per connection; atomically persist the rotated token. Reuse, lost refresh responses and grant expiry require reconnect. Consent defaults to 7 days; 30/90/365 days require explicit client policy. Consumed refresh proofs use capped encrypted buckets, never eviction of live evidence. Capacity exhaustion rejects new grants or exchanges. A 30-day idle limit never extends consent. Access tokens live at most 300 seconds. OAuth 2.1 and Idempotency-Key are drafts; no FAPI compliance claim. API data uses no-store. Runtime cross-field refinements remain mandatory.',
        contact: { name: 'Festapp', url: 'https://festapp.net' }, license: { name: 'Proprietary' } },
        servers: [{ url: endpoint.publicBase }],
        'x-profile-policy': endpoint.endpointId === 'regional-api' ? 'fixed' : 'selected',
        'x-proof-profile': proofProfile, 'x-client-proof-policy': 'A registered DPoP-only client must also supply a bound DPoP token and fresh DPoP proof. OAuth alone is never sufficient for that client.',
        'x-oauth-resource': endpoint.resource, 'x-oauth-issuer': endpoint.issuer, 'x-data-profile': dataProfile,
        'x-source-digest': sourceDigest, 'x-body-limit-bytes': API_JSON_LIMITS.bytes, 'x-json-limits': API_JSON_LIMITS, 'x-cost-budget': API_COST_BUDGET,
        'x-readiness': catalog.map(d => ({ operationId: d.id, ...readiness(d,dataProfile) })),
        tags: [...new Set([...supported.map(d => d.id.split('.')[0]), ...(dataProfile === 'operator' ? ['artifacts'] : [])])].map(name => ({ name, description: name + ' operations' })),
        paths, components: { schemas, headers: { RequestId: { description: 'Correlation ID, matching meta.requestId or problem.requestId.', schema: { type: 'string', minLength: 1, maxLength: 128 } } }, securitySchemes: { ...(proofProfile === 'dpop' ? {dpop:{type:'apiKey',in:'header',name:'DPoP',description:'A per-request signed RFC 9449 proof, not an API key. OAuth and this proof are both required. The OAuth access token uses Authorization: DPoP.'}} : {}), oauth: { type: 'oauth2', description:proofProfile === 'dpop' ? 'DPoP-bound opaque token in Authorization: DPoP. OAuth alone is insufficient; the signed DPoP header is also mandatory.' : 'Bearer opaque token in Authorization: Bearer.', flows: { authorizationCode: { authorizationUrl: endpoint.issuer + '/auth', tokenUrl: endpoint.issuer + '/token', scopes: Object.fromEntries([...new Set(supported.flatMap(d=>scopesForOperation(d.id)))].map(s=>[s,s])) } } } } },
    };
}
export function generate({ check = false } = {}) {
    for (const endpoint of facades) for (const profile of API_DATA_PROFILES) for (const proofProfile of API_PROOF_PROFILES) {
        const spec = specification(endpoint, profile, proofProfile);
        const schemaDigest = hash(JSON.stringify(spec.components.schemas));
        const projectionDigest = hash(JSON.stringify(spec));
        spec['x-projection-digest'] = projectionDigest;
        const manifest = { schemaVersion: 1, sourceSha, sourceDigest, apiMajor: 1, contractVersion: version,
            generator: 'festapp-api-v1', redocly: JSON.parse(fs.readFileSync(path.join(root, 'package.json'))).devDependencies['@redocly/cli'],
            endpointId: endpoint.endpointId, publicBase: endpoint.publicBase, resource: endpoint.resource, issuer: endpoint.issuer, dataProfile: profile, proofProfile, schemaDigest, projectionDigest, reference: 'docs/index.html' };
        const dir = path.join(root, 'contracts/api-v1', apiProjectionDirectory(endpoint.endpointId,profile,proofProfile));
        const snapshotDirectory = path.join(root, 'contracts/api-v1', endpoint.endpointId, 'contracts', projectionDigest);
        const snapshot = path.join(snapshotDirectory, 'openapi.json');
        const snapshotText = JSON.stringify(spec, null, 2) + '\n';
        if (fs.existsSync(snapshot)) {
            if (fs.readFileSync(snapshot, 'utf8') !== snapshotText) throw new Error('Immutable API snapshot collision: ' + snapshot);
        } else if (check) throw new Error('Missing immutable API snapshot: ' + snapshot);
        else { fs.mkdirSync(snapshotDirectory, {recursive:true}); fs.writeFileSync(snapshot, snapshotText); }
        for (const [name, value] of [['openapi.json', spec], ['manifest.json', manifest]]) {
            const file = path.join(dir, name), text = JSON.stringify(value, null, 2) + '\n';
            if (check) {
                if (!fs.existsSync(file)) throw new Error('API contract drift: ' + file);
                // A checked-in manifest cannot contain the SHA of its own future
                // commit. Compare source/schema/projection digests here; seal the
                // actual source SHA with api:generate after checkout at release.
                const stored = JSON.parse(fs.readFileSync(file, 'utf8'));
                if (name === 'manifest.json') stored.sourceSha = value.sourceSha;
                if (JSON.stringify(stored, null, 2) + '\n' !== text) throw new Error('API contract drift: ' + file);
            }
            else { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(file, text); }
        }
    }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) { generate({ check: process.argv.includes('--check') }); console.log('API contracts: 8 projections current.'); }
