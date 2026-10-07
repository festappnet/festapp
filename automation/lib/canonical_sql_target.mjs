import path from 'node:path';
import { execFile } from 'node:child_process';
import { parseKeyValueFile } from './supabase_management.mjs';
import { canonicalBackendProfileSha256 } from './backend_activation_manifest.mjs';
const literal = value => `'${String(value).replaceAll("'", "''")}'`;

// Operational target comes exclusively from activation, never compiled SUPABASE_URL.
export function loadCanonicalTarget(root, {configFile = path.join(root, 'automation/project.conf')} = {}) {
  const c = parseKeyValueFile(configFile);
  const canonicalOrigin = c.get('BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL');
  const tenantId = c.get('BACKEND_ACTIVATION_TENANT_ID');
  const organization = Number(c.get('BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID'));
  const occasionLink = c.get('FORCE_OCCASION_LINK');
  if (c.get('BACKEND_ACTIVATION_PHASE') !== 'canonical') throw new Error('canonical activation phase required');
  if (canonicalOrigin !== 'https://api.festapp.net') throw new Error('canonical API origin required; cloud fallback forbidden');
  if (!tenantId || !Number.isSafeInteger(organization) || organization <= 0 || !/^[a-z0-9][a-z0-9-]*$/.test(occasionLink ?? '')) throw new Error('explicit canonical tenant, organization and occasion required');
  const profile = canonicalBackendProfileSha256({tenantId, canonicalOrigin, canonicalAnonKey:c.get('BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY'),canonicalOrganizationId:organization});
  // apply_config.sh derives this hash; issued tenant source configs may omit it.
  const pinnedProfile = c.get('BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256');
  if (pinnedProfile && profile !== pinnedProfile) throw new Error('canonical activation profile mismatch');
  const webLink = c.get('WEB_LINK');
  if (!webLink?.startsWith('https://')) throw new Error('HTTPS WEB_LINK required');
  return {root, tenantId, organization, occasionLink, canonicalOrigin, profileSha256:profile, generation:1, webLink, syncHeadOrigin:c.get('SYNC_HEAD_ORIGIN')};
}
export function assertCanonicalActivation(target, document) {
  if (document?.schemaVersion !== 1 || document.backend !== 'canonical' || document.generation !== target.generation || document.tenantId !== target.tenantId) throw new Error('live canonical activation mismatch');
}
export function buildCanonicalTargetGuard(target) {
  if (!Number.isSafeInteger(target.organization) || target.organization <= 0 || target.generation !== 1 || !/^[a-z0-9][a-z0-9-]*$/.test(target.occasionLink ?? '')) throw new Error('invalid canonical SQL target');
  return `DO $canonical_target$ BEGIN IF (SELECT count(*) FROM public.occasions WHERE organization=${target.organization} AND link=${literal(target.occasionLink)})<>1 THEN RAISE EXCEPTION 'canonical organization/occasion mismatch'; END IF; END $canonical_target$;`;
}
export async function canonicalQuery({target, query, operation = 'read'}, {fetchActivation = async t => {
  const r = await fetch(`${t.webLink.replace(/\/$/,'')}/backend-activation.json`, {headers:{'User-Agent':'Mozilla/5.0'}, cache:'no-store', redirect:'error', signal:AbortSignal.timeout(15000)});
  if (!r.ok) throw new Error('live activation unavailable');
  return r.json();
}, executeSql = null} = {}) {
  assertCanonicalActivation(target, await fetchActivation(target));
  if(!['read','write'].includes(operation))throw new Error('explicit SQL operation required');
  // The real executor enforces a read-only transaction and preserves result rows.
  const guarded = `${buildCanonicalTargetGuard(target)}\n${query}`;
  const sql = operation==='write' ? `BEGIN;\n${guarded}\nCOMMIT;` : guarded;
  if (executeSql) return executeSql(sql);
  return executeProtectedCanonicalSql({root:target.root,guard:buildCanonicalTargetGuard(target),query,operation});
}

function runWithInput(command,args,input) {
  return new Promise((resolve,reject)=>{
    const child=execFile(command,args,{maxBuffer:8*1024*1024,timeout:60000},(error,stdout)=>error?reject(error):resolve({stdout}));
    child.stdin.on('error',()=>{});
    child.stdin.end(input);
  });
}
const shellQuote = value => `'${String(value).replaceAll("'", "'\\''")}'`;

export async function executeProtectedCanonicalSql({root,guard,query,operation}, {run=runWithInput}={}) {
  if(!['read','write'].includes(operation))throw new Error('explicit SQL operation required');
  const skill=path.join(root,'.agents/skills/festapp-backend-access/scripts');
  const assertions=JSON.parse((await run('python3',[path.join(skill,'target.py')],'')).stdout);
  if(!/^[a-z0-9_-]+$/.test(assertions.database??'') || !/^[a-z0-9-]+$/.test(assertions.expected_hostname??''))throw new Error('invalid protected backend assertions');
  // Reuse the existing alias/key/token. Its installed proxy path may be stale;
  // resolve the same project-owned proxy without changing SSH configuration.
  const sshArgs=['-o',`ProxyCommand=python3 ${shellQuote(path.join(skill,'proxy.py'))}`,'festapp-backend-agent'];
  const identity=(await run('ssh',[...sshArgs,"hostname -s; sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' /opt/festapp-supabase/docker/.env"],'')).stdout.trim().split(/\r?\n/);
  if(identity.length!==2 || identity[0]!==assertions.expected_hostname || identity[1]!==assertions.database)throw new Error('protected backend hostname/runtime database mismatch');
  const databaseGuard=`DO $database_identity$ BEGIN IF current_database()<>${literal(assertions.database)} THEN RAISE EXCEPTION 'canonical runtime database mismatch'; END IF; END $database_identity$;`;
  const resultQuery=operation==='read'?`SELECT COALESCE(jsonb_agg(row_to_json(r)),'[]'::jsonb) FROM (\n${query.trim().replace(/;\s*$/,'')}\n) r;`:query;
  const sql=`BEGIN${operation==='read'?' READ ONLY':''};\nSET LOCAL statement_timeout='45s';\n${databaseGuard}\n${guard}\n${resultQuery}\n${operation==='read'?'ROLLBACK':'COMMIT'};`;
  const {stdout}=await run('ssh',[...sshArgs,`docker exec -i supabase-db psql -X -q -A -t -U postgres -d ${shellQuote(assertions.database)} -v ON_ERROR_STOP=1`],sql);
  return operation==='read'?JSON.parse(stdout):[];
}
