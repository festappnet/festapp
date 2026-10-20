#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import {
  REPOSITORY_ROOT,
  SOURCES,
  accessToken,
  assertNewEvidencePaths,
  assertPrivateOutput,
  managementQuery,
  sha256,
  stableJson,
} from './lib.mjs';
import {
  buildTenantConfigInventory,
  discoverProductionTenantConfigs,
} from './tenant-config-inventory.mjs';

const POLICY_PATH = path.join(
  REPOSITORY_ROOT,
  'automation/hetzner-supabase/merge/write-authority-policy.json',
);
const RPC_LITERAL = /['"]([a-z][a-z0-9_]+_client_sync_v1)['"]/g;

export function loadWriteAuthorityPolicy(filePath = POLICY_PATH) {
  const policy = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (policy.policy_version !== 1 || policy.source_project !== 'a') {
    throw new Error('unsupported write-authority policy');
  }
  if (!Array.isArray(policy.legacy_adapters) || policy.legacy_adapters.length === 0) {
    throw new Error('write-authority policy has no legacy adapters');
  }
  return policy;
}

export function auditLegacyAdapters(
  policy,
  root = REPOSITORY_ROOT,
) {
  const rpcNames = new Set();
  const entries = policy.legacy_adapters.map((entry) => {
    const adapterPath = path.join(root, entry.path);
    if (!fs.existsSync(adapterPath)) {
      return { ...entry, status: 'missing-adapter', rpc_names: [] };
    }
    const adapter = fs.readFileSync(adapterPath, 'utf8');
    const hasSelectionContract = adapter.includes(policy.selection_contract);
    const moduleProblems = [];
    const entryRpcNames = new Set();
    for (const relativeModule of entry.command_modules) {
      const modulePath = path.join(root, relativeModule);
      if (!fs.existsSync(modulePath)) {
        moduleProblems.push(`missing:${relativeModule}`);
        continue;
      }
      const module = fs.readFileSync(modulePath, 'utf8');
      for (const match of module.matchAll(RPC_LITERAL)) {
        entryRpcNames.add(match[1]);
        rpcNames.add(match[1]);
      }
      if (!module.includes('ClientCommandTransport')) {
        moduleProblems.push(`unbound-transport:${relativeModule}`);
      }
    }
    const status = hasSelectionContract && moduleProblems.length === 0 && entryRpcNames.size > 0
      ? 'rpc-seam-detected-legacy-fallback-remains'
      : 'blocked';
    return {
      ...entry,
      selection_contract_present: hasSelectionContract,
      module_problems: moduleProblems,
      rpc_names: [...entryRpcNames].sort(),
      status,
    };
  });
  return {
    entries,
    rpc_names: [...rpcNames].sort(),
    seam_detected_adapters: entries.filter((entry) =>
      entry.status === 'rpc-seam-detected-legacy-fallback-remains').length,
    coverage_proof: 'partial-static-evidence-not-operation-completeness',
  };
}

function sqlStrings(values) {
  return values.map((value) => `'${value.replaceAll("'", "''")}'`).join(',');
}

export async function inspectSourceA({ token, policy, rpcNames }) {
  const tables = sqlStrings(policy.direct_dml_tables);
  const rpcs = sqlStrings(rpcNames);
  const [summary] = await managementQuery({
    projectRef: SOURCES.a,
    token,
    query: `WITH latest AS (
        SELECT max(registry_version) AS version
        FROM public.client_sync_component_sources
      ), registry AS (
        SELECT count(*)::integer AS total,
          count(*) FILTER (WHERE cutover_ready)::integer AS ready
        FROM public.client_sync_component_sources s, latest
        WHERE s.registry_version = latest.version
      ), occasions AS (
        SELECT count(*)::integer AS total,
          count(*) FILTER (WHERE COALESCE((data->>'client_sync_v1')::boolean, false))::integer AS enabled
        FROM public.occasions
      )
      SELECT registry.total AS registry_total,
        registry.ready AS registry_ready,
        occasions.total AS occasion_total,
        occasions.enabled AS occasion_enabled
      FROM registry, occasions`,
  });
  const grants = await managementQuery({
    projectRef: SOURCES.a,
    token,
    query: `SELECT table_name, grantee,
        jsonb_agg(privilege_type ORDER BY privilege_type) AS privileges
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND grantee IN ('anon', 'authenticated')
        AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
        AND table_name IN (${tables})
      GROUP BY table_name, grantee
      ORDER BY table_name, grantee`,
  });
  const functions = await managementQuery({
    projectRef: SOURCES.a,
    token,
    query: `SELECT p.proname AS name,
        pg_get_function_identity_arguments(p.oid) AS identity_arguments,
        p.prosecdef AS security_definer,
        COALESCE(p.proconfig @> ARRAY['search_path=public, extensions'], false) AS approved_search_path
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN (${rpcs})
      ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)`,
  });
  const cohorts = await managementQuery({
    projectRef: SOURCES.a,
    token,
    query: `SELECT COALESCE((data->>'client_sync_v1')::boolean, false) AS sync_enabled,
        is_hidden,
        is_open,
        count(*)::integer AS occasions,
        count(*) FILTER (
          WHERE end_time IS NULL OR end_time >= current_date - interval '30 days'
        )::integer AS current_or_recent
      FROM public.occasions
      GROUP BY 1, 2, 3
      ORDER BY 1 DESC, 2, 3`,
  });
  return { summary, grants, functions, cohorts };
}

export async function assertSourceATarget({ token, tenantEntries }) {
  const configured = tenantEntries.filter((entry) =>
    entry.status === 'discovered' && entry.source_alias === 'a' && entry.project_ref === SOURCES.a);
  if (configured.length === 0) {
    throw new Error('source a is not resolved from any production project.conf');
  }
  const forcedLinks = [...new Set(configured.map((entry) => entry.occasion_link).filter(Boolean))].sort();
  if (forcedLinks.some((link) => !/^[a-zA-Z0-9_-]+$/.test(link))) {
    throw new Error('source-a production config has an unsafe occasion link');
  }
  if (forcedLinks.length > 0) {
    const rows = await managementQuery({
      projectRef: SOURCES.a,
      token,
      query: `SELECT link FROM public.occasions
        WHERE link IN (${sqlStrings(forcedLinks)})
        ORDER BY link`,
    });
    const found = new Set(rows.map((row) => row.link));
    const missing = forcedLinks.filter((link) => !found.has(link));
    if (missing.length > 0) {
      throw new Error(`configured source-a occasions are absent: ${missing.join(', ')}`);
    }
  }
  return {
    project_ref: SOURCES.a,
    production_configs: configured.length,
    forced_occasions_verified: forcedLinks.length,
  };
}

export function buildHybridReadiness({ policy, codeAudit, live, target, tenantInventory }) {
  const liveFunctionNames = new Set(live.functions.map((entry) => entry.name));
  const missingFunctions = codeAudit.rpc_names.filter((name) => !liveFunctionNames.has(name));
  const insecureFunctions = live.functions
    .filter((entry) => !entry.security_definer || !entry.approved_search_path)
    .map((entry) => `${entry.name}(${entry.identity_arguments ?? ''})`)
    .sort();
  const disabledOccasions = Number(live.summary.occasion_total) -
    Number(live.summary.occasion_enabled);
  const unreadyRegistry = Number(live.summary.registry_total) -
    Number(live.summary.registry_ready);
  const blockedAdapters = codeAudit.entries.length - codeAudit.seam_detected_adapters;
  const blockers = [];
  if (blockedAdapters > 0) blockers.push(`${blockedAdapters} repository adapters lack a verified RPC seam`);
  if (missingFunctions.length > 0) blockers.push(`${missingFunctions.length} canonical RPCs are missing in source a`);
  if (insecureFunctions.length > 0) blockers.push(`${insecureFunctions.length} RPC signatures lack SECURITY DEFINER with search_path=public, extensions`);
  if (unreadyRegistry > 0) blockers.push(`${unreadyRegistry} current registry sources are not cutover-ready`);
  if (disabledOccasions > 0) blockers.push(`${disabledOccasions} source-a occasions still require adoption or reachability disposition`);
  if (live.grants.length > 0) blockers.push(`${live.grants.length} direct-DML grant groups remain on legacy tables`);
  blockers.push('global writer, side-effect, deployment and traffic evidence is outside this Flutter-seam report');
  return {
    report_version: 1,
    scope: 'flutter-direct-dml-rpc-seam-only',
    source: { alias: 'a', project_ref: SOURCES.a },
    target_resolution: target ?? { status: 'fixture-only' },
    architecture_decision: {
      write_seam: 'existing explicit client_sync_v1 domain RPCs',
      journal_hook: 'transactional PostgreSQL mutation finalization',
      cloudflare_role: 'DNS/WAF and R2 image adapter only; not database write owner',
    },
    repository: codeAudit,
    live: {
      ...live.summary,
      occasion_disabled_or_unclassified: disabledOccasions,
      registry_unready: unreadyRegistry,
      direct_dml_grants: live.grants,
      occasion_cohorts: live.cohorts ?? [],
      rpc_functions_found: live.functions.length,
      rpc_functions_missing: missingFunctions,
      rpc_functions_insecure: insecureFunctions,
      production_config_gate: tenantInventory?.validation ?? { status: 'not-evaluated' },
    },
    validation: {
      status: 'blocked',
      blockers,
      hybrid_activation_authorized: false,
      permission_check_review: 'not-proven-by-this-report',
      production_mutations_performed: false,
    },
  };
}

async function main() {
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex < 0 || !process.argv[outputIndex + 1]) {
    throw new Error('usage: hybrid-readiness.mjs --output /private/path/hybrid-readiness.json');
  }
  const output = assertPrivateOutput(process.argv[outputIndex + 1]);
  assertNewEvidencePaths([output]);
  const policy = loadWriteAuthorityPolicy();
  const codeAudit = auditLegacyAdapters(policy);
  const token = accessToken();
  const tenantEntries = discoverProductionTenantConfigs();
  const tenantInventory = buildTenantConfigInventory(tenantEntries);
  const target = await assertSourceATarget({ token, tenantEntries });
  const live = await inspectSourceA({ token, policy, rpcNames: codeAudit.rpc_names });
  const report = buildHybridReadiness({ policy, codeAudit, live, target, tenantInventory });
  report.generated_at = new Date().toISOString();
  report.report_sha256 = sha256(stableJson(report));
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`hybrid readiness: status=${report.validation.status}, seams=${codeAudit.seam_detected_adapters}/${codeAudit.entries.length}, rpc_signatures=${live.functions.length}, expected_names=${codeAudit.rpc_names.length}, blockers=${report.validation.blockers.length}, sha256=${report.report_sha256}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
