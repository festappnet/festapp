// Shared ignored output location; baseline recovery is always deliberate.
import {mkdir, access} from 'node:fs/promises';
import {resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

export async function evidenceDirectory(...required) {
    const folder = pathToFileURL(resolve(process.env.FESTAPP_AUTHORIZATION_EVIDENCE_DIR ??
        fileURLToPath(new URL('../../.codex-artifacts/authorization/run/', import.meta.url))) + '/');
    for (const name of required) {
        try { await access(new URL(name, folder)); }
        catch { throw new Error(`Missing authorization replay input ${name} in ${fileURLToPath(folder)}. Restore paired immutable captures using docs/archive/canonical-authorization-evidence-2026-10-20.md; never derive a historical baseline from current SQL.`); }
    }
    await mkdir(folder, {recursive: true});
    return folder;
}
