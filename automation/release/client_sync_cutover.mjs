#!/usr/bin/env node

import path from 'node:path';
import fs from 'node:fs';
import process from 'node:process';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';


import {parseKeyValueFile} from '../lib/supabase_management.mjs';
import {loadCanonicalTarget, canonicalQuery} from '../lib/canonical_sql_target.mjs';

import {mutationContractionManifest, validateMutationEvidence, validateMutationAuthority, verifyEvidenceArtifacts} from '../client-sync/canonical_mutation_contraction.mjs';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '../..');
const execFileAsync = promisify(execFile);

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

export function loadTarget(root = projectRoot) { return loadCanonicalTarget(root); }

export function buildPreparePublicationSql({ organization, occasionLink }) {
  return `
DO $prepare_client_sync_head$
DECLARE v_occasion bigint; v_commit uuid; v_component text; v_revision bigint;
BEGIN
  SELECT o.id INTO STRICT v_occasion FROM public.occasions o
  WHERE o.organization=${organization} AND o.link=${sqlLiteral(occasionLink)} FOR UPDATE;
  INSERT INTO public.client_commits
    (occasion,actor_kind,source,change_class,reason)
  VALUES (v_occasion,'system','client_sync.cutover.enable','configuration',
    'prepare a forward public head before enabling client_sync_v1')
  RETURNING commit_id INTO v_commit;
  FOREACH v_component IN ARRAY ARRAY['occasion_config','program_catalog','map_catalog',
    'content_catalog','unit_catalog','live_public'] LOOP
    INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
    VALUES (v_component,'occasion',v_occasion,1)
    ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
      source_revision=public.client_sync_scopes.source_revision+1,updated_at=now()
    RETURNING source_revision INTO v_revision;
    INSERT INTO public.client_commit_components
      (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
    VALUES (v_commit,v_component,'occasion',v_occasion,NULL,v_revision);
    INSERT INTO public.client_projection_dirty_keys
      (component,scope_type,scope_id,entity_id,source_revision)
    VALUES (v_component,'occasion',v_occasion,0,v_revision)
    ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
      source_revision=EXCLUDED.source_revision,dirty_since=now(),claimed_at=NULL,claim_token=NULL;
  END LOOP;
END
$prepare_client_sync_head$;`;
}

export function buildPreflightSql({ organization, occasionLink }) {
  return `
SELECT jsonb_build_object(
  'occasion', (
    SELECT jsonb_build_object(
      'id', o.id,
      'link', o.link,
      'enabled', COALESCE((o.data->>'client_sync_v1')::boolean, false)
    )
    FROM public.occasions o
    WHERE o.organization = ${organization}
      AND o.link = ${sqlLiteral(occasionLink)}
  ),
  'registryVersion', (
    SELECT max(registry_version) FROM public.client_sync_component_sources
  ),
  'registryRows', (
    SELECT count(*) FROM public.client_sync_component_sources
    WHERE registry_version=(
      SELECT max(registry_version) FROM public.client_sync_component_sources
    )
  ),
  'readyRows', (
    SELECT count(*) FROM public.client_sync_component_sources
    WHERE registry_version=(
      SELECT max(registry_version) FROM public.client_sync_component_sources
    ) AND cutover_ready
  ),
  'sourceTables', (
    SELECT count(DISTINCT source_relation)
    FROM public.client_sync_component_sources
    WHERE registry_version=(
      SELECT max(registry_version) FROM public.client_sync_component_sources
    )
  ),
  'sourceTableNames', (SELECT jsonb_agg(DISTINCT source_relation::text) FROM public.client_sync_component_sources WHERE registry_version=(SELECT max(registry_version) FROM public.client_sync_component_sources)),
  'ordinaryDmlTables', (
    SELECT count(DISTINCT s.source_relation) FROM public.client_sync_component_sources s
    WHERE s.registry_version=(SELECT max(registry_version) FROM public.client_sync_component_sources)
      AND EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated']) role_name
        WHERE has_table_privilege(role_name,s.source_relation,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege(role_name,s.source_relation,'INSERT,UPDATE'))
  ),
  'otherEnabledOccasions', (
    SELECT count(*) FROM public.occasions o
    WHERE COALESCE((o.data->>'client_sync_v1')::boolean, false)
      AND NOT (
        o.organization=${organization}
        AND o.link=${sqlLiteral(occasionLink)}
      )
  ),
  'pgauditInstalled', EXISTS (
    SELECT 1 FROM pg_extension WHERE extname='pgaudit'
  ),
  'pgauditRolesConfigured', (
    EXISTS (
      SELECT 1 FROM pg_db_role_setting s
      JOIN pg_roles r ON r.oid=s.setrole
      WHERE r.rolname='postgres'
        AND array_to_string(s.setconfig, ',') LIKE '%pgaudit.log=write%'
    ) AND EXISTS (
      SELECT 1 FROM pg_db_role_setting s
      JOIN pg_roles r ON r.oid=s.setrole
      WHERE r.rolname='authenticator'
        AND array_to_string(s.setconfig, ',') LIKE '%pgaudit.log=write%'
    )
  )
) AS result;
`;
}

export function buildActivateSql({ organization, occasionLink }) {
  return `
DO $client_sync_cutover$
DECLARE
  v_registry_version integer;
  v_relation regclass; v_role text; v_columns text;
  v_occasion_id bigint;
  v_config jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pgaudit') THEN
    RAISE EXCEPTION 'pgaudit is not installed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole
    WHERE r.rolname='postgres'
      AND array_to_string(s.setconfig, ',') LIKE '%pgaudit.log=write%'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole
    WHERE r.rolname='authenticator'
      AND array_to_string(s.setconfig, ',') LIKE '%pgaudit.log=write%'
  ) THEN
    RAISE EXCEPTION 'pgaudit write logging is not configured for required roles';
  END IF;

  SELECT max(registry_version) INTO v_registry_version
  FROM public.client_sync_component_sources;
  IF v_registry_version IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.client_sync_component_sources
    WHERE registry_version=v_registry_version
  ) THEN
    RAISE EXCEPTION 'client sync registry is empty';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.client_sync_component_sources
    WHERE registry_version=v_registry_version AND disposition='boundary'
  ) THEN
    RAISE EXCEPTION 'client sync registry contains unresolved boundaries';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE COALESCE((o.data->>'client_sync_v1')::boolean, false)
      AND NOT (
        o.organization=${organization}
        AND o.link=${sqlLiteral(occasionLink)}
      )
  ) THEN
    RAISE EXCEPTION 'another occasion already has client_sync_v1 enabled';
  END IF;

  SELECT o.id INTO STRICT v_occasion_id
  FROM public.occasions o
  WHERE o.organization=${organization}
    AND o.link=${sqlLiteral(occasionLink)}
  FOR UPDATE;

  FOR v_relation IN
    SELECT DISTINCT source_relation
    FROM public.client_sync_component_sources
    WHERE registry_version=v_registry_version
  LOOP
    SELECT string_agg(quote_ident(attname),',') INTO v_columns FROM pg_attribute WHERE attrelid=v_relation AND attnum>0 AND NOT attisdropped;
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE %s FROM PUBLIC',v_relation);
    EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM PUBLIC',v_columns,v_columns,v_relation);
    FOR v_role IN SELECT DISTINCT r.rolname FROM pg_roles r WHERE r.rolname IN('anon','authenticated') OR pg_has_role('anon',r.oid,'MEMBER') OR pg_has_role('authenticated',r.oid,'MEMBER') LOOP
      IF v_role IN('postgres','service_role','authenticator') THEN RAISE EXCEPTION 'ordinary role inherits privileged lane'; END IF;
      EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE %s FROM %I',v_relation,v_role);
      EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM %I',v_columns,v_columns,v_relation,v_role);
    END LOOP;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.client_sync_component_sources s CROSS JOIN unnest(ARRAY['anon','authenticated']) role_name WHERE s.registry_version=v_registry_version AND (has_table_privilege(role_name,s.source_relation,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege(role_name,s.source_relation,'INSERT,UPDATE'))) THEN
    RAISE EXCEPTION 'ordinary effective DML grants remain after revocation';
  END IF;

  UPDATE public.client_sync_component_sources
  SET cutover_ready=true
  WHERE registry_version=v_registry_version;

  UPDATE public.occasions
  SET data=jsonb_set(
    COALESCE(data, '{}'::jsonb),
    '{client_sync_v1}',
    'true'::jsonb,
    true
  )
  WHERE id=v_occasion_id;

  v_config := public.get_app_config_v219(jsonb_build_object(
    'link', ${sqlLiteral(occasionLink)},
    'form_link', NULL,
    'unit_id', NULL,
    'organization', ${organization},
    'platform', 'release-cutover'
  ));
  IF COALESCE((v_config->>'client_sync_v1')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'capability verification failed';
  END IF;
END
$client_sync_cutover$;
`;
}

export function buildDisableSql({ organization, occasionLink }) {
  return `
DO $client_sync_disable$
DECLARE v_count integer;
BEGIN
  UPDATE public.occasions
  SET data=jsonb_set(
    COALESCE(data, '{}'::jsonb),
    '{client_sync_v1}',
    'false'::jsonb,
    true
  )
  WHERE organization=${organization}
    AND link=${sqlLiteral(occasionLink)};
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected one target occasion, updated %', v_count;
  END IF;
END
$client_sync_disable$;
`;
}

export function activationMissingConfirmations(args, occasionLink) {
  const missing = [];
  if (
    !args.includes('--audit-gate-confirmed') &&
    !args.includes('--audit-risk-accepted')
  ) {
    missing.push('--audit-gate-confirmed or --audit-risk-accepted');
  }
  if (!args.includes('--full-registry-activation')) missing.push('--full-registry-activation');
  if (!args.some(arg=>arg.startsWith('--evidence='))) missing.push('--evidence=<dated-artifact>');
  if (!args.some(arg=>arg.startsWith('--authority='))) missing.push('--authority=<G4-artifact>');
  if (!args.includes(`--confirm=${occasionLink}`)) {
    missing.push(`--confirm=${occasionLink}`);
  }
  return missing;
}

export async function executeEnableLifecycle(actions) {
  await actions.preflight();
  await actions.preparePublication();
  await actions.publishInitialHead();
  await actions.verifyPublishedHead();
  await actions.setEnabledFlag();
}

export async function executeDisableLifecycle(actions) {
  await actions.preflight();
  await actions.deletePublicHead();
  await actions.verifyNotPublished();
  await actions.setDisabledFlag();
}

async function runPublisherOnce() {
  await execFileAsync('npm', ['run', 'once'], {
    cwd: path.join(projectRoot, 'workers/sync-publisher'),
    env: process.env,
  });
}

async function deleteExactPublicHead(organization, occasionId) {
  const wrangler = path.join(projectRoot, 'workers/sync-publisher/node_modules/.bin/wrangler');
  await execFileAsync(wrangler, [
    'r2', 'object', 'delete',
    `festapp-public/client-sync/v1/${organization}/${occasionId}/public-head.json`,
    '--remote',
  ], { cwd: path.join(projectRoot, 'workers/sync-publisher'), env: process.env });
}

async function verifyHeadStatus(origin, organization, occasionId, expectedStatus) {
  const deadline = Date.now() + (expectedStatus === 404 ? 8000 : 0);
  do {
    const response = await fetch(`${origin}/v1/public-sync/${organization}/${occasionId}/head`, {
      headers: { 'Cache-Control': 'no-cache' },
    });
    if (response.status === expectedStatus) {
      if (expectedStatus === 200) {
        const head = await response.json();
        if (head.protocol !== 1 || !head.catalog?.sha256) throw new Error('published head failed protocol/hash verification');
        for (const descriptor of [head.catalog, head.live].filter(Boolean)) {
          const artifact = await fetch(descriptor.url);
          const bytes = Buffer.from(await artifact.arrayBuffer());
          const hash = createHash('sha256').update(bytes).digest('hex');
          if (!artifact.ok || hash !== descriptor.sha256 || bytes.length !== descriptor.bytes) {
            throw new Error('published immutable artifact failed hash/length verification');
          }
        }
      }
      return;
    }
    if (Date.now() >= deadline) {
      throw new Error(`public head verification expected ${expectedStatus}, received ${response.status}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  } while (true);
}

function parseMode(args) {
  const modes = ['--apply', '--disable'].filter((flag) => args.includes(flag));
  if (modes.length > 1) throw new Error('choose only one operation');
  return modes[0] ?? '--dry-run';
}

export async function main(args = process.argv.slice(2)) {
  const option = key => args.find(arg=>arg.startsWith(`${key}=`))?.slice(key.length+1);
  const manifest = mutationContractionManifest({includeSharedPlaces:args.includes('--include-shared-places')});
  if(args.includes('--mutation-dry-run')) { console.log(JSON.stringify(manifest,null,2)); return; }
  if(args.includes('--mutation-apply')) {
    const target=loadTarget();
    const evidenceFile=option('--evidence'),authorityFile=option('--authority');
    if(!evidenceFile || !authorityFile)throw new Error('dated G2/G3 evidence and separate G4 authority required');
    const evidence=JSON.parse(fs.readFileSync(evidenceFile,'utf8'));
    validateMutationEvidence(evidence,target,manifest);
    verifyEvidenceArtifacts(evidence,path.dirname(path.resolve(evidenceFile)));
    validateMutationAuthority(JSON.parse(fs.readFileSync(authorityFile,'utf8')),target,manifest);
    await canonicalQuery({target,query:manifest.sql,operation:'write'});
    console.log(JSON.stringify({scope:manifest.scope,sqlSha256:manifest.sqlSha256,tenantId:target.tenantId}));
    return;
  }
  const mode = parseMode(args);
  const target = loadTarget();
  const queryTarget = {
    organization: target.organization,
    occasionLink: target.occasionLink,
  };

  const preflight = async () => {
    const rows = await canonicalQuery({ target, query: buildPreflightSql(queryTarget) });
    const result = rows[0]?.result;
    if (!result?.occasion) throw new Error('target occasion was not found');
    if (result.otherEnabledOccasions !== 0) throw new Error('another occasion already has client_sync_v1 enabled');
    if (!result.registryRows || result.pgauditInstalled !== true
        || result.pgauditRolesConfigured !== true) {
      throw new Error('registry or privileged audit preflight is not ready');
    }
    return result;
  };

  if (mode === '--apply') {
    const missing = activationMissingConfirmations(args, target.occasionLink);
    if (missing.length > 0) {
      throw new Error(`activation refused; missing ${missing.join(', ')}`);
    }
    const publisherConfig=parseKeyValueFile(path.join(projectRoot,'workers/sync-publisher/.env'));
    if((process.env.SUPABASE_URL || publisherConfig.get('SUPABASE_URL'))!==target.canonicalOrigin)throw new Error('publisher canonical origin must be verified before full registry activation');
    const current = await preflight();
    const fullManifest={scope:'full-registry-global-activation',completeAclBoundary:true,sqlSha256:createHash('sha256').update(buildActivateSql(queryTarget)).digest('hex')};
    const evidence=JSON.parse(fs.readFileSync(option('--evidence'),'utf8'));
    validateMutationEvidence(evidence,target,fullManifest);
    verifyEvidenceArtifacts(evidence,path.dirname(path.resolve(option('--evidence'))));
    if(!Array.isArray(evidence.coveredTables) || evidence.coveredTables.sort().join(',')!==current.sourceTableNames?.sort().join(','))throw new Error('full registry shared table coverage required');
    const authority=JSON.parse(fs.readFileSync(option('--authority'),'utf8'));
    if(authority.action!=='full-registry-global-activation')throw new Error('separate full registry G4 authority required');
    validateMutationAuthority({...authority,action:'shared-mutation-contraction'},target,fullManifest);
    await executeEnableLifecycle({
      preflight: async () => current,
      preparePublication: () => canonicalQuery({ target, query: buildPreparePublicationSql(queryTarget), operation:'write' }),
      publishInitialHead: runPublisherOnce,
      verifyPublishedHead: () => verifyHeadStatus(target.syncHeadOrigin, target.organization, current.occasion.id, 200),
      setEnabledFlag: () => canonicalQuery({ target, query: buildActivateSql(queryTarget), operation:'write' }),
    });
  } else if (mode === '--disable') {
    if (!args.includes(`--confirm=${target.occasionLink}`)) {
      throw new Error(`disable refused; missing --confirm=${target.occasionLink}`);
    }
    const current = await preflight();
    await executeDisableLifecycle({
      preflight: async () => current,
      deletePublicHead: () => deleteExactPublicHead(target.organization, current.occasion.id),
      verifyNotPublished: () => verifyHeadStatus(target.syncHeadOrigin, target.organization, current.occasion.id, 404),
      setDisabledFlag: () => canonicalQuery({ target, query: buildDisableSql(queryTarget), operation:'write' }),
    });
  }

  const rows = await canonicalQuery({
    target,
    query: buildPreflightSql(queryTarget),
  });
  const result = rows[0]?.result;
  if (!result?.occasion) throw new Error('target occasion was not found');
  console.log(JSON.stringify({ mode, tenantId: target.tenantId, ...result }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
