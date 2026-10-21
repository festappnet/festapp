#!/usr/bin/env bash
set -euo pipefail

readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="${FESTAPP_REHEARSAL_COMPOSE_DIR:-/opt/festapp-supabase/docker}"
readonly EVIDENCE_ROOT="${FESTAPP_REHEARSAL_EVIDENCE_ROOT:-/var/lib/festapp-rehearsal-evidence}"
readonly TARGET_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_REHEARSAL_ACK:-}" == "rebuild-a-client-derived-state-forward-only" ]] ||
  fail "set FESTAPP_REHEARSAL_ACK=rebuild-a-client-derived-state-forward-only"
[[ "$TARGET_DATABASE" == "postgres" || "$TARGET_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] || fail "invalid isolated rehearsal database name"
[[ "$(id -u)" == "0" ]] || fail "run as root on rehearsal host"
[[ "$(hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "refusing unexpected host"
cd "$COMPOSE_DIR"
docker compose config -q

psql_main() { docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U postgres -d "$TARGET_DATABASE" "$@"; }
readonly STATE="$(psql_main -Atqc "SELECT concat_ws('|',split_part(current_setting('server_version'),'.',1),
  (SELECT count(*) FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked'),
  (SELECT NOT EXISTS (
    WITH required(check_name) AS (VALUES
      ('a-relational-import'),('a-identity-profile-review'),('a-semantic-reference-repair'),
      ('a-embedded-payload-repair'),('a-operational-reference-repair'),('a-auth-import'),
      ('a-storage-metadata-import'),('a-storage-object-payloads'),('a-auth-and-storage-import')
    ), a_run AS (SELECT run_id FROM festapp_merge.import_runs WHERE source_alias='a')
    SELECT 1 FROM required CROSS JOIN a_run
    LEFT JOIN festapp_merge.validation_results v
      ON v.run_id=a_run.run_id AND v.check_name=required.check_name
    GROUP BY required.check_name
    HAVING count(v.check_name)<>1 OR count(*) FILTER (WHERE v.status='pass')<>1)),
  (SELECT count(*) FROM festapp_merge.validation_results v JOIN festapp_merge.import_runs r USING(run_id)
    WHERE r.source_alias='a' AND v.check_name='a-client-derived-state-rebuild' AND v.status='blocked'),
  (SELECT count(*) FROM public.client_sync_scopes),(SELECT count(*) FROM public.client_sync_private_scopes),
  (SELECT count(*) FROM public.client_projection_dirty_keys))")"
[[ "$STATE" == "17|1|t|1|0|0|0" ]] || fail "target is not approved derived-state rebuild state ($STATE)"

install -d -o root -g root -m 0700 "$EVIDENCE_ROOT"
readonly RUN_DIR="$EVIDENCE_ROOT/a-client-derived-state-rebuild-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$RUN_DIR"

psql_main <<'SQL'
BEGIN;
SET LOCAL statement_timeout = 0;

DO $repair$
DECLARE
  import_run uuid;
  revision_epoch bigint;
  aggregate_epoch bigint;
  release_epoch bigint;
  excluded_source_rows bigint;
BEGIN
  SELECT run_id INTO STRICT import_run
  FROM festapp_merge.import_runs WHERE source_alias='a' AND status='blocked';

  SELECT greatest(
    COALESCE((SELECT max(source_revision) FROM festapp_stage_a_public.client_sync_scopes),0),
    COALESCE((SELECT max(source_revision) FROM festapp_stage_a_public.client_sync_private_scopes),0),
    COALESCE((SELECT max(source_revision) FROM festapp_stage_a_public.client_projection_dirty_keys),0),
    COALESCE((SELECT max(published_revision) FROM festapp_stage_a_public.client_sync_publications),0),
    COALESCE((SELECT max(source_revision) FROM public.client_sync_scopes),0),
    COALESCE((SELECT max(source_revision) FROM public.client_sync_private_scopes),0)
  ) + 1 INTO revision_epoch;
  SELECT greatest(
    COALESCE((SELECT max(version) FROM festapp_stage_a_public.client_aggregate_versions),0),
    COALESCE((SELECT max(version) FROM public.client_aggregate_versions),0)
  ) + 1 INTO aggregate_epoch;
  SELECT greatest(
    COALESCE((SELECT max(release_revision) FROM festapp_stage_a_public.client_sync_release_manifests),0),
    COALESCE((SELECT max(release_revision) FROM festapp_stage_a_public.client_sync_public_heads),0),
    COALESCE((SELECT max(release_revision) FROM public.client_sync_release_manifests),0)
  ) INTO release_epoch;
  SELECT (observed->>'excluded_derived_rows')::bigint INTO STRICT excluded_source_rows
  FROM festapp_merge.validation_results WHERE run_id=import_run AND check_name='a-relational-import' AND status='pass';

  CREATE TEMP TABLE repair_commits(occasion bigint PRIMARY KEY,commit_id uuid NOT NULL) ON COMMIT DROP;
  WITH inserted AS (
    INSERT INTO public.client_commits(occasion,actor_kind,source,change_class,reason)
    SELECT o.id,'system','migration.merge.client-sync-rebuild','migration',
      'forward-only rebuild after canonical merge; source operational history preserved privately'
    FROM public.occasions o
    RETURNING occasion,commit_id
  ) INSERT INTO repair_commits SELECT occasion,commit_id FROM inserted;

  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  SELECT r.commit_id,0,'occasion',r.occasion::text,'import','Canonical merge client-sync rebuild',
    ARRAY['public_scopes','private_vectors','aggregate_versions']::text[]
  FROM repair_commits r;

  INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
  SELECT component,'occasion',o.id,revision_epoch
  FROM public.occasions o CROSS JOIN unnest(ARRAY[
    'occasion_config','program_catalog','map_catalog','content_catalog','unit_catalog','live_public'
  ]) component
  ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
    source_revision=greatest(public.client_sync_scopes.source_revision+1,EXCLUDED.source_revision),
    updated_at=now();

  INSERT INTO public.client_commit_components
    (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
  SELECT r.commit_id,s.component,s.scope_type,s.scope_id,NULL,s.source_revision
  FROM repair_commits r JOIN public.client_sync_scopes s
    ON s.scope_type='occasion' AND s.scope_id=r.occasion;

  -- Hidden occasions are prepared but not queued: the publisher correctly
  -- refuses to expose them. Saving/unhiding through the canonical command will
  -- advance and enqueue them later.
  INSERT INTO public.client_projection_dirty_keys
    (component,scope_type,scope_id,entity_id,source_revision)
  SELECT s.component,s.scope_type,s.scope_id,0,s.source_revision
  FROM public.client_sync_scopes s JOIN public.occasions o ON o.id=s.scope_id
  WHERE s.scope_type='occasion' AND NOT o.is_hidden
  ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
    source_revision=greatest(public.client_projection_dirty_keys.source_revision,EXCLUDED.source_revision),
    dirty_since=now(),claimed_at=NULL,claim_token=NULL;

  INSERT INTO public.client_sync_private_scopes
    (component,occasion,user_id,source_revision)
  SELECT component,ou.occasion,ou."user",revision_epoch
  FROM public.occasion_users ou
  JOIN public.user_info ui ON ui.id=ou."user"
  CROSS JOIN unnest(ARRAY[
    'private_program','private_profile','private_inventory',
    'private_activity','private_news','private_feedback'
  ]) component
  ON CONFLICT (component,occasion,user_id) DO UPDATE SET
    source_revision=greatest(public.client_sync_private_scopes.source_revision+1,EXCLUDED.source_revision),
    updated_at=now();

  INSERT INTO public.client_commit_components
    (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
  SELECT r.commit_id,s.component,'occasion',s.occasion,s.user_id,s.source_revision
  FROM repair_commits r JOIN public.client_sync_private_scopes s ON s.occasion=r.occasion;

  -- Recreate optimistic-concurrency versions from canonical business rows.
  -- A migration epoch above every source version forces stale editors to
  -- refetch instead of accepting a pre-merge version accidentally.
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT aggregate_type,scope_type,scope_id,aggregate_id,aggregate_epoch FROM (
    SELECT 'event'::text aggregate_type,'occasion'::text scope_type,e.occasion scope_id,e.id::text aggregate_id FROM public.events e
    UNION ALL SELECT 'information','occasion',i.occasion,i.id::text FROM public.information i
    UNION ALL SELECT 'news','occasion',n.occasion,n.id::text FROM public.news n
    UNION ALL SELECT 'occasion','occasion',o.id,o.id::text FROM public.occasions o
    UNION ALL SELECT 'occasion_user','occasion',ou.occasion,ou."user"::text FROM public.occasion_users ou
    UNION ALL SELECT 'path','occasion',p.occasion,p.id::text FROM public.path_groups p
    UNION ALL SELECT 'place','occasion',p.occasion,p.id::text FROM public.places p
    UNION ALL SELECT 'place_type','occasion',p.occasion,p.id::text FROM public.place_types p
    UNION ALL SELECT 'speaker','occasion',s.occasion,s.id::text FROM public.speakers s
    UNION ALL SELECT 'speaker_topic','occasion',s.occasion,s.id::text FROM public.speaker_topics s
    UNION ALL SELECT 'user_group','occasion',g.occasion,g.id::text FROM public.user_group_info g
    UNION ALL SELECT 'inventory_pool','occasion',p.occasion,p.id::text FROM public.inventory_pools p
    UNION ALL SELECT 'resource','occasion',r.occasion,r.id::text FROM public.resources r
    UNION ALL SELECT 'exclusive_group','occasion',g.occasion,g.id::text FROM public.exclusive_groups g
    UNION ALL SELECT 'activities','occasion',a.occasion,a.occasion::text FROM public.activities a GROUP BY a.occasion
    UNION ALL SELECT 'unit','unit',u.id,u.id::text FROM public.units u
    UNION ALL SELECT 'icon','unit',i.unit,i.id::text FROM public.icons i WHERE i.unit IS NOT NULL
  ) canonical_aggregates
  WHERE scope_id IS NOT NULL
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET
    version=greatest(public.client_aggregate_versions.version+1,EXCLUDED.version),
    updated_at=clock_timestamp();

  PERFORM setval('public.client_sync_release_revision_seq',
    greatest((SELECT last_value FROM public.client_sync_release_revision_seq),release_epoch),true);

  UPDATE festapp_merge.validation_results SET status='pass',observed=jsonb_build_object(
    'strategy','forward-only-canonical-rebuild-v1',
    'excluded_source_rows_preserved',excluded_source_rows,
    'revision_epoch',revision_epoch,
    'aggregate_epoch',aggregate_epoch,
    'release_sequence_floor',release_epoch,
    'public_scopes',(SELECT count(*) FROM public.client_sync_scopes),
    'private_scopes',(SELECT count(*) FROM public.client_sync_private_scopes),
    'unreachable_memberships_without_profile',(SELECT count(*) FROM public.occasion_users ou WHERE NOT EXISTS (SELECT 1 FROM public.user_info ui WHERE ui.id=ou."user")),
    'aggregate_versions',(SELECT count(*) FROM public.client_aggregate_versions),
    'dirty_visible_scopes',(SELECT count(*) FROM public.client_projection_dirty_keys),
    'production_r2_writes',0,
    'requires_fresh_cutover_snapshot',true)
  WHERE run_id=import_run AND check_name='a-client-derived-state-rebuild';

  -- The reference-registry validator is the sole owner of the final
  -- blocked -> validated transition after it observes this gate as passing.
END
$repair$;

COMMIT;
SQL

psql_main -Atqc "SELECT jsonb_build_object(
  'source_status',r.status,
  'validation_status',(SELECT status FROM festapp_merge.validation_results WHERE run_id=r.run_id AND check_name='a-client-derived-state-rebuild'),
  'public_scopes',(SELECT count(*) FROM public.client_sync_scopes),
  'private_scopes',(SELECT count(*) FROM public.client_sync_private_scopes),
  'aggregate_versions',(SELECT count(*) FROM public.client_aggregate_versions),
  'dirty_keys',(SELECT count(*) FROM public.client_projection_dirty_keys),
  'audit_commits',(SELECT count(*) FROM public.client_commits WHERE source='migration.merge.client-sync-rebuild'),
  'r2_writes',0)
FROM festapp_merge.import_runs r WHERE r.source_alias='a'" >"$RUN_DIR/result.json"
chmod 0600 "$RUN_DIR/result.json"
echo "Source a client derived state rebuilt forward-only; no R2 object was written."
echo "Evidence: $RUN_DIR"
