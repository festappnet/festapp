#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
readonly SSH_TARGET="${FESTAPP_REHEARSAL_SSH_TARGET:-root@46.224.187.4}"
readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="/opt/festapp-supabase/docker"
readonly SOURCE_DATABASE="${FESTAPP_REHEARSAL_DATABASE:-postgres}"
readonly WRITER_SERVICES=(auth rest realtime storage meta functions studio)
readonly BACKUP_STARTED_EPOCH="$(date +%s)"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_BACKUP_ACK:-}" == "create-encrypted-append-only-rehearsal-backup" ]] ||
  fail "set FESTAPP_BACKUP_ACK=create-encrypted-append-only-rehearsal-backup"
[[ "${FESTAPP_BACKUP_QUIESCENCE_ACK:-}" == "writes-frozen-for-rehearsal-recovery-point" ]] ||
  fail "set FESTAPP_BACKUP_QUIESCENCE_ACK=writes-frozen-for-rehearsal-recovery-point"
[[ -n "${FESTAPP_BACKUP_OUTPUT_DIR:-}" && "$FESTAPP_BACKUP_OUTPUT_DIR" == /* ]] ||
  fail "FESTAPP_BACKUP_OUTPUT_DIR must be an absolute path outside the repository"
[[ -f "${FESTAPP_BACKUP_RECIPIENT_FILE:-}" ]] || fail "FESTAPP_BACKUP_RECIPIENT_FILE is required"
[[ "$SOURCE_DATABASE" == "postgres" || "$SOURCE_DATABASE" =~ ^festapp_rehearsal_[0-9]{14}$ ]] ||
  fail "FESTAPP_REHEARSAL_DATABASE must be postgres or a timestamped isolated rehearsal database"
case "$FESTAPP_BACKUP_OUTPUT_DIR/" in "$PROJECT_ROOT/"*) fail "backup output must be outside the repository";; esac
command -v age >/dev/null || fail "age is required"
command -v jq >/dev/null || fail "jq is required"
[[ "$(ssh -o BatchMode=yes "$SSH_TARGET" hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "unexpected rehearsal host"

readonly RUNTIME_DATABASE="$(ssh -o BatchMode=yes "$SSH_TARGET" "sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' '$COMPOSE_DIR/.env'")"
[[ "$RUNTIME_DATABASE" == "$SOURCE_DATABASE" ]] ||
  fail "active rehearsal runtime must target the backup database before write freeze"

thaw_runtime() {
  ssh -o BatchMode=yes "$SSH_TARGET" "cd '$COMPOSE_DIR' && docker compose up -d ${WRITER_SERVICES[*]} >/dev/null" || true
}
trap thaw_runtime EXIT
ssh -o BatchMode=yes "$SSH_TARGET" "cd '$COMPOSE_DIR' && docker compose stop ${WRITER_SERVICES[*]} >/dev/null"
readonly ACTIVE_CLIENTS="$(ssh -o BatchMode=yes "$SSH_TARGET" "cd '$COMPOSE_DIR' &&
  docker compose exec -T db psql -X -U postgres -d '$SOURCE_DATABASE' -Atqc \"SELECT count(*) FROM pg_stat_activity
    WHERE datname=current_database() AND backend_type='client backend' AND pid<>pg_backend_pid()\"")"
[[ "$ACTIVE_CLIENTS" == "0" ]] || fail "database still has client sessions after runtime write freeze ($ACTIVE_CLIENTS)"

readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly RUN_DIR="$FESTAPP_BACKUP_OUTPUT_DIR/$RUN_ID"
[[ ! -e "$RUN_DIR" ]] || fail "refusing to overwrite backup $RUN_DIR"
install -d -m 0700 "$RUN_DIR"

stream_remote() {
  local output="$1" remote_command="$2"
  ssh -o BatchMode=yes "$SSH_TARGET" "$remote_command" |
    age -R "$FESTAPP_BACKUP_RECIPIENT_FILE" -o "$output"
  [[ -s "$output" ]] || fail "empty encrypted artifact: $output"
  chmod 0600 "$output"
}

remote_consistency_state() {
  ssh -o BatchMode=yes "$SSH_TARGET" "cd $COMPOSE_DIR &&
    docker compose exec -T db psql -X -U postgres -d $SOURCE_DATABASE -Atqc \"SELECT concat_ws('|',
      tup_inserted,tup_updated,tup_deleted) FROM pg_stat_database WHERE datname=current_database()\";
    cd volumes/storage && find . -type f -printf '%P|%s|%T@\\n' | LC_ALL=C sort | sha256sum | awk '{print \$1}'"
}

readonly CONSISTENCY_BEFORE="$(remote_consistency_state)"

stream_remote "$RUN_DIR/postgres.dump.age" \
  "cd $COMPOSE_DIR && docker compose exec -T db pg_dump -U postgres -d $SOURCE_DATABASE -Fc"
stream_remote "$RUN_DIR/globals.sql.age" \
  "cd $COMPOSE_DIR && docker compose exec -T db pg_dumpall -U postgres --globals-only"
stream_remote "$RUN_DIR/storage.tar.age" \
  "tar -C $COMPOSE_DIR/volumes/storage -cf - ."
stream_remote "$RUN_DIR/runtime.tar.age" \
  "tar -C /opt/festapp-supabase -cf - docker/.env docker/docker-compose.yml docker/docker-compose.festapp.yml docker/docker-compose.database-target.yml docker/caddy/Caddyfile docker/volumes/functions docker/volumes/proxy"

readonly CONSISTENCY_AFTER="$(remote_consistency_state)"
[[ "$CONSISTENCY_AFTER" == "$CONSISTENCY_BEFORE" ]] ||
  fail "database or Storage changed during backup; encrypted artifacts are retained but no manifest was issued"

readonly REMOTE_STATE="$(ssh -o BatchMode=yes "$SSH_TARGET" "cd $COMPOSE_DIR &&
  docker compose exec -T db psql -X -U postgres -d $SOURCE_DATABASE -Atqc \"SELECT jsonb_build_object(
    'database_bytes',pg_database_size(current_database()),
    'auth_users',(SELECT count(*) FROM auth.users),
    'storage_objects',(SELECT count(*) FROM storage.objects),
    'public_scopes',(SELECT count(*) FROM public.client_sync_scopes),
    'validated_imports',(SELECT count(*) FROM festapp_merge.import_runs WHERE status='validated'),
    'auth_users_owner',(SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='auth.users'::regclass),
    'storage_objects_owner',(SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='storage.objects'::regclass),
    'auth_users_acl',(SELECT coalesce(relacl::text,'') FROM pg_class WHERE oid='auth.users'::regclass),
    'storage_objects_acl',(SELECT coalesce(relacl::text,'') FROM pg_class WHERE oid='storage.objects'::regclass),
    'public_occasions_acl',(SELECT coalesce(relacl::text,'') FROM pg_class WHERE oid='public.occasions'::regclass))\" | tr -d '\\n';
  find volumes/storage -type f -printf '%s\\n' | awk '{bytes+=\$1; count+=1} END {printf \"|%d|%d\",count,bytes}';
  cd volumes/storage && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{printf \"|%s\\n\",\$1}'")"
readonly DB_JSON="${REMOTE_STATE%%|*}"
readonly STORAGE_FILE_COUNT="$(cut -d'|' -f2 <<<"$REMOTE_STATE")"
readonly STORAGE_BYTES="$(cut -d'|' -f3 <<<"$REMOTE_STATE")"
readonly STORAGE_TREE_SHA256="$(cut -d'|' -f4 <<<"$REMOTE_STATE")"
readonly IMPORT_INVENTORY="$(ssh -o BatchMode=yes "$SSH_TARGET" "cd $COMPOSE_DIR &&
  docker compose exec -T db psql -X -U postgres -d $SOURCE_DATABASE -Atqc \"SELECT coalesce(jsonb_agg(jsonb_build_object(
    'source_alias',source_alias,'source_project_ref',source_project_ref,'run_id',run_id::text,
    'snapshot_at',to_char(snapshot_at AT TIME ZONE 'UTC','YYYY-MM-DD\\\"T\\\"HH24:MI:SS.US\\\"Z\\\"'),
    'source_schema_fingerprint',source_schema_fingerprint,'transformation_version',transformation_version,
    'status',status) ORDER BY source_alias),'[]'::jsonb) FROM festapp_merge.import_runs\"")"
readonly IMPORT_INVENTORY_CANONICAL="$(jq -cS . <<<"$IMPORT_INVENTORY")"
readonly IMPORT_INVENTORY_SHA256="$(printf '%s' "$IMPORT_INVENTORY_CANONICAL" | shasum -a 256 | awk '{print $1}')"
[[ "$(jq 'length' <<<"$IMPORT_INVENTORY")" == "3" && "$IMPORT_INVENTORY_SHA256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "final import inventory is incomplete or invalid"

readonly SECURITY_STATE="$(ssh -o BatchMode=yes "$SSH_TARGET" "cd $COMPOSE_DIR &&
  docker compose exec -T db psql -X -U postgres -d $SOURCE_DATABASE -Atqc \"SELECT concat_ws('|',
    encode(extensions.digest(coalesce((SELECT string_agg(entry,E'\\n' ORDER BY entry) FROM (
      SELECT concat_ws('|','role',rolname,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolcanlogin,rolreplication,rolbypassrls,coalesce(rolpassword,'')) entry FROM pg_roles
      UNION ALL SELECT concat_ws('|','member',member_role.rolname,parent_role.rolname,member.grantor::regrole::text,member.admin_option)
        FROM pg_auth_members member JOIN pg_roles member_role ON member_role.oid=member.member
        JOIN pg_roles parent_role ON parent_role.oid=member.roleid) role_entries),''),'sha256'),'hex'),
    encode(extensions.digest(coalesce((SELECT string_agg(entry,E'\\n' ORDER BY entry) FROM (
      SELECT concat_ws('|','schema',n.nspname,pg_get_userbyid(n.nspowner),coalesce((
        SELECT string_agg(concat_ws(':',grantor::regrole::text,grantee::regrole::text,privilege_type,is_grantable),','
          ORDER BY grantor,grantee,privilege_type,is_grantable) FROM aclexplode(n.nspacl)
          WHERE grantee<>n.nspowner),'')) entry
        FROM pg_namespace n WHERE n.nspname IN ('public','eshop','auth','storage','realtime','_realtime','supabase_functions','graphql','graphql_public','extensions','vault')
      UNION ALL SELECT concat_ws('|','relation',n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner),coalesce((
        SELECT string_agg(concat_ws(':',grantor::regrole::text,grantee::regrole::text,privilege_type,is_grantable),','
          ORDER BY grantor,grantee,privilege_type,is_grantable) FROM aclexplode(c.relacl)
          WHERE grantee<>c.relowner),''))
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','eshop','auth','storage','realtime','_realtime','supabase_functions','graphql','graphql_public','extensions','vault')
      UNION ALL SELECT concat_ws('|','function',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),p.prokind,pg_get_userbyid(p.proowner),coalesce((
        SELECT string_agg(concat_ws(':',grantor::regrole::text,grantee::regrole::text,privilege_type,is_grantable),','
          ORDER BY grantor,grantee,privilege_type,is_grantable) FROM aclexplode(p.proacl)
          WHERE grantee<>p.proowner),''))
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname IN ('public','eshop','auth','storage','realtime','_realtime','supabase_functions','graphql','graphql_public','extensions','vault')
          AND NOT (n.nspname='extensions' AND p.proname='grant_pg_cron_access')) object_entries),''),'sha256'),'hex'))\"")"
readonly ROLE_SECURITY_SHA256="${SECURITY_STATE%%|*}"
readonly OBJECT_SECURITY_SHA256="${SECURITY_STATE#*|}"
[[ "$ROLE_SECURITY_SHA256" =~ ^[0-9a-f]{64}$ && "$OBJECT_SECURITY_SHA256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "normalized role/object security inventory is invalid"

thaw_runtime
trap - EXIT
readonly UNHEALTHY_SERVICES="$(ssh -o BatchMode=yes "$SSH_TARGET" "cd '$COMPOSE_DIR';
  for attempt in \$(seq 1 30); do
    unhealthy=\$(docker compose ps --format json ${WRITER_SERVICES[*]} | jq -s 'map(select(.State != \"running\" or (.Health != \"\" and .Health != \"healthy\"))) | length');
    [ \"\$unhealthy\" = 0 ] && break; sleep 2; done; printf '%s' \"\$unhealthy\"")"
[[ "$UNHEALTHY_SERVICES" == "0" ]] || fail "runtime services did not recover after backup freeze"

jq -n \
  --arg runId "$RUN_ID" --arg sourceHost "$EXPECTED_HOSTNAME" --arg sourceDatabase "$SOURCE_DATABASE" --arg createdAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson database "$DB_JSON" --argjson storageFiles "$STORAGE_FILE_COUNT" --argjson storageBytes "$STORAGE_BYTES" \
  --arg storageTreeSha "$STORAGE_TREE_SHA256" \
  --arg roleSecuritySha "$ROLE_SECURITY_SHA256" --arg objectSecuritySha "$OBJECT_SECURITY_SHA256" \
  --argjson importInventory "$IMPORT_INVENTORY" --arg importInventorySha "$IMPORT_INVENTORY_SHA256" \
  --argjson durationSeconds "$(( $(date +%s) - BACKUP_STARTED_EPOCH ))" \
  --arg postgresSha "$(shasum -a 256 "$RUN_DIR/postgres.dump.age" | awk '{print $1}')" \
  --arg globalsSha "$(shasum -a 256 "$RUN_DIR/globals.sql.age" | awk '{print $1}')" \
  --arg storageSha "$(shasum -a 256 "$RUN_DIR/storage.tar.age" | awk '{print $1}')" \
  --arg runtimeSha "$(shasum -a 256 "$RUN_DIR/runtime.tar.age" | awk '{print $1}')" \
  '{version:3,run_id:$runId,created_at:$createdAt,source_host:$sourceHost,source_database:$sourceDatabase,
    encrypted:true,plaintext_artifacts_written:false,cloud_sources_mutated:false,writes_frozen:true,
    consistency_check:"runtime-stopped-zero-client-sessions-and-before-after-state-stable",rpo_seconds:0,backup_duration_seconds:$durationSeconds,
    role_security_sha256:$roleSecuritySha,object_security_sha256:$objectSecuritySha,database:$database,
    import_inventory:$importInventory,import_inventory_sha256:$importInventorySha,
    storage:{files:$storageFiles,bytes:$storageBytes,tree_sha256:$storageTreeSha},
    artifacts:{postgres_dump:{file:"postgres.dump.age",sha256:$postgresSha},globals:{file:"globals.sql.age",sha256:$globalsSha},storage:{file:"storage.tar.age",sha256:$storageSha},runtime:{file:"runtime.tar.age",sha256:$runtimeSha}}}' \
  >"$RUN_DIR/manifest.json"
chmod 0600 "$RUN_DIR/manifest.json"

echo "Encrypted append-only rehearsal backup created: $RUN_DIR"
