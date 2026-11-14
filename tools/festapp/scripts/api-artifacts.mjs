import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const packageRoot = fileURLToPath(new URL('../', import.meta.url));
export const artifactRoot = path.join(packageRoot, 'contracts/api-v1');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

/** Retrieve the pinned public recovery artifact. Runtime requests never fetch it. */
export async function restoreApiArchive({ destination = artifactRoot } = {}) {
    const pin = JSON.parse(fs.readFileSync(path.join(packageRoot, 'api-contract-archive.json')));
    if (!/^[a-f0-9]{64}$/.test(pin.sha256)) throw new Error('Invalid API archive pin');
    const cache = path.join(os.homedir(), '.cache', 'festapp-api-contracts');
    fs.mkdirSync(cache, { recursive: true });
    const archive = process.env.FESTAPP_API_CONTRACT_ARCHIVE ?? path.join(cache, pin.sha256 + '.tar.gz');
    if (!fs.existsSync(archive)) {
        if (process.env.FESTAPP_API_CONTRACT_ARCHIVE) throw new Error('Explicit API archive is missing');
        const response = await fetch(pin.url, { signal: AbortSignal.timeout(120000) });
        if (!response.ok) throw new Error('API recovery archive unavailable: HTTP ' + response.status);
        const bytes = Buffer.from(await response.arrayBuffer());
        if (hash(bytes) !== pin.sha256) throw new Error('API recovery archive checksum mismatch');
        const temporary = archive + '.' + process.pid;
        fs.writeFileSync(temporary, bytes, { mode: 0o600 });
        fs.renameSync(temporary, archive);
    }
    if (hash(fs.readFileSync(archive)) !== pin.sha256) throw new Error('API recovery archive checksum mismatch');
    const names = execFileSync('tar', ['-tzf', archive], { encoding: 'utf8' }).trim().split('\n');
    const snapshotPath = /^(?:global|regional)-api\/contracts\/[a-f0-9]{64}\/openapi\.json$/;
    if (names.some(name => name !== 'archive-manifest.json' && !snapshotPath.test(name)))
        throw new Error('Unexpected API archive member');
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-api-archive-'));
    try {
        execFileSync('tar', ['-xzf', archive, '-C', temporary]);
        const manifest = JSON.parse(fs.readFileSync(path.join(temporary, 'archive-manifest.json')));
        if (manifest.schemaVersion !== 1 || Object.keys(manifest.files).length !== pin.snapshotCount ||
            names.length !== pin.snapshotCount + 1) throw new Error('Incomplete API recovery archive');
        for (const [relative, entry] of Object.entries(manifest.files)) {
            if (!snapshotPath.test(relative)) throw new Error('Invalid API snapshot path');
            const source = path.join(temporary, relative);
            if (!fs.lstatSync(source).isFile()) throw new Error('API snapshot is not a regular file');
            const bytes = fs.readFileSync(source);
            if (bytes.length !== entry.bytes || hash(bytes) !== entry.sha256) throw new Error('API snapshot checksum mismatch');
            const target = path.join(destination, relative);
            if (fs.existsSync(target)) {
                if (!fs.readFileSync(target).equals(bytes)) throw new Error('Immutable API snapshot collision: ' + relative);
            } else {
                fs.mkdirSync(path.dirname(target), { recursive: true });
                fs.writeFileSync(target, bytes);
            }
        }
        return manifest;
    } finally {
        fs.rmSync(temporary, { recursive: true, force: true });
    }
}
