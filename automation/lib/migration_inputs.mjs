// Logical SQL input catalog for tooling/tests. Installers use only active forwards.
import * as fs from 'node:fs';
import * as promises from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {readHistoricalSql} from './historical_sql.mjs';
export * from 'node:fs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const migrationDirectory = path.join(root, 'supabase/migrations');
const filename = value => value instanceof URL ? fileURLToPath(value) : value;
const coveredPath = value => typeof filename(value) === 'string' && path.dirname(path.resolve(filename(value))) === migrationDirectory;
function recovered(value, options) {
  if (!coveredPath(value)) return null;
  const bytes = Buffer.from(readHistoricalSql('supabase/migrations/' + path.basename(filename(value))));
  const encoding = typeof options === 'string' ? options : options?.encoding;
  return encoding ? bytes.toString(encoding) : bytes;
}
export function readFileSync(value, options) {
  try { return fs.readFileSync(value, options); }
  catch (error) { if (error.code !== 'ENOENT' || !coveredPath(value)) throw error; return recovered(value, options); }
}
export async function readFile(value, options) {
  try { return await promises.readFile(value, options); }
  catch (error) { if (error.code !== 'ENOENT' || !coveredPath(value)) throw error; return recovered(value, options); }
}
function assertWritable(value) {
  if (!coveredPath(value)) return;
  const baseline = JSON.parse(fs.readFileSync(path.join(root, 'supabase/baseline/manifest.json')));
  if (path.basename(filename(value)).slice(0,14) <= baseline.coveredThrough) {
    throw Error('Covered migration is immutable; author a new forward migration');
  }
}
export function writeFileSync(value, data, options) {
  assertWritable(value);
  return fs.writeFileSync(value, data, options);
}
export async function writeFile(value, data, options) {
  assertWritable(value);
  return promises.writeFile(value, data, options);
}
export function copyFileSync(source, destination, flags) {
  if (!fs.existsSync(source) && coveredPath(source)) {
    return fs.writeFileSync(destination, readFileSync(source), {flag: flags & fs.constants.COPYFILE_EXCL ? 'wx' : 'w'});
  }
  return fs.copyFileSync(source, destination, flags);
}
export function readdirSync(value, options) {
  const names = fs.readdirSync(value, options);
  if (path.resolve(filename(value)) !== migrationDirectory) return names;
  if (options === 'buffer' || options?.encoding === 'buffer') throw Error('Historical migration listing requires names');
  const config = JSON.parse(fs.readFileSync(path.join(root, 'supabase/baseline/manifest.json')));
  const history = JSON.parse(fs.readFileSync(path.join(root, config.historicalSources.path)));
  const lower = config.compactedForwardsAfter ?? config.coveredThrough;
  const historical = history.files.filter(entry => entry.path.startsWith('supabase/migrations/') && path.basename(entry.path).slice(0,14) > lower).map(entry => path.basename(entry.path));
  if (options?.withFileTypes) {
    const existing = new Set(names.map(entry => entry.name));
    return [...names, ...historical.filter(name => !existing.has(name)).map(name => ({name,
      parentPath: migrationDirectory, isFile: () => true, isDirectory: () => false,
      isSymbolicLink: () => false}))];
  }
  return [...new Set([...names, ...historical])].sort();
}
export default {...fs, readFileSync, writeFileSync, copyFileSync, readdirSync};
