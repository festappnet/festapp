import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { restoreApiArchive, packageRoot } from '../scripts/api-artifacts.mjs';

test('the pinned archive independently restores every published baseline byte', async () => {
    const destination = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-api-restore-test-'));
    try {
        const manifest = await restoreApiArchive({ destination });
        const baseline = JSON.parse(fs.readFileSync(path.join(packageRoot, 'api-release-baseline.json')));
        assert.equal(baseline.state, 'released');
        for (const contract of baseline.contracts) {
            const bytes = fs.readFileSync(path.join(destination, contract.snapshot));
            assert.equal(bytes.length, manifest.files[contract.snapshot].bytes);
            assert(JSON.parse(bytes).openapi);
        }
        const contract = baseline.contracts[0];
        fs.writeFileSync(path.join(destination, contract.snapshot), '{}');
        await assert.rejects(restoreApiArchive({ destination }), /Immutable API snapshot collision/);
    } finally {
        fs.rmSync(destination, { recursive: true, force: true });
    }
});

test('a missing explicit offline archive cannot silently bypass compatibility', async () => {
    const previous = process.env.FESTAPP_API_CONTRACT_ARCHIVE;
    process.env.FESTAPP_API_CONTRACT_ARCHIVE = path.join(os.tmpdir(), 'missing-api-archive-' + process.pid);
    try {
        await assert.rejects(restoreApiArchive(), /Explicit API archive is missing/);
    } finally {
        if (previous === undefined) delete process.env.FESTAPP_API_CONTRACT_ARCHIVE;
        else process.env.FESTAPP_API_CONTRACT_ARCHIVE = previous;
    }
});
