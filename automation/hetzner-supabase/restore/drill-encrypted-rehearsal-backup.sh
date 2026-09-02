#!/usr/bin/env bash
set -euo pipefail

readonly SSH_TARGET="${FESTAPP_REHEARSAL_SSH_TARGET:-root@46.224.187.4}"
readonly EXPECTED_HOSTNAME="festapp-supabase-rehearsal-01"
readonly COMPOSE_DIR="/opt/festapp-supabase/docker"
readonly RESTORE_STARTED_EPOCH="$(date +%s)"

fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_RESTORE_ACK:-}" == "restore-encrypted-backup-into-new-isolated-target" ]] ||
  fail "set FESTAPP_RESTORE_ACK=restore-encrypted-backup-into-new-isolated-target"
[[ -d "${FESTAPP_BACKUP_RUN_DIR:-}" ]] || fail "FESTAPP_BACKUP_RUN_DIR is required"
[[ -f "${FESTAPP_BACKUP_IDENTITY_FILE:-}" ]] || fail "FESTAPP_BACKUP_IDENTITY_FILE is required"
command -v age >/dev/null || fail "age is required"
command -v jq >/dev/null || fail "jq is required"
[[ "$(ssh -o BatchMode=yes "$SSH_TARGET" hostname -s)" == "$EXPECTED_HOSTNAME" ]] || fail "unexpected rehearsal host"

readonly MANIFEST="$FESTAPP_BACKUP_RUN_DIR/manifest.json"
[[ -f "$MANIFEST" ]] || fail "backup manifest is missing"
[[ "$(jq -r '[.version,.writes_frozen,.consistency_check,(.storage.tree_sha256|test("^[0-9a-f]{64}$")),(.role_security_sha256|test("^[0-9a-f]{64}$")),(.object_security_sha256|test("^[0-9a-f]{64}$")),(.import_inventory_sha256|test("^[0-9a-f]{64}$"))]|join("|")' "$MANIFEST")" == "3|true|runtime-stopped-zero-client-sessions-and-before-after-state-stable|true|true|true|true" ]] ||
  fail "backup manifest does not satisfy the coordinated recovery-point contract"
for artifact in postgres.dump.age globals.sql.age storage.tar.age runtime.tar.age; do
  [[ -f "$FESTAPP_BACKUP_RUN_DIR/$artifact" ]] || fail "missing $artifact"
done
for item in postgres_dump globals storage runtime; do
  readonly_file="$(jq -r ".artifacts.$item.file" "$MANIFEST")"
  expected="$(jq -r ".artifacts.$item.sha256" "$MANIFEST")"
  observed="$(shasum -a 256 "$FESTAPP_BACKUP_RUN_DIR/$readonly_file" | awk '{print $1}')"
  [[ "$observed" == "$expected" ]] || fail "encrypted artifact checksum mismatch: $readonly_file"
done

readonly RUN_ID="$(jq -r .run_id "$MANIFEST")"
[[ "$RUN_ID" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "invalid backup run id"
readonly ATTEMPT_ID="$RUN_ID-$(date -u +%Y%m%dT%H%M%SZ)"
readonly TARGET_DB="festapp_restore_${ATTEMPT_ID//[^0-9]/}"
readonly CLEAN_CONTAINER="festapp-restore-cluster-${ATTEMPT_ID//[^0-9]/}"
readonly REMOTE_ROOT="/var/lib/festapp-restore-drills/$ATTEMPT_ID"
readonly EVIDENCE_ROOT="/var/lib/festapp-rehearsal-evidence/restore-drill-$ATTEMPT_ID"
readonly LOCAL_EVIDENCE_ROOT="${FESTAPP_RESTORE_LOCAL_EVIDENCE_ROOT:-/tmp/festapp-restore-evidence}/$ATTEMPT_ID"
readonly RESTORE_LIST="$LOCAL_EVIDENCE_ROOT/restore.list"
[[ ! -e "$LOCAL_EVIDENCE_ROOT" ]] || fail "local restore evidence already exists"
install -d -m 0700 "$LOCAL_EVIDENCE_ROOT"

# pg_cron is intentionally installed only in the live `postgres` database on
# this cluster. An isolated drill database cannot create it; exclude only the
# extension and its comment from the otherwise complete archive list.
pg_restore --list < <(age -d -i "$FESTAPP_BACKUP_IDENTITY_FILE" "$FESTAPP_BACKUP_RUN_DIR/postgres.dump.age") |
  awk '/EXTENSION - pg_cron|COMMENT - EXTENSION pg_cron|TABLE DATA cron |SEQUENCE SET cron |FUNCTION extensions grant_pg_cron_access|COMMENT extensions FUNCTION grant_pg_cron_access|EVENT TRIGGER - issue_pg_cron_access/{print ";" $0; next} {print}' >"$RESTORE_LIST"
chmod 0600 "$RESTORE_LIST"

readonly DB_IMAGE="$(ssh -o BatchMode=yes "$SSH_TARGET" "docker inspect -f '{{.Config.Image}}' supabase-db")"
[[ "$DB_IMAGE" == supabase/postgres:* ]] || fail "running database image is not an approved Supabase PostgreSQL image"
readonly CLEAN_EXISTS="$(ssh -o BatchMode=yes "$SSH_TARGET" "docker container inspect '$CLEAN_CONTAINER' >/dev/null 2>&1; printf '%s' \$?")"
[[ "$CLEAN_EXISTS" != "0" ]] || fail "clean restore cluster already exists"
ssh -o BatchMode=yes "$SSH_TARGET" "test ! -e '$REMOTE_ROOT' && install -d -o root -g root -m 0700 '$REMOTE_ROOT/storage' '$REMOTE_ROOT/runtime' '$REMOTE_ROOT/pgdata' '$EVIDENCE_ROOT'"
ssh -o BatchMode=yes "$SSH_TARGET" "docker run -d --name '$CLEAN_CONTAINER' --network none \
  -e POSTGRES_PASSWORD=festapp-isolated-restore-only -e POSTGRES_HOST_AUTH_METHOD=trust \
  -v '$REMOTE_ROOT/pgdata:/var/lib/postgresql/data' '$DB_IMAGE' >/dev/null"
stop_clean_cluster() { ssh -o BatchMode=yes "$SSH_TARGET" "docker stop '$CLEAN_CONTAINER' >/dev/null" || true; }
trap stop_clean_cluster EXIT
readonly CLEAN_READY="$(ssh -o BatchMode=yes "$SSH_TARGET" "for attempt in \$(seq 1 60); do
  docker exec '$CLEAN_CONTAINER' psql -X -U supabase_admin -d postgres -Atqc 'SELECT 1' >/dev/null 2>&1 && { printf ready; exit; }; sleep 1; done; printf failed")"
[[ "$CLEAN_READY" == "ready" ]] || fail "clean PostgreSQL restore cluster did not become ready"

# The image foundation can already contain standard Supabase roles. pg_dumpall
# therefore reports harmless duplicate CREATE ROLE errors, while subsequent
# ALTER ROLE and GRANT statements restore the exact attributes, password hashes
# and memberships; the complete role digest below is the fail-closed proof.
age -d -i "$FESTAPP_BACKUP_IDENTITY_FILE" "$FESTAPP_BACKUP_RUN_DIR/globals.sql.age" |
  ssh -o BatchMode=yes "$SSH_TARGET" "docker exec -i '$CLEAN_CONTAINER' psql -X -U supabase_admin -d postgres >/dev/null 2>&1"
ssh -o BatchMode=yes "$SSH_TARGET" "docker exec '$CLEAN_CONTAINER' createdb -U supabase_admin -O supabase_admin '$TARGET_DB'"
ssh -o BatchMode=yes "$SSH_TARGET" "docker exec -i '$CLEAN_CONTAINER' sh -c 'umask 077; tee /tmp/$TARGET_DB.restore.list >/dev/null'" <"$RESTORE_LIST"

age -d -i "$FESTAPP_BACKUP_IDENTITY_FILE" "$FESTAPP_BACKUP_RUN_DIR/postgres.dump.age" |
  ssh -o BatchMode=yes "$SSH_TARGET" "docker exec -i '$CLEAN_CONTAINER' pg_restore -U supabase_admin -d '$TARGET_DB' --exit-on-error -L /tmp/$TARGET_DB.restore.list"
age -d -i "$FESTAPP_BACKUP_IDENTITY_FILE" "$FESTAPP_BACKUP_RUN_DIR/storage.tar.age" |
  ssh -o BatchMode=yes "$SSH_TARGET" "tar -C '$REMOTE_ROOT/storage' -xf -"
age -d -i "$FESTAPP_BACKUP_IDENTITY_FILE" "$FESTAPP_BACKUP_RUN_DIR/runtime.tar.age" |
  ssh -o BatchMode=yes "$SSH_TARGET" "tar -C '$REMOTE_ROOT/runtime' -xf -"

ssh -o BatchMode=yes "$SSH_TARGET" "set -eu
  cd '$REMOTE_ROOT/runtime/docker'
  docker compose config -q
  docker exec -i festapp-caddy caddy validate --adapter caddyfile --config - <caddy/Caddyfile >/dev/null"

readonly OBSERVED="$(ssh -o BatchMode=yes "$SSH_TARGET" "docker exec '$CLEAN_CONTAINER' psql -X -U postgres -d '$TARGET_DB' -Atqc \"SELECT jsonb_build_object(
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
  find '$REMOTE_ROOT/storage' -type f -printf '%s\\n' | awk '{bytes+=\$1; count+=1} END {printf \"|%d|%d\",count,bytes}';
  cd '$REMOTE_ROOT/storage' && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | awk '{printf \"|%s\\n\",\$1}'")"
readonly OBSERVED_DB="${OBSERVED%%|*}"
readonly OBSERVED_FILES="$(cut -d'|' -f2 <<<"$OBSERVED")"
readonly OBSERVED_BYTES="$(cut -d'|' -f3 <<<"$OBSERVED")"
readonly OBSERVED_TREE_SHA256="$(cut -d'|' -f4 <<<"$OBSERVED")"
readonly OBSERVED_IMPORT_INVENTORY="$(ssh -o BatchMode=yes "$SSH_TARGET" "docker exec '$CLEAN_CONTAINER' psql -X -U postgres -d '$TARGET_DB' -Atqc \"SELECT coalesce(jsonb_agg(jsonb_build_object(
  'source_alias',source_alias,'source_project_ref',source_project_ref,'run_id',run_id::text,
  'snapshot_at',to_char(snapshot_at AT TIME ZONE 'UTC','YYYY-MM-DD\\\"T\\\"HH24:MI:SS.US\\\"Z\\\"'),
  'source_schema_fingerprint',source_schema_fingerprint,'transformation_version',transformation_version,
  'status',status) ORDER BY source_alias),'[]'::jsonb) FROM festapp_merge.import_runs\"")"
readonly OBSERVED_IMPORT_CANONICAL="$(jq -cS . <<<"$OBSERVED_IMPORT_INVENTORY")"
readonly OBSERVED_IMPORT_SHA256="$(printf '%s' "$OBSERVED_IMPORT_CANONICAL" | shasum -a 256 | awk '{print $1}')"

readonly OBSERVED_SECURITY="$(ssh -o BatchMode=yes "$SSH_TARGET" "docker exec '$CLEAN_CONTAINER' psql -X -U postgres -d '$TARGET_DB' -Atqc \"SELECT concat_ws('|',
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
readonly OBSERVED_ROLE_SECURITY_SHA256="${OBSERVED_SECURITY%%|*}"
readonly OBSERVED_OBJECT_SECURITY_SHA256="${OBSERVED_SECURITY#*|}"
readonly RESTORE_DURATION_SECONDS="$(( $(date +%s) - RESTORE_STARTED_EPOCH ))"

for key in auth_users storage_objects public_scopes validated_imports auth_users_owner storage_objects_owner auth_users_acl storage_objects_acl public_occasions_acl; do
  [[ "$(jq -r ".$key" <<<"$OBSERVED_DB")" == "$(jq -r ".database.$key" "$MANIFEST")" ]] || fail "restore mismatch: $key"
done
[[ "$OBSERVED_FILES" == "$(jq -r .storage.files "$MANIFEST")" ]] || fail "restored Storage file-count mismatch"
[[ "$OBSERVED_BYTES" == "$(jq -r .storage.bytes "$MANIFEST")" ]] || fail "restored Storage byte-count mismatch"
[[ "$OBSERVED_TREE_SHA256" == "$(jq -r .storage.tree_sha256 "$MANIFEST")" ]] || fail "restored Storage tree checksum mismatch"
[[ "$OBSERVED_ROLE_SECURITY_SHA256" == "$(jq -r .role_security_sha256 "$MANIFEST")" ]] || fail "restored role security inventory mismatch"
[[ "$OBSERVED_OBJECT_SECURITY_SHA256" == "$(jq -r .object_security_sha256 "$MANIFEST")" ]] || fail "restored object ownership/ACL inventory mismatch"
[[ "$OBSERVED_IMPORT_CANONICAL" == "$(jq -cS .import_inventory "$MANIFEST")" &&
   "$OBSERVED_IMPORT_SHA256" == "$(jq -r .import_inventory_sha256 "$MANIFEST")" ]] ||
  fail "restored import inventory differs from the promotion backup"

stop_clean_cluster
trap - EXIT

jq -n --arg runId "$RUN_ID" --arg attemptId "$ATTEMPT_ID" --arg targetDatabase "$TARGET_DB" --arg storagePath "$REMOTE_ROOT/storage" \
  --argjson database "$OBSERVED_DB" --argjson storageFiles "$OBSERVED_FILES" --argjson storageBytes "$OBSERVED_BYTES" --arg storageTreeSha "$OBSERVED_TREE_SHA256" \
  --arg roleSecuritySha "$OBSERVED_ROLE_SECURITY_SHA256" --arg objectSecuritySha "$OBSERVED_OBJECT_SECURITY_SHA256" \
  --argjson importInventory "$OBSERVED_IMPORT_INVENTORY" --arg importInventorySha "$OBSERVED_IMPORT_SHA256" \
  --argjson restoreDurationSeconds "$RESTORE_DURATION_SECONDS" --arg cleanContainer "$CLEAN_CONTAINER" \
  '{version:1,run_id:$runId,attempt_id:$attemptId,status:"pass",target_database:$targetDatabase,storage_path:$storagePath,
    database:$database,storage:{files:$storageFiles,bytes:$storageBytes,tree_sha256:$storageTreeSha},
    role_security_sha256:$roleSecuritySha,object_security_sha256:$objectSecuritySha,
    import_inventory:$importInventory,import_inventory_sha256:$importInventorySha,
    rpo_seconds:0,rto_seconds:$restoreDurationSeconds,clean_cluster_container:$cleanContainer,clean_cluster_stopped:true,
    globals_restored:true,runtime_config_validated:true,
    ownership_acl_equivalence:true,production_target_mutated:false,
    cluster_extension_exceptions:["pg_cron extension-owned objects are confined to the live postgres database"],cloud_sources_mutated:false,deleted_paths:[]}' |
  ssh -o BatchMode=yes "$SSH_TARGET" "umask 077; tee '$EVIDENCE_ROOT/result.json' >/dev/null"

echo "Encrypted restore drill passed: database=$TARGET_DB storage=$REMOTE_ROOT/storage"
