// Exact fixture bytes shared by historical SQL recovery and regression readers.
import {readFileSync, existsSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
const directory = new URL('../historical-inputs/', import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json', directory)));
if (manifest.schemaVersion !== 1) throw new Error('Unsupported historical input manifest');
export function readSource(revision, relative) {
  const sha = manifest.snapshots[revision]?.[relative];
  if (!/^[0-9a-f]{64}$/.test(sha ?? '')) throw new Error(`Unregistered historical input: ${revision}:${relative}`);
  const blob = new URL(`objects/${sha}`, directory);
  const bytes = existsSync(blob) ? readFileSync(blob) : gunzipSync(readFileSync(new URL(`objects/${sha}.gz`, directory)));
  if (createHash('sha256').update(bytes).digest('hex') !== sha) throw new Error(`Historical input checksum mismatch: ${relative}`);
  return bytes;
}
