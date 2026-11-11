import {readdirSync} from 'node:fs';
import {join, relative, resolve, sep} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

export function testBatches(directory = join(root, 'tests')) {
    const files = readdirSync(directory, {recursive: true, withFileTypes: true})
        .filter(entry => entry.isFile() && entry.name.endsWith('.test.js'))
        .map(entry => join(entry.parentPath, entry.name)).sort();
    const database = file => relative(directory, file).split(sep)[0] === 'database';
    return [
        {concurrency: 4, files: files.filter(file => !database(file))},
        // These fixtures may share a disposable backend. Preserve their ordering.
        {concurrency: 1, files: files.filter(database)},
    ];
}

export function runTests(batches, run = spawnSync) {
    if (!batches.some(batch => batch.files.length)) {
        console.error('No web tests discovered.');
        return 1;
    }
    let failed = false;
    for (const {concurrency, files} of batches) {
        if (!files.length) continue;
        const result = run(process.execPath,
            ['--test', `--test-concurrency=${concurrency}`, ...files],
            {cwd: root, stdio: 'inherit'});
        if (result.error) console.error(result.error.message);
        failed ||= result.status !== 0;
    }
    return Number(failed);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    process.exitCode = runTests(testBatches());
}
