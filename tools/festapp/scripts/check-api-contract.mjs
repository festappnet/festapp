import {API_DATA_PROFILES,API_PROOF_PROFILES,apiProjectionDirectory} from '../src/remote/endpoints.mjs';
import { execFileSync } from 'node:child_process';
import { generate, facades } from './generate-api-reference.mjs';
import { publicCatalog, readiness, scopesForOperation, problemSchema } from '../src/remote/api-contract.mjs';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { z } from 'zod';
generate({ check: true });
for (const facade of facades) for (const profile of API_DATA_PROFILES) for (const proofProfile of API_PROOF_PROFILES) {
    const relative = apiProjectionDirectory(facade.endpointId,profile,proofProfile) + '/openapi.json';
    const url = new URL('../contracts/api-v1/' + relative, import.meta.url);
    const spec = JSON.parse(fs.readFileSync(url));
    const catalog = publicCatalog(profile).filter(d=>readiness(d,profile).supported);
    assert.deepEqual(Object.values(spec.paths).map(p=>p.post.operationId).sort(), [...catalog.map(d=>d.id),...(profile === 'operator' ? ['artifacts.read'] : [])].sort());
    for (const descriptor of catalog) {
        const operation = spec.paths['/operations/' + descriptor.id].post;
        assert.deepEqual(operation.security,[{oauth:scopesForOperation(descriptor.id),...(proofProfile==='dpop'?{dpop:[]}:{})}]);
        for (const media of Object.values(operation.requestBody.content)) if (media.example !== undefined) descriptor.input.parse(media.example);
        for (const response of Object.values(operation.responses)) for (const media of Object.values(response.content ?? {})) if (media.example !== undefined) { if (response === operation.responses['200']) descriptor.output.parse(media.example); else problemSchema.parse(media.example); }
    }
    try { execFileSync('pnpm', ['exec','redocly','lint',url.pathname,'--config',new URL('../redocly.yaml',import.meta.url).pathname], { env: { ...process.env, REDOCLY_TELEMETRY:'off' }, stdio: ['ignore','pipe','pipe'] }); } catch (error) { throw new Error(error.stdout?.toString() + error.stderr?.toString()); }
}
console.log('API contracts: schemas, parity, examples and lint passed (8 projections).');
