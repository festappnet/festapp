#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';


import {loadCanonicalTarget, canonicalQuery} from './lib/canonical_sql_target.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '..');

const feedbackFunctions = new Map([
  [
    'delete_event_feedback_for_edit_client_sync_v1',
    'database/functions/events/delete_event_feedback_for_edit.sql',
  ],
  [
    'delete_event_feedback',
    'database/functions/events/delete_event_feedback.sql',
  ],
  [
    'get_event_feedback',
    'database/functions/events/get_event_feedback.sql',
  ],
  [
    'get_event_feedback_export_for_edit',
    'database/functions/events/get_event_feedback_export_for_edit.sql',
  ],
  [
    'get_event_feedback_for_edit',
    'database/functions/events/get_event_feedback_for_edit.sql',
  ],
  [
    'get_is_event_feedback_enabled_on_occasion',
    'database/functions/events/get_is_event_feedback_enabled_on_occasion.sql',
  ],
  [
    'submit_event_feedback',
    'database/functions/events/submit_event_feedback.sql',
  ],
]);

const requiredSources = [
  'database/tables/event_feedback.sql',
  'database/tests/event_feedback_gate_test.sql',
  'database/tests/event_feedback_contract_test.sql',
  'database/operations/README.md',
  'docs/architecture/database.md',
  'docs/plans/offline-sync-revision-cache-plan-2026-08-02.md',
  'docs/plans/offline-sync-revision-cache-EXECUTION-PROMPT-2026-08-02.md',
  'docs/plans/offline-sync-preflight-baseline-2026-08-02.md',
  'supabase/migrations/20260806100000_client_sync_production_hardening.sql',
  'supabase/migrations/20260807150000_allow_admin_feedback_deletion.sql',
  'automation/release/client_sync_health.mjs',
  'automation/release/configure_client_sync_publisher_schedule.mjs',
  'automation/release/client_sync_cutover.mjs',
  ...feedbackFunctions.values(),
];

const feedbackTableContract = {
  columns: [
    { name: 'id', udt: 'int8', nullable: 'NO', default: null, identity: 'BY DEFAULT' },
    { name: 'created_at', udt: 'timestamptz', nullable: 'NO', default: 'now()', identity: null },
    { name: 'updated_at', udt: 'timestamptz', nullable: 'NO', default: 'now()', identity: null },
    { name: 'event', udt: 'int8', nullable: 'NO', default: null, identity: null },
    { name: 'occasion', udt: 'int8', nullable: 'NO', default: null, identity: null },
    { name: 'user', udt: 'uuid', nullable: 'YES', default: null, identity: null },
    { name: 'client_id', udt: 'uuid', nullable: 'YES', default: null, identity: null },
    { name: 'rating', udt: 'text', nullable: 'NO', default: null, identity: null },
    { name: 'note', udt: 'text', nullable: 'YES', default: null, identity: null },
    { name: 'data', udt: 'jsonb', nullable: 'NO', default: "'{}'::jsonb", identity: null },
  ],
  constraints: {
    event_feedback_event_fkey:
      'FOREIGN KEY (event) REFERENCES events(id) ON DELETE CASCADE',
    event_feedback_identity_check:
      'CHECK ((("user" IS NOT NULL) OR (client_id IS NOT NULL)))',
    event_feedback_note_length_check:
      "CHECK ((char_length(COALESCE(note, ''::text)) <= 2000))",
    event_feedback_occasion_fkey:
      'FOREIGN KEY (occasion) REFERENCES occasions(id) ON DELETE CASCADE',
    event_feedback_pkey: 'PRIMARY KEY (id)',
    event_feedback_rating_check:
      "CHECK ((rating = ANY (ARRAY['happy'::text, 'neutral'::text, 'sad'::text])))",
    event_feedback_user_fkey:
      'FOREIGN KEY ("user") REFERENCES user_info(id) ON DELETE SET NULL',
  },
  indexes: {
    event_feedback_event_client_uidx:
      'CREATE UNIQUE INDEX event_feedback_event_client_uidx ON public.event_feedback USING btree (event, client_id) WHERE (("user" IS NULL) AND (client_id IS NOT NULL))',
    event_feedback_event_idx:
      'CREATE INDEX event_feedback_event_idx ON public.event_feedback USING btree (event)',
    event_feedback_event_user_uidx:
      'CREATE UNIQUE INDEX event_feedback_event_user_uidx ON public.event_feedback USING btree (event, "user") WHERE ("user" IS NOT NULL)',
    event_feedback_pkey:
      'CREATE UNIQUE INDEX event_feedback_pkey ON public.event_feedback USING btree (id)',
  },
};

function extractFunctionBody(sql) {
  const match = sql.match(/\$function\$([\s\S]*)\$function\$/);
  if (!match) throw new Error('SQL source has no $function$ body');
  return match[1].replace(/\s+/g, '');
}

function normalizeSqlFragment(value) {
  return value.replace(/\s+/g, ' ').replace(/\s*,\s*/g, ', ').trim();
}

function parseLocalFunctionContract(sql, functionName) {
  const declaration = sql.match(
    new RegExp(
      `CREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+public\\.${functionName}\\s*\\(([\\s\\S]*?)\\)\\s*RETURNS\\s+([^\\s]+)`,
      'i',
    ),
  );
  if (!declaration) throw new Error('canonical CREATE FUNCTION declaration missing');

  const revokePublic = new RegExp(
    `REVOKE\\s+ALL\\s+ON\\s+FUNCTION\\s+public\\.${functionName}\\s*\\([^;]+\\)\\s+FROM\\s+PUBLIC(?:\\s*,\\s*[a-z_]+)*\\s*;`,
    'i',
  ).test(sql);
  const grant = sql.match(
    new RegExp(
      `GRANT\\s+EXECUTE\\s+ON\\s+FUNCTION\\s+public\\.${functionName}\\s*\\([^;]+\\)\\s+TO\\s+([^;]+);`,
      'i',
    ),
  );
  const executeRoles = (grant?.[1] ?? '')
    .split(',')
    .map((role) => role.trim().toLowerCase())
    .filter(Boolean)
    .sort();

  return {
    args: normalizeSqlFragment(declaration[1]),
    result: normalizeSqlFragment(declaration[2]).toLowerCase(),
    volatility: /\bSTABLE\b/i.test(sql)
      ? 's'
      : /\bIMMUTABLE\b/i.test(sql)
        ? 'i'
        : 'v',
    securityDefiner: /\bSECURITY\s+DEFINER\b/i.test(sql),
    searchPath: /\bSET\s+search_path\s*=\s*public\s*,\s*extensions\b/i.test(sql),
    revokePublic,
    executeRoles,
    body: extractFunctionBody(sql),
  };
}

function parseLocalTableSecurity(sql) {
  const has = (pattern) => pattern.test(sql);
  return {
    rlsEnabled: has(
      /ALTER\s+TABLE\s+public\.event_feedback\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY\s*;/i,
    ),
    tableRevoked: has(
      /REVOKE\s+ALL\s+ON\s+TABLE\s+public\.event_feedback\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*;/i,
    ),
    serviceTableAll: has(
      /GRANT\s+ALL\s+ON\s+TABLE\s+public\.event_feedback\s+TO\s+service_role\s*;/i,
    ),
    sequenceRevoked: has(
      /REVOKE\s+ALL\s+ON\s+SEQUENCE\s+public\.event_feedback_id_seq\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*;/i,
    ),
    serviceSequencePrivileges: has(
      /GRANT\s+USAGE\s*,\s*SELECT\s*,\s*UPDATE\s+ON\s+SEQUENCE\s+public\.event_feedback_id_seq\s+TO\s+service_role\s*;/i,
    ),
  };
}

function runLocalChecks() {
  const missingSources = requiredSources.filter(
    (relativePath) => !fs.existsSync(path.join(projectRoot, relativePath)),
  );

  const invalidFunctions = [];
  for (const [functionName, relativePath] of feedbackFunctions) {
    const absolutePath = path.join(projectRoot, relativePath);
    if (!fs.existsSync(absolutePath)) continue;
    const sql = fs.readFileSync(absolutePath, 'utf8');
    try {
      const contract = parseLocalFunctionContract(sql, functionName);
      if (
        !contract.securityDefiner ||
        !contract.searchPath ||
        !contract.revokePublic ||
        ['authenticated', 'service_role'].some(
          (role) => !contract.executeRoles.includes(role),
        )
      ) {
        invalidFunctions.push({
          functionName,
          relativePath,
          reason: 'incomplete_security_contract',
        });
      }
    } catch (error) {
      invalidFunctions.push({
        functionName,
        relativePath,
        reason: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const tablePath = path.join(projectRoot, 'database/tables/event_feedback.sql');
  const invalidTableSecurity = fs.existsSync(tablePath)
    ? Object.entries(parseLocalTableSecurity(fs.readFileSync(tablePath, 'utf8')))
        .filter(([, present]) => !present)
        .map(([clause]) => clause)
    : [];
  const hardeningPath = path.join(
    projectRoot,
    'supabase/migrations/20260806100000_client_sync_production_hardening.sql',
  );
  const hardening = fs.existsSync(hardeningPath)
    ? fs.readFileSync(hardeningPath, 'utf8')
    : '';
  const publisherPackage = fs.readFileSync(
    path.join(projectRoot, 'workers/sync-publisher/package.json'),
    'utf8',
  );
  const hardeningFailures = [
    ...(fs.existsSync(path.join(projectRoot, 'workers/sync-publisher/src/loop.ts'))
      ? ['unmanaged_loop_runtime'] : []),
    ...(JSON.parse(publisherPackage).scripts?.start ? ['publisher_start_script'] : []),
    ...(/CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER/i.test(hardening)
      ? ['persistent_application_trigger'] : []),
    ...(!hardening.includes('release_client_projection_claims_v1')
      ? ['claim_release_missing'] : []),
    ...(!hardening.includes('delete_client_sync_artifact_metadata_v1')
      ? ['retention_recheck_missing'] : []),
  ];

  return {
    ok:
      missingSources.length === 0 &&
      invalidFunctions.length === 0 &&
      invalidTableSecurity.length === 0 &&
      hardeningFailures.length === 0,
    requiredSourceCount: requiredSources.length,
    feedbackFunctionCount: feedbackFunctions.size,
    missingSources,
    invalidFunctions,
    invalidTableSecurity,
    hardeningFailures,
  };
}

async function runRemoteChecks() {
  const target = loadCanonicalTarget(projectRoot);

  const functionNames = [...feedbackFunctions.keys()];
  const quotedNames = functionNames.map((name) => `'${name}'`).join(',');
  const definitions = await canonicalQuery({
    target,
    query: `
      SELECT
        p.proname,
        pg_get_function_arguments(p.oid) AS args,
        pg_get_function_result(p.oid) AS result,
        p.provolatile AS volatility,
        p.prosecdef AS security_definer,
        p.proconfig AS config,
        EXISTS (
          SELECT 1
          FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
          WHERE acl.grantee = 0
            AND acl.privilege_type = 'EXECUTE'
        ) AS public_execute,
        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
        has_function_privilege('authenticated', p.oid, 'EXECUTE')
          AS authenticated_execute,
        has_function_privilege('service_role', p.oid, 'EXECUTE')
          AS service_role_execute,
        pg_get_functiondef(p.oid) AS definition
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN (${quotedNames})
        AND p.prokind = 'f'
      ORDER BY p.proname;
    `,
  });

  const remoteByName = new Map();
  const duplicateFunctions = [];
  for (const row of definitions) {
    if (remoteByName.has(row.proname)) duplicateFunctions.push(row.proname);
    remoteByName.set(row.proname, row);
  }
  const functionDrift = [];
  for (const [functionName, relativePath] of feedbackFunctions) {
    const remoteFunction = remoteByName.get(functionName);
    const localDefinition = fs.readFileSync(
      path.join(projectRoot, relativePath),
      'utf8',
    );
    const expectedContract = parseLocalFunctionContract(
      localDefinition,
      functionName,
    );
    if (!remoteFunction) {
      functionDrift.push({ functionName, reason: 'missing_in_production' });
      continue;
    }
    const contractMatches =
      remoteFunction.args === expectedContract.args &&
      remoteFunction.result === expectedContract.result &&
      remoteFunction.volatility === expectedContract.volatility &&
      remoteFunction.security_definer === expectedContract.securityDefiner &&
      JSON.stringify(remoteFunction.config) ===
        JSON.stringify(
          expectedContract.searchPath ? ['search_path=public, extensions'] : [],
        ) &&
      remoteFunction.public_execute === !expectedContract.revokePublic &&
      remoteFunction.anon_execute ===
        expectedContract.executeRoles.includes('anon') &&
      remoteFunction.authenticated_execute ===
        expectedContract.executeRoles.includes('authenticated') &&
      remoteFunction.service_role_execute ===
        expectedContract.executeRoles.includes('service_role');
    if (!contractMatches) {
      functionDrift.push({ functionName, reason: 'contract_mismatch' });
    }
    if (expectedContract.body !== extractFunctionBody(remoteFunction.definition)) {
      functionDrift.push({ functionName, reason: 'body_mismatch' });
    }
  }
  for (const functionName of duplicateFunctions) {
    functionDrift.push({ functionName, reason: 'unexpected_overload' });
  }

  const tableRows = await canonicalQuery({
    target,
    query: `
      SELECT jsonb_build_object(
        'columns', (
          SELECT jsonb_agg(
            jsonb_build_object(
              'name', column_name,
              'udt', udt_name,
              'nullable', is_nullable,
              'default', column_default,
              'identity', identity_generation
            )
            ORDER BY ordinal_position
          )
          FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'event_feedback'
        ),
        'constraints', (
          SELECT jsonb_object_agg(conname, pg_get_constraintdef(oid))
          FROM pg_constraint
          WHERE conrelid = 'public.event_feedback'::regclass
        ),
        'indexes', (
          SELECT jsonb_object_agg(indexname, indexdef)
          FROM pg_indexes
          WHERE schemaname = 'public'
            AND tablename = 'event_feedback'
        ),
        'policy_count', (
          SELECT count(*)
          FROM pg_policies
          WHERE schemaname = 'public'
            AND tablename = 'event_feedback'
        ),
        'rls_enabled', (
          SELECT relrowsecurity
          FROM pg_class
          WHERE oid = 'public.event_feedback'::regclass
        ),
        'grants', jsonb_build_object(
          'anon_select', has_table_privilege(
            'anon', 'public.event_feedback', 'SELECT'
          ),
          'anon_insert', has_table_privilege(
            'anon', 'public.event_feedback', 'INSERT'
          ),
          'anon_update', has_table_privilege(
            'anon', 'public.event_feedback', 'UPDATE'
          ),
          'anon_delete', has_table_privilege(
            'anon', 'public.event_feedback', 'DELETE'
          ),
          'authenticated_select', has_table_privilege(
            'authenticated', 'public.event_feedback', 'SELECT'
          ),
          'authenticated_insert', has_table_privilege(
            'authenticated', 'public.event_feedback', 'INSERT'
          ),
          'authenticated_update', has_table_privilege(
            'authenticated', 'public.event_feedback', 'UPDATE'
          ),
          'authenticated_delete', has_table_privilege(
            'authenticated', 'public.event_feedback', 'DELETE'
          ),
          'service_all', has_table_privilege(
            'service_role', 'public.event_feedback',
            'SELECT,INSERT,UPDATE,DELETE'
          ),
          'anon_sequence_usage', has_sequence_privilege(
            'anon', 'public.event_feedback_id_seq', 'USAGE'
          ),
          'anon_sequence_select', has_sequence_privilege(
            'anon', 'public.event_feedback_id_seq', 'SELECT'
          ),
          'anon_sequence_update', has_sequence_privilege(
            'anon', 'public.event_feedback_id_seq', 'UPDATE'
          ),
          'authenticated_sequence_usage', has_sequence_privilege(
            'authenticated', 'public.event_feedback_id_seq', 'USAGE'
          ),
          'authenticated_sequence_select', has_sequence_privilege(
            'authenticated', 'public.event_feedback_id_seq', 'SELECT'
          ),
          'authenticated_sequence_update', has_sequence_privilege(
            'authenticated', 'public.event_feedback_id_seq', 'UPDATE'
          ),
          'service_sequence_usage', has_sequence_privilege(
            'service_role', 'public.event_feedback_id_seq', 'USAGE'
          ),
          'service_sequence_select', has_sequence_privilege(
            'service_role', 'public.event_feedback_id_seq', 'SELECT'
          ),
          'service_sequence_update', has_sequence_privilege(
            'service_role', 'public.event_feedback_id_seq', 'UPDATE'
          )
        )
      ) AS contract;
    `,
  });
  const tableContract = tableRows[0]?.contract;
  const canonicalJson = (value) => {
    if (Array.isArray(value)) return value.map(canonicalJson);
    if (value && typeof value === 'object') {
      return Object.fromEntries(
        Object.entries(value)
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([key, item]) => [key, canonicalJson(item)]),
      );
    }
    return value;
  };
  const sameValues = (actual, expected) =>
    JSON.stringify(canonicalJson(actual ?? [])) ===
    JSON.stringify(canonicalJson(expected));
  const tableDrift = [];
  if (!sameValues(tableContract?.columns, feedbackTableContract.columns)) {
    tableDrift.push('columns');
  }
  if (!sameValues(tableContract?.constraints, feedbackTableContract.constraints)) {
    tableDrift.push('constraints');
  }
  if (!sameValues(tableContract?.indexes, feedbackTableContract.indexes)) {
    tableDrift.push('indexes');
  }
  if (Number(tableContract?.policy_count) !== 0) {
    tableDrift.push('policies');
  }
  if (tableContract?.rls_enabled !== true) tableDrift.push('rls');
  if (
    !sameValues(tableContract?.grants, {
      anon_select: false,
      anon_insert: false,
      anon_update: false,
      anon_delete: false,
      authenticated_select: false,
      authenticated_insert: false,
      authenticated_update: false,
      authenticated_delete: false,
      service_all: true,
      anon_sequence_usage: false,
      anon_sequence_select: false,
      anon_sequence_update: false,
      authenticated_sequence_usage: false,
      authenticated_sequence_select: false,
      authenticated_sequence_update: false,
      service_sequence_usage: true,
      service_sequence_select: true,
      service_sequence_update: true,
    })
  ) {
    tableDrift.push('grants');
  }

  const auditRows = await canonicalQuery({
    target,
    query: `
      SELECT
        current_setting('log_statement', true) AS log_statement,
        current_setting('log_min_duration_statement', true)
          AS log_min_duration_statement,
        current_setting('pgaudit.log', true) AS pgaudit_log,
        EXISTS (
          SELECT 1 FROM pg_extension WHERE extname = 'pgaudit'
        ) AS pgaudit_installed,
        EXISTS (
          SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
        ) AS pg_stat_statements_installed;
    `,
  });
  const audit = auditRows[0];
  const privilegedDmlAuditReady =
    audit?.pgaudit_installed === true &&
    typeof audit?.pgaudit_log === 'string' &&
    audit.pgaudit_log !== 'none';

  const mutationRows = await canonicalQuery({target, query: fs.readFileSync(path.join(projectRoot,'database/operations/canonical_mutation_inventory.sql'),'utf8')});
  return {
    mutationInventory: mutationRows[0]?.result ?? null,
    ok: functionDrift.length === 0 && tableDrift.length === 0,
    tenantId: target.tenantId,
    feedbackFunctionsFound: remoteByName.size,
    functionDrift,
    tableDrift,
    tableGrantState: tableContract?.grants ?? null,
    audit: {
      ...audit,
      privilegedDmlAuditReady,
    },
    feedbackAuditBlockers: [
      ...(privilegedDmlAuditReady
        ? []
        : ['privileged_dml_audit_not_configured']),
    ],
    feedbackAuditReady:
      functionDrift.length === 0 &&
      tableDrift.length === 0 &&
      privilegedDmlAuditReady,
  };
}

const feedbackAuditGateRequested = process.argv.includes('--feedback-audit-gate');
const remoteRequested =
  process.argv.includes('--remote') || feedbackAuditGateRequested;
const local = runLocalChecks();
let remote = null;
let fatalError = null;

try {
  if (remoteRequested) remote = await runRemoteChecks();
} catch (error) {
  fatalError = error instanceof Error ? error.message : String(error);
}

const result = {
  generatedAt: new Date().toISOString(),
  mode: feedbackAuditGateRequested
    ? 'feedback-audit-gate-read-only'
    : remoteRequested
      ? 'remote-read-only'
      : 'repo-only',
  local,
  remote,
  fatalError,
};

console.log(JSON.stringify(result, null, 2));

if (
  !local.ok ||
  fatalError ||
  (remoteRequested && !remote?.ok) ||
  (feedbackAuditGateRequested && !remote?.feedbackAuditReady)
) {
  process.exitCode = 1;
}
