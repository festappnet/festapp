import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { artifactRoot, restoreApiArchive } from './api-artifacts.mjs';
import { generate, facades } from './generate-api-reference.mjs';
import { API_DATA_PROFILES, API_PROOF_PROFILES, apiProjectionDirectory } from '../src/remote/endpoints.mjs';

const archive = await restoreApiArchive();
generate();
const keep = new Set(Object.keys(archive.files));
for (const endpoint of facades) for (const profile of API_DATA_PROFILES) for (const proof of API_PROOF_PROFILES) {
    const dir = path.join(artifactRoot, apiProjectionDirectory(endpoint.endpointId, profile, proof));
    const bytes = fs.readFileSync(path.join(dir, 'openapi.json'));
    const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json')));
    const relative = endpoint.endpointId + '/contracts/' + manifest.projectionDigest + '/openapi.json';
    keep.add(relative);
    const target = path.join(artifactRoot, relative);
    if (fs.existsSync(target) && !fs.readFileSync(target).equals(bytes)) throw new Error('Immutable current API snapshot collision');
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes);
}
// A build contains the pinned release archive and exactly its current projections.
for (const endpoint of facades) {
    const directory = path.join(artifactRoot, endpoint.endpointId, 'contracts');
    for (const digest of fs.readdirSync(directory)) {
        if (!/^[a-f0-9]{64}$/.test(digest)) throw new Error('Unexpected generated API archive directory');
        if (!keep.has(endpoint.endpointId + '/contracts/' + digest + '/openapi.json'))
            fs.rmSync(path.join(directory, digest), { recursive: true, force: true });
    }
}
if (!process.argv.includes('--contracts-only'))
    execFileSync(process.execPath, [new URL('./build-api-docs.mjs', import.meta.url).pathname], { stdio: 'inherit' });
console.log('API artifacts prepared from the pinned recovery archive and 8 current projections.');
