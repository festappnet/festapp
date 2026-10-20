#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {
  SOURCES,
  sourceAliasUsage,
  accessToken,
  assertCanonicalDefaultTarget,
  assertNewEvidencePaths,
  assertPrivateOutput,
  buildInventoryManifest,
  managementQuery,
  quoteIdentifier,
  sha256,
  stableJson,
} from './lib.mjs';

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith('--') || value === undefined) {
      throw new Error(`usage: inventory.mjs --source ${sourceAliasUsage()} --output /private/path/file.json`);
    }
    result[name.slice(2)] = value;
  }
  if (!SOURCES[result.source] || !result.output) {
    throw new Error(`both --source ${sourceAliasUsage()} and --output are required`);
  }
  return result;
}

const catalogSql = String.raw`
WITH relations AS (
  SELECT n.nspname AS schema_name, c.relname AS table_name,
         c.relkind, c.relrowsecurity, c.relforcerowsecurity,
         pg_total_relation_size(c.oid)::bigint AS total_bytes,
         COALESCE(s.n_live_tup, 0)::bigint AS estimated_rows
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
  WHERE c.relkind IN ('r', 'p', 'v', 'm')
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
), columns AS (
  SELECT table_schema AS schema_name, table_name, ordinal_position,
         column_name, data_type, udt_schema, udt_name, is_nullable,
         column_default, is_identity, identity_generation, is_generated
  FROM information_schema.columns
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
), constraints AS (
  SELECT n.nspname AS schema_name, c.relname AS table_name,
         con.conname AS constraint_name, con.contype AS constraint_type,
         pg_get_constraintdef(con.oid, true) AS definition
  FROM pg_constraint con
  JOIN pg_class c ON c.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
), routines AS (
  SELECT n.nspname AS schema_name, p.proname AS routine_name,
         pg_get_function_identity_arguments(p.oid) AS identity_arguments,
         p.prosecdef AS security_definer,
         p.provolatile AS volatility,
         md5(pg_get_functiondef(p.oid)) AS definition_md5
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND p.prokind = 'f'
), policies AS (
  SELECT schemaname AS schema_name, tablename AS table_name,
         policyname AS policy_name, permissive, roles, cmd,
         md5(COALESCE(qual, '') || '|' || COALESCE(with_check, '')) AS expression_md5
  FROM pg_policies
), grants AS (
  SELECT grantee, table_schema AS schema_name, table_name, privilege_type
  FROM information_schema.role_table_grants
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
), extensions AS (
  SELECT e.extname AS name, e.extversion AS version, n.nspname AS schema_name
  FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
), publications AS (
  SELECT pubname AS name, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
  FROM pg_publication
), roles AS (
  SELECT rolname AS name, rolsuper, rolinherit, rolcreaterole, rolcreatedb,
         rolcanlogin, rolreplication, rolbypassrls
  FROM pg_roles
), collations AS (
  SELECT n.nspname AS schema_name, c.collname AS name,
         c.collprovider::text AS provider, c.collversion AS version
  FROM pg_collation c JOIN pg_namespace n ON n.oid = c.collnamespace
  WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
)
SELECT jsonb_build_object(
  'postgres_version', current_setting('server_version'),
  'postgres_version_num', current_setting('server_version_num'),
  'database_name', current_database(),
  'database_bytes', pg_database_size(current_database()),
  'wal_level', current_setting('wal_level'),
  'max_connections', current_setting('max_connections'),
  'active_connections', (SELECT count(*) FROM pg_stat_activity),
  'peak_connections_available', false,
  'relations', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, table_name), '[]') FROM relations x),
  'columns', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, table_name, ordinal_position), '[]') FROM columns x),
  'constraints', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, table_name, constraint_name), '[]') FROM constraints x),
  'routines', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, routine_name, identity_arguments), '[]') FROM routines x),
  'policies', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, table_name, policy_name), '[]') FROM policies x),
  'grants', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, table_name, grantee, privilege_type), '[]') FROM grants x),
  'extensions', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY name), '[]') FROM extensions x),
  'publications', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY name), '[]') FROM publications x),
  'roles', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY name), '[]') FROM roles x),
  'collations', (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY schema_name, name), '[]') FROM collations x),
  'capabilities', jsonb_build_object(
    'cron_schema', to_regnamespace('cron') IS NOT NULL,
    'vault_schema', to_regnamespace('vault') IS NOT NULL,
    'auth_users', to_regclass('auth.users') IS NOT NULL,
    'auth_identities', to_regclass('auth.identities') IS NOT NULL,
    'auth_mfa_factors', to_regclass('auth.mfa_factors') IS NOT NULL,
    'storage_objects', to_regclass('storage.objects') IS NOT NULL,
    'storage_buckets', to_regclass('storage.buckets') IS NOT NULL
  )
) AS inventory`;

async function exactCounts({ projectRef, token, relations }) {
  const countable = relations.filter((relation) => relation.relkind === 'r' || relation.relkind === 'p');
  const counts = {};
  for (const relation of countable) {
    const qualified = `${quoteIdentifier(relation.schema_name)}.${quoteIdentifier(relation.table_name)}`;
    const rows = await managementQuery({
      projectRef,
      token,
      query: `SELECT count(*)::bigint AS row_count FROM ${qualified}`,
    });
    counts[`${relation.schema_name}.${relation.table_name}`] = Number(rows[0]?.row_count ?? 0);
  }
  return counts;
}

async function edgeFunctionInventory({ projectRef, token }) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${projectRef}/functions`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return { available: false, functions: [] };
  if (!response.ok) throw new Error(`edge function inventory failed: HTTP ${response.status}`);
  const values = await response.json();
  return {
    available: true,
    functions: values.map((item) => ({
      slug: item.slug ?? item.name,
      status: item.status ?? null,
      verify_jwt: item.verify_jwt ?? null,
      version: item.version ?? null,
    })).sort((left, right) => left.slug.localeCompare(right.slug)),
  };
}

async function singleValueQuery({ projectRef, token, query, field }) {
  const rows = await managementQuery({ projectRef, token, query });
  return rows[0]?.[field] ?? null;
}

async function supplementalInventory({ projectRef, token, capabilities }) {
  const limitations = [];
  let wal = null;
  try {
    wal = await singleValueQuery({
      projectRef,
      token,
      field: 'wal',
      query: `SELECT jsonb_build_object(
        'bytes', COALESCE((SELECT sum(size) FROM pg_ls_waldir()), 0),
        'current_lsn', pg_current_wal_lsn()::text,
        'retained_slots_bytes', COALESCE((SELECT sum(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) FROM pg_replication_slots), 0)
      ) AS wal`,
    });
  } catch (error) {
    limitations.push(`WAL inventory unavailable: ${error.message}`);
  }

  let storage = null;
  if (capabilities.storage_objects && capabilities.storage_buckets) {
    storage = await singleValueQuery({
      projectRef,
      token,
      field: 'storage',
      query: `SELECT jsonb_build_object(
        'bucket_count', (SELECT count(*) FROM storage.buckets),
        'object_count', (SELECT count(*) FROM storage.objects),
        'object_bytes', (SELECT COALESCE(sum(CASE WHEN metadata->>'size' ~ '^[0-9]+$' THEN (metadata->>'size')::bigint ELSE 0 END), 0) FROM storage.objects),
        'objects_without_size', (SELECT count(*) FROM storage.objects WHERE metadata->>'size' IS NULL OR metadata->>'size' !~ '^[0-9]+$')
      ) AS storage`,
    });
  } else {
    limitations.push('Storage catalog is unavailable');
  }

  let auth = null;
  if (capabilities.auth_users) {
    const users = await singleValueQuery({
      projectRef,
      token,
      field: 'users',
      query: `SELECT jsonb_build_object(
        'users', count(*),
        'verified_email_users', count(*) FILTER (WHERE email_confirmed_at IS NOT NULL),
        'phone_users', count(*) FILTER (WHERE phone IS NOT NULL)
      ) AS users FROM auth.users`,
    });
    let providers = [];
    if (capabilities.auth_identities) {
      providers = await managementQuery({
        projectRef,
        token,
        query: `SELECT provider, count(*)::bigint AS identities
          FROM auth.identities GROUP BY provider ORDER BY provider`,
      });
    }
    let mfa = [];
    if (capabilities.auth_mfa_factors) {
      mfa = await managementQuery({
        projectRef,
        token,
        query: `SELECT factor_type, status, count(*)::bigint AS factors
          FROM auth.mfa_factors GROUP BY factor_type, status ORDER BY factor_type, status`,
      });
    }
    auth = { ...users, providers, mfa };
  } else {
    limitations.push('Auth user catalog is unavailable');
  }

  let cron = null;
  if (capabilities.cron_schema) {
    cron = await singleValueQuery({
      projectRef,
      token,
      field: 'cron',
      query: `SELECT jsonb_build_object(
        'job_count', count(*),
        'jobs', COALESCE(jsonb_agg(jsonb_build_object(
          'jobid', jobid, 'schedule', schedule, 'active', active,
          'database', database, 'username', username,
          'command_md5', md5(command)
        ) ORDER BY jobid), '[]'::jsonb)
      ) AS cron FROM cron.job`,
    });
  }

  let vault = null;
  if (capabilities.vault_schema) {
    try {
      vault = await singleValueQuery({
        projectRef,
        token,
        field: 'vault',
        query: `SELECT jsonb_build_object('secret_count', count(*)) AS vault FROM vault.secrets`,
      });
    } catch (error) {
      limitations.push(`Vault count unavailable: ${error.message}`);
    }
  }
  return { wal, storage, auth, cron, vault, limitations };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const output = assertPrivateOutput(args.output);
  const projectRef = SOURCES[args.source];
  const token = accessToken();
  if (args.source === 'default') await assertCanonicalDefaultTarget({ token });
  const rows = await managementQuery({ projectRef, token, query: catalogSql });
  const catalog = rows[0]?.inventory;
  if (!catalog || !Array.isArray(catalog.relations)) {
    throw new Error('unexpected catalog inventory response');
  }
  const counts = await exactCounts({ projectRef, token, relations: catalog.relations });
  const edgeFunctions = await edgeFunctionInventory({ projectRef, token });
  const supplemental = await supplementalInventory({
    projectRef,
    token,
    capabilities: catalog.capabilities,
  });
  const generatedAt = new Date().toISOString();
  const fingerprintInput = {
    postgres_version_num: catalog.postgres_version_num,
    relations: catalog.relations.map(({ total_bytes, estimated_rows, ...value }) => value),
    columns: catalog.columns,
    constraints: catalog.constraints,
    routines: catalog.routines,
    policies: catalog.policies,
    grants: catalog.grants,
    extensions: catalog.extensions,
    publications: catalog.publications,
    roles: catalog.roles,
    collations: catalog.collations,
  };
  const inventory = {
    manifest_version: 1,
    source: { alias: args.source, project_ref: projectRef },
    generated_at: generatedAt,
    access_mode: 'management-api-read-only',
    schema_fingerprint_sha256: sha256(stableJson(fingerprintInput)),
    catalog,
    exact_row_counts: counts,
    edge_functions: edgeFunctions,
    supplemental,
    limitations: [
      'peak connection history and growth require provider metrics export',
      'Auth identity, natural-key and Storage key/hash collisions require a separately approved private evidence pass',
      'no row payloads or production identities are included',
      ...supplemental.limitations,
    ],
  };
  const inventoryChecksum = sha256(stableJson(inventory));
  const manifest = buildInventoryManifest({ inventory, inventoryChecksum });
  const manifestOutput = output.replace(/\.json$/i, '') + '.manifest.json';
  assertNewEvidencePaths([output, manifestOutput]);
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  fs.writeFileSync(output, `${JSON.stringify(inventory, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  fs.writeFileSync(manifestOutput, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`inventory ${args.source}: ${catalog.postgres_version}, ${catalog.relations.length} relations, ${inventory.schema_fingerprint_sha256}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
