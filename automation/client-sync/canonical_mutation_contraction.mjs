import fs from 'node:fs';
import {createHash} from 'node:crypto';
export const mutationInventory=JSON.parse(fs.readFileSync(new URL('./canonical-mutation-inventory.json',import.meta.url),'utf8'));
const q=x=>`'${String(x).replaceAll("'","''")}'`;
export function buildMutationContractionSql({includeSharedPlaces=false}={}) {
  const tables=[...mutationInventory.tables,...(includeSharedPlaces?mutationInventory.sharedTables:[])];
  const signatures=mutationInventory.legacyFunctions.map(x=>`public.${x.signature}`);
  const names=mutationInventory.legacyFunctions.map(x=>x.signature.split('(')[0]);
  return `-- GATED SOURCE ONLY. G2/G3 shared-consumer evidence and G4 authority required.
-- Scope: ${tables.join(', ')}. Shared places closure: ${includeSharedPlaces}.
DO $mutation_overloads$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=ANY(ARRAY[${names.map(q).join(',')}]) AND p.oid::regprocedure::text<>ALL(ARRAY[${mutationInventory.legacyFunctions.map(x=>q(x.signature)).join(',')},'update_activities(bigint)'])) THEN RAISE EXCEPTION 'unexpected legacy overload: re-inventory before contraction'; END IF;
END $mutation_overloads$;
${signatures.map(s=>`DROP FUNCTION IF EXISTS ${s};`).join('\n')}
DO $mutation_acl$
DECLARE relation regclass; role_name text; column_names text; client_role text;
BEGIN
 FOR relation IN SELECT unnest(ARRAY[${tables.map(q).join(',')}]::regclass[]) LOOP
  SELECT string_agg(quote_ident(attname),',') INTO column_names FROM pg_attribute WHERE attrelid=relation AND attnum>0 AND NOT attisdropped;
  EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM PUBLIC',relation);
  EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM PUBLIC',column_names,column_names,relation);
  FOR role_name IN SELECT DISTINCT r.rolname FROM pg_roles r WHERE r.rolname IN('anon','authenticated') OR pg_has_role('anon',r.oid,'MEMBER') OR pg_has_role('authenticated',r.oid,'MEMBER') LOOP
   IF role_name IN('postgres','service_role','authenticator') THEN RAISE EXCEPTION 'ordinary role inherits privileged lane: repair role membership explicitly'; END IF;
   EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON TABLE %s FROM %I',relation,role_name);
   EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE %s FROM %I',column_names,column_names,relation,role_name);
  END LOOP;
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated'] LOOP
   IF has_table_privilege(client_role,relation,'INSERT,UPDATE,DELETE,TRUNCATE') OR has_any_column_privilege(client_role,relation,'INSERT,UPDATE') THEN RAISE EXCEPTION 'effective DML survived: % %',client_role,relation; END IF;
  END LOOP;
 END LOOP;
END $mutation_acl$;
-- Remove only the retired writer labels; readiness and capability stay unchanged.
UPDATE public.client_sync_component_sources SET legacy_writers=ARRAY(SELECT x FROM unnest(legacy_writers) x WHERE x<>ALL(ARRAY[${names.map(q).join(',')}]::text[])) WHERE (component,source_relation) IN (${mutationInventory.registry.map(x=>`(${q(x.component)},${q(x.relation)}::regclass)`).join(',')});
DO $mutation_absence$ BEGIN
 IF EXISTS(SELECT 1 FROM unnest(ARRAY[${signatures.map(q).join(',')}]) signature WHERE to_regprocedure(signature) IS NOT NULL) THEN RAISE EXCEPTION 'legacy writer survived'; END IF;
END $mutation_absence$;`;
}
export function mutationContractionManifest({includeSharedPlaces=false}={}) {
 const sql=buildMutationContractionSql({includeSharedPlaces});
 return {schemaVersion:1,scope:mutationInventory.scope,globalAcl:true,tenantRolloutAuthorized:false,completeAclBoundary:includeSharedPlaces,tables:[...mutationInventory.tables,...(includeSharedPlaces?mutationInventory.sharedTables:[])],functions:mutationInventory.legacyFunctions.map(x=>x.signature),pendingSharedBoundaries:includeSharedPlaces?[]:mutationInventory.sharedTables,externalBoundaries:mutationInventory.externalBoundaries,sqlSha256:createHash('sha256').update(sql).digest('hex'),sql};
}
export function validateMutationEvidence(evidence,target,manifest,{now=new Date()}={}) {
 const fail=reason=>{throw new Error(`mutation contraction evidence rejected: ${reason}`);};
 if(evidence?.schemaVersion!==1 || evidence.scope!==manifest.scope || !manifest.completeAclBoundary)fail('complete shared ACL scope required');
 if(evidence.tenantId!==target.tenantId || evidence.organization!==target.organization || evidence.occasionLink!==target.occasionLink || evidence.generation!==target.generation)fail('target mismatch');
 const captured=Date.parse(evidence.capturedAt),from=Date.parse(evidence.usage?.from),to=Date.parse(evidence.usage?.to);
 if(!Number.isFinite(captured) || captured>now.getTime() || now-captured>86400000 || !Number.isFinite(from) || !Number.isFinite(to) || to<from || to>captured || captured-to>3600000)fail('dated contiguous evidence required (fresh 24h, usage gap <=1h)');
 const usage=evidence.usage;
 const required=Math.max(usage.tokenLifetimeHours,usage.maximumOfflineWriterHours);
 if(!Number.isFinite(required) || required<=0 || (to-from)/3600000<required || usage.uncoveredIntervals?.length!==0 || usage.legacyWrites!==0 || usage.rolesCovered?.sort().join(',')!=='anon,authenticated' || usage.postgrestSqlCoverage!==true || usage.serviceIntegrationCoverage!==true)fail('insufficient usage/log coverage');
 if(!Array.isArray(evidence.sharedConsumers) || !evidence.sharedConsumers.length)fail('shared consumer matrix required');
 const seen=new Set();
 for(const c of evidence.sharedConsumers) {
  const id=`${c.tenantId}/${c.platform}`;
  if(seen.has(id) || !c.tenantId || !['web','pwa','android','ios','js','service','edge','import','cron'].includes(c.platform) || !c.supportedRelease || !c.minimumWriteBuild || !c.bootstrapRoute || !c.writeRoute || c.writeGateEnforced!==true || c.oldWriterAccessDenied!==true || !c.evidenceReference)fail('incomplete or duplicate shared consumer');
  seen.add(id);
 }
 if(!Array.isArray(evidence.expectedConsumers) || !evidence.expectedConsumers.length || evidence.expectedConsumers.sort().join(',')!==[...seen].sort().join(','))fail('consumer inventory mismatch');
 if(evidence.mixedClientWindow?.editorWritesRestricted!==true || !evidence.mixedClientWindow.evidenceReference)fail('mixed-client write restriction proof required');
 if(evidence.g2?.activationVerified!==true || evidence.g2.appliedMigrationHashesVerified!==true || evidence.g2.effectiveAclInventoried!==true || evidence.g2.functionHashesVerified!==true || !evidence.g2.artifactReference || evidence.g2.enabledOccasionsInventoried!==true || evidence.g2.externalBoundariesClosed!==true)fail('G2 schema/access and external writer inventory required');
 if(evidence.sqlSha256!==manifest.sqlSha256)fail('reviewed SQL digest mismatch');
 return true;
}
export function validateMutationAuthority(authority,target,manifest) {
 if(authority?.approved!==true || !authority.reference || authority.tenantId!==target.tenantId || authority.occasionLink!==target.occasionLink || authority.organization!==target.organization || authority.sqlSha256!==manifest.sqlSha256 || authority.action!=='shared-mutation-contraction')throw new Error('separate G4 authority for exact shared SQL required');
}

export function verifyEvidenceArtifacts(evidence, directory) {
 const artifacts=evidence.artifacts;
 if(!Array.isArray(artifacts) || !artifacts.length)throw new Error('hashed evidence artifacts required');
 const references=[evidence.g2?.artifactReference,evidence.mixedClientWindow?.evidenceReference,...(evidence.sharedConsumers??[]).map(c=>c.evidenceReference),evidence.usage?.artifactReference];
 for(const reference of references)if(!artifacts.some(a=>a.id===reference))throw new Error('unresolved evidence reference');
 for(const artifact of artifacts) {
  if(!artifact.id || !artifact.file || !/^[a-f0-9]{64}$/.test(artifact.sha256??''))throw new Error('invalid hashed evidence artifact');
  const bytes=fs.readFileSync(new URL(artifact.file, `file://${directory.replace(/\/$/,'')}/`));
  if(createHash('sha256').update(bytes).digest('hex')!==artifact.sha256)throw new Error('evidence artifact digest mismatch');
 }
}
