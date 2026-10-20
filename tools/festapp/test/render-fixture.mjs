import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
const cwd = fileURLToPath(new URL('../../../', import.meta.url));
let rendered;
export async function canonicalPreview() {
    if (!rendered)
        rendered = promisify(execFile)(
            'deno',
            [
                'run',
                '--no-lock',
                '--node-modules-dir=none',
                '--allow-read',
                '--allow-env',
                'tools/festapp/test/canonical_preview.ts',
            ],
            { cwd, maxBuffer: 8 * 1024 * 1024 },
        ).then(({ stdout }) => JSON.parse(stdout));
    return rendered;
}
