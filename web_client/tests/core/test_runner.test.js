import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, relative} from 'node:path';
import {testBatches, runTests} from '../../scripts/run_tests.mjs';

test('discovers nested web tests once and keeps database fixtures sequential', t => {
    const directory = mkdtempSync(join(tmpdir(), 'festapp-web-runner-'));
    t.after(() => rmSync(directory, {recursive: true, force: true}));
    const files = ['core/a.test.js', 'forms/nested/b.test.js', 'database/c.test.js'];
    for (const file of [...files, 'database/fixture.js']) {
        mkdirSync(join(directory, file, '..'), {recursive: true});
        writeFileSync(join(directory, file), '');
    }
    const batches = testBatches(directory);
    assert.deepEqual(batches.map(batch => batch.concurrency), [4, 1]);
    assert.deepEqual(batches[0].files.map(file => relative(directory, file)), files.slice(0, 2));
    assert.deepEqual(batches[1].files.map(file => relative(directory, file)), files.slice(2));
});

test('both batches run after either fails and preserve nonzero exit status', () => {
    const batches = [{concurrency: 4, files: ['ui.test.js']}, {concurrency: 1, files: ['db.test.js']}];
    for (const statuses of [[0, 0], [1, 0], [0, 1], [null, 0]]) {
        const calls = [];
        assert.equal(runTests(batches, (binary, args) => {
            assert.equal(binary, process.execPath);
            calls.push(args);
            return {status: statuses[calls.length - 1]};
        }), statuses.every(status => status === 0) ? 0 : 1);
        assert.deepEqual(calls, [
            ['--test', '--test-concurrency=4', 'ui.test.js'],
            ['--test', '--test-concurrency=1', 'db.test.js'],
        ]);
    }
});

test('empty discovery fails instead of reporting a passing suite', () => {
    assert.equal(runTests([{concurrency: 4, files: []}]), 1);
});
