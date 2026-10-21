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

export const SOURCE_REGISTRY = Object.freeze(sourceRegistry.sources.map((source) => Object.freeze(source)));
export const SOURCES = Object.freeze(Object.fromEntries(
  SOURCE_REGISTRY.map((source) => [source.alias, source.project_ref]),
));
export const SOURCE_ALIASES = Object.freeze(SOURCE_REGISTRY.map((source) => source.alias));

export function sourceAliasUsage({ includeCanonical = false } = {}) {
  return [...SOURCE_ALIASES, ...(includeCanonical ? ['canonical'] : [])].join('|');
}

export function parseKeyValueFile(filePath) {
  const values = new Map();
  if (!fs.existsSync(filePath)) return values;
  for (const rawLine of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (value.length >= 2 && ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))) {
      value = value.slice(1, -1);
    }
    values.set(key, value);
  }
  return values;
}

export function accessToken() {
  const local = parseKeyValueFile(path.join(REPOSITORY_ROOT, '.env.local'));
  const token = process.env.SUPABASE_ACCESS_TOKEN || local.get('SUPABASE_ACCESS_TOKEN');
  if (!token) throw new Error('SUPABASE_ACCESS_TOKEN is required');
  return token;
}

export function canonicalDefaultConfig() {
  const config = parseKeyValueFile(path.join(REPOSITORY_ROOT, 'automation/project.conf'));
  const supabaseUrl = config.get('SUPABASE_URL');
  const projectRef = supabaseUrl?.match(/^https:\/\/([a-z0-9]+)\.supabase\.co$/)?.[1];
  const organization = Number(config.get('ORGANIZATION_ID'));
  const occasionLink = config.get('FORCE_OCCASION_LINK') ?? '';
  if (projectRef !== SOURCES.default || !Number.isSafeInteger(organization)) {
    throw new Error('canonical default source does not match automation/project.conf');
  }
  if (occasionLink && !/^[a-zA-Z0-9_-]+$/.test(occasionLink)) {
    throw new Error('configured occasion link is not safe to verify');
  }
  return { projectRef, organization, occasionLink };
}

export async function assertCanonicalDefaultTarget({ token }) {
  const target = canonicalDefaultConfig();
  if (!target.occasionLink) return target;
  const rows = await managementQuery({
    projectRef: target.projectRef,
    token,
    query: `SELECT EXISTS (
      SELECT 1 FROM public.occasions WHERE link = '${target.occasionLink}'
    ) AS occasion_exists`,
  });
  if (!rows[0]?.occasion_exists) {
    throw new Error('configured occasion is absent from canonical default source');
  }
  return target;
}

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

export function buildInventoryManifest({ inventory, inventoryChecksum }) {
  const counts = inventory.exact_row_counts;
  return {
    manifest_version: 1,
    run_id: `inventory-${inventory.source.alias}-${inventory.generated_at.replaceAll(/[^0-9]/g, '')}`,
    phase: 'inventory',
    sources: [{
      alias: inventory.source.alias,
      project_ref: inventory.source.project_ref,
      schema_fingerprint: inventory.schema_fingerprint_sha256,
      snapshot_at: inventory.generated_at,
      journal_position: null,
    }],
    transformation_version: 'inventory-only-2026-08-27.1',
    counts: {
      relations: inventory.catalog.relations.length,
      counted_tables: Object.keys(counts).length,
      rows: Object.values(counts).reduce((sum, value) => sum + value, 0),
      edge_functions: inventory.edge_functions.functions.length,
      storage_objects: Number(inventory.supplemental?.storage?.object_count ?? 0),
      storage_bytes: Number(inventory.supplemental?.storage?.object_bytes ?? 0),
      auth_users: Number(inventory.supplemental?.auth?.users ?? 0),
    },
    checksums: {
      schema: inventory.schema_fingerprint_sha256,
      inventory: inventoryChecksum,
    },
    validation: {
      status: 'blocked',
      unresolved_conflicts: null,
      orphan_foreign_keys: null,
      journal_lag: null,
      notes: inventory.limitations,
    },
    created_at: inventory.generated_at,
    signature: null,
  };
}

export async function managementQuery({ projectRef, token, query }) {
  if (!Object.values(SOURCES).includes(projectRef)) {
    throw new Error(`unapproved source project: ${projectRef}`);
  }
  const normalized = query.replace(/--.*$/gm, '').trimStart().toLowerCase();
  if (!normalized.startsWith('select') && !normalized.startsWith('with')) {
    throw new Error('inventory permits SELECT/CTE statements only');
  }
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${projectRef}/database/query`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!response.ok) {
    const detail = (await response.text()).replaceAll(token, '<redacted>').slice(0, 1200);
    throw new Error(`management query failed for ${projectRef}: HTTP ${response.status}: ${detail}`);
  }
  const body = await response.json();
  return Array.isArray(body) ? body : (body.result ?? body.data ?? []);
}

export function quoteIdentifier(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}
