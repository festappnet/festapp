#!/usr/bin/env bash
set -euo pipefail
readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGISTRY_FILE="${FESTAPP_SOURCE_REGISTRY:-$SCRIPT_DIR/../merge/source-registry.json}"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly SOURCE_ALIAS="${FESTAPP_MERGE_SOURCE_ALIAS:-}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "rebuild-and-validate-merge-source-client-state" ]] || fail "set the client-state acknowledgement"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid rehearsal database"
[[ "$SOURCE_ALIAS" =~ ^[a-z][a-z0-9_]{0,19}$ ]] || fail "invalid source alias"
readonly SOURCE_REF="$(jq -er --arg source "$SOURCE_ALIAS" '.sources[]|select(.alias==$source and .role=="merge-source")|.project_ref' "$REGISTRY_FILE")" || fail "unregistered merge source"
readonly LEGACY_REF_REGEX="$(jq -r '[.sources[].project_ref]|join("|")' "$REGISTRY_FILE")"
[[ "$(id -u)" == 0 && "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "run on approved rehearsal host"
cd "$COMPOSE_DIR"; docker compose config -q
psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/$SOURCE_ALIAS-client-state-final-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main -v source_alias="$SOURCE_ALIAS" -v source_ref="$SOURCE_REF" -v legacy_regex="$LEGACY_REF_REGEX" <<'SQL'
BEGIN;
SET LOCAL statement_timeout=0;
SELECT set_config('festapp.merge_source_alias',:'source_alias',true);
SELECT set_config('festapp.merge_source_ref',:'source_ref',true);
SELECT set_config('festapp.legacy_ref_regex',:'legacy_regex',true);
CREATE TEMP TABLE source_occasions(occasion bigint PRIMARY KEY) ON COMMIT DROP;
CREATE TEMP TABLE source_units(unit bigint PRIMARY KEY) ON COMMIT DROP;
DO $seed$
DECLARE import_run uuid; alias text:=current_setting('festapp.merge_source_alias'); ref text:=current_setting('festapp.merge_source_ref');
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias=alias AND source_project_ref=ref AND status='blocked';
  INSERT INTO source_occasions SELECT target_id::bigint FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='public.occasions';
  INSERT INTO source_units SELECT target_id::bigint FROM festapp_merge.id_mappings WHERE run_id=import_run AND source_table='public.units';
  IF NOT EXISTS(SELECT 1 FROM source_occasions) THEN RAISE EXCEPTION 'source has no mapped occasions'; END IF;
END $seed$;
CREATE TEMP TABLE prior_scopes ON COMMIT DROP AS SELECT component,scope_type,scope_id,to_jsonb(s) row_data FROM public.client_sync_scopes s WHERE NOT(scope_type='occasion' AND scope_id IN(SELECT occasion FROM source_occasions));
CREATE TEMP TABLE prior_private ON COMMIT DROP AS SELECT component,occasion,user_id,to_jsonb(s) row_data FROM public.client_sync_private_scopes s WHERE occasion NOT IN(SELECT occasion FROM source_occasions);
CREATE TEMP TABLE prior_dirty ON COMMIT DROP AS SELECT component,scope_type,scope_id,entity_id,to_jsonb(s) row_data FROM public.client_projection_dirty_keys s WHERE NOT(scope_type='occasion' AND scope_id IN(SELECT occasion FROM source_occasions));
CREATE TEMP TABLE prior_versions ON COMMIT DROP AS SELECT aggregate_type,scope_type,scope_id,aggregate_id,to_jsonb(s) row_data FROM public.client_aggregate_versions s WHERE NOT((scope_type='occasion' AND scope_id IN(SELECT occasion FROM source_occasions)) OR (scope_type='unit' AND scope_id IN(SELECT unit FROM source_units)));

DO $rebuild$
DECLARE import_run uuid; revision_epoch bigint; aggregate_epoch bigint; changed bigint; alias text:=current_setting('festapp.merge_source_alias'); legacy_regex text:=current_setting('festapp.legacy_ref_regex'); legacy_links bigint; invalid_components bigint; expected_private bigint; canonical_auth_mismatches bigint;
BEGIN
  SELECT run_id INTO STRICT import_run FROM festapp_merge.import_runs WHERE source_alias=alias AND status='blocked';
  IF EXISTS (WITH required(name) AS (VALUES(alias||'-id-mapping-preparation'),(alias||'-relational-import'),(alias||'-identity-profile-review'),(alias||'-auth-import'),(alias||'-storage-metadata-import'),(alias||'-storage-object-payloads'),(alias||'-auth-and-storage-import'),(alias||'-semantic-reference-validation'),(alias||'-embedded-payload-validation'),(alias||'-operational-reference-validation'),(alias||'-quarantine-disposition')) SELECT 1 FROM required LEFT JOIN festapp_merge.validation_results v ON v.run_id=import_run AND v.check_name=required.name GROUP BY required.name HAVING count(v.check_name)<>1 OR count(*) FILTER(WHERE v.status='pass')<>1) THEN RAISE EXCEPTION 'client-state prerequisite is missing or not passing'; END IF;
  SELECT coalesce(max(source_revision),0)+1 INTO revision_epoch FROM (SELECT source_revision FROM public.client_sync_scopes UNION ALL SELECT source_revision FROM public.client_sync_private_scopes) revisions;
  SELECT coalesce(max(version),0)+1 INTO aggregate_epoch FROM public.client_aggregate_versions;

  CREATE TEMP TABLE repair_commits(occasion bigint PRIMARY KEY,commit_id uuid NOT NULL) ON COMMIT DROP;
  WITH inserted AS (INSERT INTO public.client_commits(occasion,actor_kind,source,change_class,reason) SELECT occasion,'system','migration.merge.'||alias||'.client-sync-rebuild','migration','source-scoped forward-only rebuild after canonical merge' FROM source_occasions RETURNING occasion,commit_id) INSERT INTO repair_commits SELECT * FROM inserted;
  INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields) SELECT commit_id,0,'occasion',occasion::text,'import','Canonical source merge client-sync rebuild',ARRAY['public_scopes','private_vectors','aggregate_versions']::text[] FROM repair_commits;
  INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision) SELECT component,'occasion',occasion,revision_epoch FROM source_occasions CROSS JOIN unnest(ARRAY['occasion_config','program_catalog','map_catalog','content_catalog','unit_catalog','live_public']) component ON CONFLICT(component,scope_type,scope_id) DO UPDATE SET source_revision=greatest(public.client_sync_scopes.source_revision+1,excluded.source_revision),updated_at=now();
  INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision) SELECT c.commit_id,s.component,s.scope_type,s.scope_id,NULL,s.source_revision FROM repair_commits c JOIN public.client_sync_scopes s ON s.scope_type='occasion' AND s.scope_id=c.occasion;
  INSERT INTO public.client_projection_dirty_keys(component,scope_type,scope_id,entity_id,source_revision) SELECT s.component,s.scope_type,s.scope_id,0,s.source_revision FROM public.client_sync_scopes s JOIN public.occasions o ON o.id=s.scope_id WHERE s.scope_type='occasion' AND s.scope_id IN(SELECT occasion FROM source_occasions) AND NOT o.is_hidden ON CONFLICT(component,scope_type,scope_id,entity_id) DO UPDATE SET source_revision=greatest(public.client_projection_dirty_keys.source_revision,excluded.source_revision),dirty_since=now(),claimed_at=NULL,claim_token=NULL;
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision) SELECT component,ou.occasion,ou."user",revision_epoch FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" CROSS JOIN unnest(ARRAY['private_program','private_profile','private_inventory','private_activity','private_news','private_feedback']) component WHERE ou.occasion IN(SELECT occasion FROM source_occasions) ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=greatest(public.client_sync_private_scopes.source_revision+1,excluded.source_revision),updated_at=now();
  INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision) SELECT c.commit_id,s.component,'occasion',s.occasion,s.user_id,s.source_revision FROM repair_commits c JOIN public.client_sync_private_scopes s ON s.occasion=c.occasion;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT aggregate_type,scope_type,scope_id,aggregate_id,aggregate_epoch FROM (
    SELECT 'event'::text aggregate_type,'occasion'::text scope_type,e.occasion scope_id,e.id::text aggregate_id FROM public.events e WHERE e.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'information','occasion',i.occasion,i.id::text FROM public.information i WHERE i.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'news','occasion',n.occasion,n.id::text FROM public.news n WHERE n.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'occasion','occasion',o.id,o.id::text FROM public.occasions o WHERE o.id IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'occasion_user','occasion',ou.occasion,ou."user"::text FROM public.occasion_users ou WHERE ou.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'path','occasion',p.occasion,p.id::text FROM public.path_groups p WHERE p.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'place','occasion',p.occasion,p.id::text FROM public.places p WHERE p.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'place_type','occasion',p.occasion,p.id::text FROM public.place_types p WHERE p.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'speaker','occasion',s.occasion,s.id::text FROM public.speakers s WHERE s.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'speaker_topic','occasion',s.occasion,s.id::text FROM public.speaker_topics s WHERE s.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'user_group','occasion',g.occasion,g.id::text FROM public.user_group_info g WHERE g.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'inventory_pool','occasion',p.occasion,p.id::text FROM public.inventory_pools p WHERE p.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'resource','occasion',r.occasion,r.id::text FROM public.resources r WHERE r.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'exclusive_group','occasion',g.occasion,g.id::text FROM public.exclusive_groups g WHERE g.occasion IN(SELECT occasion FROM source_occasions)
    UNION ALL SELECT 'activities','occasion',a.occasion,a.occasion::text FROM public.activities a WHERE a.occasion IN(SELECT occasion FROM source_occasions) GROUP BY a.occasion
    UNION ALL SELECT 'unit','unit',u.id,u.id::text FROM public.units u WHERE u.id IN(SELECT unit FROM source_units)
    UNION ALL SELECT 'icon','unit',i.unit,i.id::text FROM public.icons i WHERE i.unit IN(SELECT unit FROM source_units)
  ) a ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=greatest(public.client_aggregate_versions.version+1,excluded.version),updated_at=clock_timestamp();

  SELECT count(*) INTO changed FROM prior_scopes b LEFT JOIN public.client_sync_scopes t USING(component,scope_type,scope_id) WHERE t.component IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data; IF changed<>0 THEN RAISE EXCEPTION 'prior public scopes changed: %',changed; END IF;
  SELECT count(*) INTO changed FROM prior_private b LEFT JOIN public.client_sync_private_scopes t USING(component,occasion,user_id) WHERE t.component IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data; IF changed<>0 THEN RAISE EXCEPTION 'prior private scopes changed: %',changed; END IF;
  SELECT count(*) INTO changed FROM prior_dirty b LEFT JOIN public.client_projection_dirty_keys t USING(component,scope_type,scope_id,entity_id) WHERE t.component IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data; IF changed<>0 THEN RAISE EXCEPTION 'prior dirty keys changed: %',changed; END IF;
  SELECT count(*) INTO changed FROM prior_versions b LEFT JOIN public.client_aggregate_versions t USING(aggregate_type,scope_type,scope_id,aggregate_id) WHERE t.aggregate_type IS NULL OR to_jsonb(t) IS DISTINCT FROM b.row_data; IF changed<>0 THEN RAISE EXCEPTION 'prior aggregate versions changed: %',changed; END IF;
  IF (SELECT count(*) FROM public.client_sync_scopes WHERE scope_type='occasion' AND scope_id IN(SELECT occasion FROM source_occasions))<>(SELECT count(*)*6 FROM source_occasions) THEN RAISE EXCEPTION 'source public scope count mismatch'; END IF;
  SELECT count(*)*6 INTO expected_private FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.occasion IN(SELECT occasion FROM source_occasions);
  IF (SELECT count(*) FROM public.client_sync_private_scopes WHERE occasion IN(SELECT occasion FROM source_occasions))<>expected_private THEN RAISE EXCEPTION 'source private scope count mismatch'; END IF;
  WITH publishable AS MATERIALIZED (SELECT s.component,s.scope_type,s.scope_id FROM public.client_sync_scopes s JOIN public.occasions o ON o.id=s.scope_id WHERE s.scope_type='occasion' AND s.scope_id IN(SELECT occasion FROM source_occasions) AND NOT o.is_hidden AND coalesce((o.data->>'client_sync_v1')::boolean,false))
  SELECT count(*) INTO invalid_components FROM publishable s WHERE CASE s.component WHEN 'content_catalog' THEN octet_length(public.get_public_client_sync_component_v1(s.component,s.scope_type,s.scope_id)::text)>2097152 WHEN 'live_public' THEN octet_length(public.get_public_client_sync_component_v1(s.component,s.scope_type,s.scope_id)::text)>524288 ELSE octet_length(public.get_public_client_sync_component_v1(s.component,s.scope_type,s.scope_id)::text)>1048576 END;
  IF invalid_components<>0 THEN RAISE EXCEPTION 'source materialization has % over-budget components',invalid_components; END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object('strategy','source-scoped-forward-only-rebuild-v1','mapped_occasions',(SELECT count(*) FROM source_occasions),'public_scopes',(SELECT count(*) FROM public.client_sync_scopes WHERE scope_type='occasion' AND scope_id IN(SELECT occasion FROM source_occasions)),'private_scopes',expected_private,'over_budget_components',0,'prior_source_rows_changed',0,'production_r2_writes',0,'requires_fresh_cutover_snapshot',true) WHERE run_id=import_run AND check_name=alias||'-client-derived-state-rebuild' AND status='blocked'; IF NOT FOUND THEN RAISE EXCEPTION 'client rebuild gate missing'; END IF;
  INSERT INTO festapp_merge.validation_results VALUES(import_run,alias||'-client-materialization','pass',jsonb_build_object('mapped_occasions',(SELECT count(*) FROM source_occasions),'over_budget_components',0,'production_r2_writes',0));

  -- Organization IDs are remapped while merging independent projects. Auth
  -- login aliases must follow the canonical user_info organization, otherwise
  -- password login and reset flows keep using the source project's prefix.
  CREATE TEMP TABLE canonical_auth_email_map ON COMMIT DROP AS
  SELECT ui.id,
    ui.organization::text||'+'||lower(btrim(ui.email_readonly)) desired_email,
    'merge-'||replace(ui.id::text,'-','')||'@invalid.local' temporary_email
  FROM public.user_info ui
  WHERE nullif(btrim(ui.email_readonly),'') IS NOT NULL;
  IF EXISTS(SELECT 1 FROM canonical_auth_email_map GROUP BY desired_email HAVING count(*)>1) OR
     EXISTS(SELECT 1 FROM canonical_auth_email_map m LEFT JOIN auth.users u ON u.id=m.id WHERE u.id IS NULL) THEN
    RAISE EXCEPTION 'canonical Auth email mapping is ambiguous or incomplete';
  END IF;
  UPDATE auth.users u SET email=m.temporary_email,updated_at=now()
  FROM canonical_auth_email_map m WHERE u.id=m.id AND lower(u.email)<>m.desired_email;
  UPDATE auth.identities i SET identity_data=jsonb_set(i.identity_data,'{email}',to_jsonb(m.temporary_email),true),updated_at=now()
  FROM canonical_auth_email_map m WHERE i.user_id=m.id AND i.provider='email' AND lower(coalesce(i.identity_data->>'email',''))<>m.desired_email;
  UPDATE auth.users u SET email=m.desired_email,updated_at=now()
  FROM canonical_auth_email_map m WHERE u.id=m.id AND lower(u.email)<>m.desired_email;
  UPDATE auth.identities i SET identity_data=jsonb_set(i.identity_data,'{email}',to_jsonb(m.desired_email),true),updated_at=now()
  FROM canonical_auth_email_map m WHERE i.user_id=m.id AND i.provider='email' AND lower(coalesce(i.identity_data->>'email',''))<>m.desired_email;
  SELECT count(*) INTO canonical_auth_mismatches
  FROM auth.users u JOIN public.user_info ui ON ui.id=u.id
  WHERE nullif(btrim(ui.email_readonly),'') IS NOT NULL
    AND lower(u.email)<>ui.organization::text||'+'||lower(btrim(ui.email_readonly));
  IF canonical_auth_mismatches<>0 OR EXISTS(
    SELECT 1 FROM auth.identities i JOIN public.user_info ui ON ui.id=i.user_id
    WHERE i.provider='email' AND nullif(btrim(ui.email_readonly),'') IS NOT NULL
      AND lower(coalesce(i.identity_data->>'email',''))<>ui.organization::text||'+'||lower(btrim(ui.email_readonly))
  ) THEN RAISE EXCEPTION 'canonical Auth email normalization failed'; END IF;

  SELECT count(*) INTO legacy_links FROM public.images WHERE link LIKE '%supabase.co/storage/v1/object/public/%';
  IF (SELECT count(*) FROM public.images i JOIN storage.objects o ON o.bucket_id=split_part(split_part(i.link,'/storage/v1/object/public/',2),'/',1) AND o.name=substring(split_part(i.link,'/storage/v1/object/public/',2) from position('/' in split_part(i.link,'/storage/v1/object/public/',2))+1) WHERE i.link LIKE '%supabase.co/storage/v1/object/public/%')<>legacy_links THEN RAISE EXCEPTION 'legacy Storage URL lacks copied object'; END IF;
  IF EXISTS(SELECT 1 FROM public.client_sync_public_heads WHERE head_json::text ~ (legacy_regex||'|supabase.co')) OR EXISTS(SELECT 1 FROM public.client_sync_publications WHERE coalesce(artifact_url,'') ~ (legacy_regex||'|supabase.co')) OR EXISTS(SELECT 1 FROM public.client_sync_release_manifests WHERE manifest::text ~ (legacy_regex||'|supabase.co') OR coalesce(artifact_url,'') ~ (legacy_regex||'|supabase.co')) THEN RAISE EXCEPTION 'legacy backend URL remains in client-sync state'; END IF;
  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object('registry_version','2026-09-10.1','known_reference_mismatches',0,'canonical_auth_email_mismatches',canonical_auth_mismatches,'legacy_storage_links',legacy_links,'legacy_storage_links_with_copied_objects',legacy_links,'storage_url_rewrite_gate','api.festapp.net-cutover','external_sync_runtime_inert',true,'deleted_rows',0) WHERE run_id=import_run AND check_name=alias||'-reference-registry-completeness' AND status='blocked'; IF NOT FOUND THEN RAISE EXCEPTION 'final reference gate missing'; END IF;
  IF EXISTS(SELECT 1 FROM festapp_merge.validation_results WHERE run_id=import_run AND status<>'pass') THEN RAISE EXCEPTION 'merge source still has a non-pass gate'; END IF;
  UPDATE festapp_merge.import_runs SET status='validated' WHERE run_id=import_run AND status='blocked'; IF NOT FOUND THEN RAISE EXCEPTION 'source final transition failed'; END IF;
END $rebuild$;
COMMIT;
SQL
psql_main -Atqc "SELECT jsonb_build_object('source_alias',source_alias,'status',status,'validation',(SELECT jsonb_object_agg(v.check_name,v.status) FROM festapp_merge.validation_results v WHERE v.run_id=import_runs.run_id),'public_scopes',(SELECT count(*) FROM public.client_sync_scopes),'private_scopes',(SELECT count(*) FROM public.client_sync_private_scopes),'storage_objects',(SELECT count(*) FROM storage.objects)) FROM festapp_merge.import_runs WHERE source_alias='$SOURCE_ALIAS'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Merge source client state rebuilt and source validated: $SOURCE_ALIAS"
echo "Evidence: $RUN_DIR"
