import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPOSITORY_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../..',
);

const sourceRegistryPath = path.join(
  REPOSITORY_ROOT,
  'automation/hetzner-supabase/merge/source-registry.json',
);
const sourceRegistry = JSON.parse(fs.readFileSync(sourceRegistryPath, 'utf8'));
if (sourceRegistry.version !== 1 || !Array.isArray(sourceRegistry.sources) ||
    sourceRegistry.sources.length === 0) {
  throw new Error('invalid migration source registry');
}
for (const [index, source] of sourceRegistry.sources.entries()) {
  if (!/^[a-z][a-z0-9_]{0,19}$/.test(source.alias ?? '') ||
      !/^[a-z0-9]{20}$/.test(source.project_ref ?? '') ||
      !['canonical-base', 'merge-source'].includes(source.role) ||
      !Array.isArray(source.tenant_ids) || source.tenant_ids.length === 0 ||
      source.tenant_ids.some((tenant) => !/^[a-z][a-z0-9_-]{0,63}$/.test(tenant)) ||
      (index === 0 ? source.alias !== 'default' || source.role !== 'canonical-base' : source.role !== 'merge-source')) {
    throw new Error('invalid migration source registry entry');
  }
}
if (new Set(sourceRegistry.sources.map((source) => source.alias)).size !== sourceRegistry.sources.length ||
    new Set(sourceRegistry.sources.map((source) => source.project_ref)).size !== sourceRegistry.sources.length ||
    sourceRegistry.sources.filter((source) => source.role === 'canonical-base').length !== 1 ||
    new Set(sourceRegistry.sources.flatMap((source) => source.tenant_ids)).size !==
      sourceRegistry.sources.flatMap((source) => source.tenant_ids).length) {
  throw new Error('migration source registry identities must be unique with one canonical base');
}

const SOURCE_REGISTRY = Object.freeze(sourceRegistry.sources.map((source) => Object.freeze(source)));
export const SOURCES = Object.freeze(Object.fromEntries(
  SOURCE_REGISTRY.map((source) => [source.alias, source.project_ref]),
));
export function assertNewEvidencePaths(paths) {
  for (const filePath of paths) {
    if (fs.existsSync(filePath)) throw new Error(`refusing to overwrite existing evidence: ${filePath}`);
  }
}

export function assertPrivateOutput(outputPath) {
  const absolute = path.resolve(outputPath);
  const relative = path.relative(REPOSITORY_ROOT, absolute);
  if (relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..')) {
    throw new Error('production inventory output must be outside the repository');
  }
  return absolute;
}

export function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
