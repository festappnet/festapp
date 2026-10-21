// Historical source inspection only. Installation and upgrade ownership lives in baseline.py.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function readHistoricalSql(relative) {
  const baseline = JSON.parse(fs.readFileSync(path.join(root, 'supabase/baseline/manifest.json')));
  const bytes = fs.readFileSync(path.join(root, baseline.historicalSources.path));
  if (digest(bytes) !== baseline.historicalSources.sha256) throw new Error('Historical SQL manifest checksum mismatch');
  const history = JSON.parse(bytes);
  const entry = history.files.find(entry => entry.path === relative);
  if (!entry) throw new Error(`Not a covered historical input: ${relative}`);
  const commit = entry.sourceCommit ?? history.sourceCommit;
  if (!/^[0-9a-f]{40}$/.test(commit)) throw new Error('Historical SQL requires a full Git commit');
  const contents = execFileSync('git', ['show', `${commit}:${entry.path}`], { cwd: root, maxBuffer: 16 * 1024 * 1024 });
  if (digest(contents) !== entry.sha256) throw new Error(`Historical SQL checksum mismatch: ${relative}`);
  return contents.toString('utf8');
}
