#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/build-canonical-schema.sh"
readonly STAGING_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/prepare-merge-staging.sh"
readonly SOURCE_DATABASE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/prepare-source-staging-databases.sh"
readonly FOREIGN_BRIDGE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/prepare-foreign-staging-bridge.sh"
readonly DEFAULT_IMPORT_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-default-canonical.sh"
readonly DEFAULT_MANAGED_IMPORT_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-default-managed.sh"
readonly DEFAULT_AUTH_VALIDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-default-auth-continuity.sh"
readonly STORAGE_RECEIVER_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/storage-file-receiver.cjs"
readonly STORAGE_COPY_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/merge/copy-storage-payloads.mjs"
readonly STORAGE_EVIDENCE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/merge/record-storage-payload-evidence.mjs"
readonly MANAGED_STAGE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/merge/stage-managed-export.mjs"
readonly A_MAPPING_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/prepare-a-id-mappings.sh"
readonly A_IMPORT_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-a-canonical.sh"
readonly A_AUTH_IMPORT_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-a-auth.sh"
readonly A_STORAGE_IMPORT_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-a-storage-metadata.sh"
readonly A_DERIVED_REBUILD_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/rebuild-a-client-derived-state.sh"
readonly MERGED_DERIVED_VALIDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-merged-client-derived-state.sh"
readonly DEFAULT_COMPANION_VALIDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-default-companion-quarantine.sh"
readonly A_SEMANTIC_REPAIR_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/repair-a-semantic-references.sh"
readonly A_PAYLOAD_REPAIR_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/repair-a-embedded-payloads.sh"
readonly A_OPERATIONAL_REPAIR_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/repair-a-operational-references.sh"
readonly A_REFERENCE_VALIDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-a-reference-registry.sh"
readonly A_IDENTITY_VALIDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-a-identity-merge.sh"
readonly MERGE_SOURCE_STORAGE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/import-merge-source-storage-metadata.sh"
readonly MERGE_SOURCE_INTEGRITY_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/validate-merge-source-integrity.sh"
readonly MERGE_SOURCE_CLIENT_STATE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/rebuild-and-validate-merge-source-client-state.sh"
readonly ISOLATED_FOUNDATION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/rehearsal/prepare-isolated-target-database.sh"
readonly ENCRYPTED_BACKUP_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/backup/create-encrypted-rehearsal-backup.sh"
readonly ENCRYPTED_RESTORE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/restore/drill-encrypted-rehearsal-backup.sh"
readonly RUNTIME_COMPOSE="$PROJECT_ROOT/automation/hetzner-supabase/runtime/docker-compose.festapp.yml"
readonly RUNTIME_CADDYFILE="$PROJECT_ROOT/automation/hetzner-supabase/runtime/Caddyfile"
readonly RUNTIME_CONFIGURATOR="$PROJECT_ROOT/automation/hetzner-supabase/runtime/configure-rehearsal-env.py"
readonly RUNTIME_DATABASE_COMPOSE="$PROJECT_ROOT/automation/hetzner-supabase/runtime/docker-compose.database-target.yml"
readonly RUNTIME_SWITCH_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/runtime/switch-rehearsal-runtime-database.sh"
readonly RUNTIME_PROMOTION_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/runtime/promote-production-runtime.sh"
readonly RUNTIME_PROMOTION_VALIDATOR="$PROJECT_ROOT/automation/hetzner-supabase/runtime/validate-production-promotion.mjs"
readonly RUNTIME_UPGRADE_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/runtime/upgrade-installed-production-runtime.sh"
readonly RUNTIME_DEPLOY_SCRIPT="$PROJECT_ROOT/automation/hetzner-supabase/runtime/deploy-rehearsal.sh"
readonly TERRAFORM_FIREWALL="$PROJECT_ROOT/automation/hetzner-supabase/terraform/firewall.tf"

[[ -x "$SCRIPT" ]] || { echo "rehearsal schema builder must be executable" >&2; exit 1; }
[[ -x "$STAGING_SCRIPT" ]] || { echo "merge staging builder must be executable" >&2; exit 1; }
[[ -x "$SOURCE_DATABASE_SCRIPT" ]] || { echo "source staging database builder must be executable" >&2; exit 1; }
[[ -x "$FOREIGN_BRIDGE_SCRIPT" ]] || { echo "foreign staging bridge builder must be executable" >&2; exit 1; }
[[ -x "$DEFAULT_IMPORT_SCRIPT" ]] || { echo "default canonical importer must be executable" >&2; exit 1; }
[[ -x "$DEFAULT_MANAGED_IMPORT_SCRIPT" ]] || { echo "default managed importer must be executable" >&2; exit 1; }
[[ -x "$DEFAULT_AUTH_VALIDATION_SCRIPT" ]] || { echo "default Auth validator must be executable" >&2; exit 1; }
[[ -r "$STORAGE_RECEIVER_SCRIPT" ]] || { echo "Storage receiver must be readable" >&2; exit 1; }
[[ -x "$STORAGE_COPY_SCRIPT" ]] || { echo "Storage payload copier must be executable" >&2; exit 1; }
[[ -x "$STORAGE_EVIDENCE_SCRIPT" ]] || { echo "Storage evidence recorder must be executable" >&2; exit 1; }
[[ -x "$MANAGED_STAGE_SCRIPT" ]] || { echo "managed staging loader must be executable" >&2; exit 1; }
[[ -x "$A_MAPPING_SCRIPT" ]] || { echo "source a mapping preparer must be executable" >&2; exit 1; }
[[ -x "$A_IMPORT_SCRIPT" ]] || { echo "source a canonical importer must be executable" >&2; exit 1; }
[[ -x "$A_AUTH_IMPORT_SCRIPT" ]] || { echo "source a Auth importer must be executable" >&2; exit 1; }
[[ -x "$A_STORAGE_IMPORT_SCRIPT" ]] || { echo "source a Storage metadata importer must be executable" >&2; exit 1; }
[[ -x "$A_DERIVED_REBUILD_SCRIPT" ]] || { echo "source a derived-state rebuilder must be executable" >&2; exit 1; }
[[ -x "$MERGED_DERIVED_VALIDATION_SCRIPT" ]] || { echo "merged derived-state validator must be executable" >&2; exit 1; }
[[ -x "$DEFAULT_COMPANION_VALIDATION_SCRIPT" ]] || { echo "default companion validator must be executable" >&2; exit 1; }
[[ -x "$A_SEMANTIC_REPAIR_SCRIPT" ]] || { echo "semantic reference repair must be executable" >&2; exit 1; }
[[ -x "$A_PAYLOAD_REPAIR_SCRIPT" ]] || { echo "embedded payload repair must be executable" >&2; exit 1; }
[[ -x "$A_OPERATIONAL_REPAIR_SCRIPT" ]] || { echo "operational reference repair must be executable" >&2; exit 1; }
[[ -x "$A_REFERENCE_VALIDATION_SCRIPT" ]] || { echo "reference registry validator must be executable" >&2; exit 1; }
[[ -x "$A_IDENTITY_VALIDATION_SCRIPT" ]] || { echo "identity merge validator must be executable" >&2; exit 1; }
[[ -x "$MERGE_SOURCE_STORAGE_SCRIPT" ]] || { echo "generic merge-source Storage importer must be executable" >&2; exit 1; }
[[ -x "$MERGE_SOURCE_INTEGRITY_SCRIPT" ]] || { echo "generic merge-source integrity validator must be executable" >&2; exit 1; }
[[ -x "$MERGE_SOURCE_CLIENT_STATE_SCRIPT" ]] || { echo "generic merge-source client-state validator must be executable" >&2; exit 1; }
[[ -x "$ISOLATED_FOUNDATION_SCRIPT" ]] || { echo "isolated foundation builder must be executable" >&2; exit 1; }
[[ -x "$ENCRYPTED_BACKUP_SCRIPT" ]] || { echo "encrypted backup script must be executable" >&2; exit 1; }
[[ -x "$ENCRYPTED_RESTORE_SCRIPT" ]] || { echo "encrypted restore drill must be executable" >&2; exit 1; }
[[ -r "$RUNTIME_CADDYFILE" ]] || { echo "Caddy origin configuration must be readable" >&2; exit 1; }
[[ -r "$RUNTIME_DATABASE_COMPOSE" ]] || { echo "database target Compose override must be readable" >&2; exit 1; }
[[ -x "$RUNTIME_SWITCH_SCRIPT" ]] || { echo "runtime database switch must be executable" >&2; exit 1; }
[[ -x "$RUNTIME_PROMOTION_SCRIPT" && -x "$RUNTIME_PROMOTION_VALIDATOR" && -x "$RUNTIME_UPGRADE_SCRIPT" ]] || {
  echo "production runtime promotion tooling must be executable" >&2; exit 1;
}

for required in 'caddy:' 'network_mode: host' NET_BIND_SERVICE 'read_only: true' \
  'rehearsal-api.festapp.net'; do
  rg -Fq "$required" "$RUNTIME_COMPOSE" || { echo "missing public-origin contract $required in $RUNTIME_COMPOSE" >&2; exit 1; }
done
for required in FESTAPP_SUPABASE_SITE_ADDRESSES trusted_proxies_strict CF-Connecting-IP \
  'reverse_proxy 127.0.0.1:8000'; do
  rg -Fq "$required" "$RUNTIME_CADDYFILE" || { echo "missing public-origin contract $required in $RUNTIME_CADDYFILE" >&2; exit 1; }
done
for required in FESTAPP_SUPABASE_HOSTNAME FESTAPP_SUPABASE_SITE_ADDRESSES \
  'https://rehearsal-api.festapp.net' \
  API_EXTERNAL_URL SUPABASE_PUBLIC_URL; do
  rg -Fq "$required" "$RUNTIME_CONFIGURATOR" || { echo "missing public-origin contract $required in $RUNTIME_CONFIGURATOR" >&2; exit 1; }
done
for required in cloudflare_proxy_cidrs '173.245.48.0/20' '2c0f:f248::/32' \
  local.cloudflare_proxy_cidrs; do
  rg -Fq "$required" "$TERRAFORM_FIREWALL" || { echo "missing public-origin contract $required in $TERRAFORM_FIREWALL" >&2; exit 1; }
done

if sed -n '/port        = "80"/,/}/p; /port        = "443"/,/}/p' "$TERRAFORM_FIREWALL" | \
    rg -q '0\.0\.0\.0/0|::/0'; then
  echo "public Supabase ports must not allow direct Internet ingress" >&2
  exit 1
fi

for required in \
  'FESTAPP_REHEARSAL_ACK' \
  'resume-after-baseline-ledger-fix' \
  '0|0|0|t|t|t|113|38' \
  'festapp-supabase-rehearsal-01' \
  'EXPECTED_POSTGRES_MAJOR="17"' \
  'target is not an empty business-schema foundation' \
  'pg_dump -U postgres -d "$TARGET_DATABASE" --schema-only' \
  'auth_users' \
  'storage_objects'; do
  rg -Fq "$required" "$SCRIPT" || { echo "missing safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$SCRIPT"; then
  echo "rehearsal schema builder contains a destructive statement" >&2
  exit 1
fi

for required in \
  'prepare-empty-private-merge-staging' \
  'festapp-supabase-rehearsal-01' \
  'EXPECTED_POSTGRES_MAJOR="17"' \
  'EXPECTED_MIGRATION_COUNT="101"' \
  "to_regnamespace('festapp_merge') IS NULL" \
  'CREATE SCHEMA festapp_merge AUTHORIZATION postgres' \
  'CREATE TABLE festapp_merge.quarantined_rows' \
  "decision IN ('repair', 'omit-with-ledger')" \
  'REVOKE ALL ON SCHEMA festapp_merge FROM PUBLIC, anon, authenticated, service_role' \
  "'rows'" \
  "'auth_users'" \
  "'storage_objects'"; do
  rg -Fq "$required" "$STAGING_SCRIPT" || { echo "missing staging safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$STAGING_SCRIPT"; then
  echo "merge staging builder contains a destructive statement" >&2
  exit 1
fi

for required in \
  'prepare-empty-source-staging-databases' \
  'prepare-additive-source-staging-databases' \
  'source-registry.json' \
  'FESTAPP_STAGE_SOURCES' \
  'festapp-supabase-rehearsal-01' \
  'festapp_stage_${source}' \
  'CREATE DATABASE %I TEMPLATE template0' \
  'REVOKE ALL ON DATABASE %I FROM PUBLIC, anon, authenticated, service_role' \
  'CREATE SCHEMA vault AUTHORIZATION postgres' \
  'CREATE FUNCTION auth.uid() RETURNS uuid' \
  'existing canonical imports are not the exact validated predecessor set'; do
  rg -Fq "$required" "$SOURCE_DATABASE_SCRIPT" || { echo "missing source staging safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$SOURCE_DATABASE_SCRIPT"; then
  echo "source staging database builder contains a destructive statement" >&2
  exit 1
fi

for required in \
  'prepare-read-only-foreign-staging-bridge' \
  'prepare-additive-read-only-foreign-staging-bridge' \
  'source-registry.json' \
  'festapp_stage_reader_${SOURCES[0]}' \
  'VALID UNTIL' \
  'NOBYPASSRLS' \
  'GRANT SELECT ON ALL TABLES IN SCHEMA public, eshop, festapp_managed_source' \
  'CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA extensions' \
  "OPTIONS (host 'db',port '5432'" \
  'LIMIT TO (rows,provenance)' \
  'IMPORT FOREIGN SCHEMA public FROM SERVER festapp_stage_${source}' \
  'pre-existing FDW topology changed' \
  'rolbypassrls'; do
  rg -Fq "$required" "$FOREIGN_BRIDGE_SCRIPT" || { echo "missing foreign bridge safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$FOREIGN_BRIDGE_SCRIPT"; then
  echo "foreign staging bridge contains a destructive statement" >&2
  exit 1
fi

for required in \
  'import-default-with-quarantine-ledger' \
  'session_replication_role = replica' \
  'OVERRIDING SYSTEM VALUE' \
  'zero-common-occasion-legacy-orphan' \
  'imported_companions + quarantined_companions <> source_companions' \
  'festapp_stage_default_managed.provenance' \
  "SET status='blocked'" \
  "'auth-and-storage-import', 'blocked'"; do
  rg -Fq "$required" "$DEFAULT_IMPORT_SCRIPT" || { echo "missing default import safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$DEFAULT_IMPORT_SCRIPT"; then
  echo "default canonical importer contains a destructive statement" >&2
  exit 1
fi

for required in \
  'import-default-auth-and-storage-metadata' \
  'EXPECTED_AUTH_MIGRATIONS="76"' \
  'EXPECTED_STORAGE_MIGRATIONS="61"' \
  "NOT IN (('auth','schema_migrations'),('storage','migrations'))" \
  'session_replication_role = replica' \
  'jsonb_populate_record' \
  'default-managed-foreign-keys' \
  "'default-storage-object-payloads','blocked'" \
  "'object_payloads_copied',false"; do
  rg -Fq "$required" "$DEFAULT_MANAGED_IMPORT_SCRIPT" || { echo "missing default managed import safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$DEFAULT_MANAGED_IMPORT_SCRIPT"; then
  echo "default managed importer contains a destructive statement" >&2
  exit 1
fi

for required in \
  'validate-default-auth-credential-continuity' \
  'changed_password_hashes' \
  'changed_refresh_tokens' \
  "'default-auth-credential-continuity','pass'" \
  'without exposing credentials'; do
  rg -Fq "$required" "$DEFAULT_AUTH_VALIDATION_SCRIPT" || { echo "missing default Auth validation contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$DEFAULT_AUTH_VALIDATION_SCRIPT"; then
  echo "default Auth validator contains a destructive statement" >&2
  exit 1
fi

for required in \
  'resolveSecurePath' \
  'withOptionalVersion' \
  'GLOBAL_S3_BUCKET' \
  'TENANT_ID' \
  'const backendKey = `${tenantId}/${bucket}/${name}`' \
  'fs.existsSync' \
  'drain source for resumable verification' \
  'backend.headObject'; do
  rg -Fq "$required" "$STORAGE_RECEIVER_SCRIPT" || { echo "missing Storage receiver safety contract: $required" >&2; exit 1; }
done

for required in \
  'CONCURRENCY = 4' \
  'Storage artifact checksum mismatch' \
  'legacy service_role key is unavailable' \
  'Storage payload MD5 differs from snapshot metadata' \
  'cloud_source_mutated: false' \
  'cloudflare_in_path: false' \
  'target must be the approved rehearsal host' \
  'installAndVerifyReceiver' \
  'refusing to overwrite Storage evidence'; do
  rg -Fq "$required" "$STORAGE_COPY_SCRIPT" || { echo "missing Storage copy safety contract: $required" >&2; exit 1; }
done

for required in source_manifest_file_sha256 ordered_descriptor_sha256 source_artifact_sha256; do
  rg -Fq "$required" "$STORAGE_COPY_SCRIPT" || { echo "missing Storage provenance contract: $required" >&2; exit 1; }
done
for required in 'readManagedDescriptors' 'SOURCE_REGISTRY' 'sourceIndex' \
  'source_artifact_sha256' 'GET DIAGNOSTICS changed=ROW_COUNT' \
  'Storage evidence descriptors differ from the encrypted managed artifact' \
  'verifyTargetPayloads' 'verifySourcePayloads' 'FESTAPP_STORAGE_VERIFY_ONLY=1' \
  'independently hashed source/target payloads' 'snapshot_time_content_proof_requires_final_source_freeze'; do
  rg -Fq "$required" "$STORAGE_EVIDENCE_SCRIPT" || { echo "missing Storage evidence recorder contract: $required" >&2; exit 1; }
done
for required in 'RAW.dump.age' 'raw_artifact_sha256' 'raw_schema_sha256' 'managed_artifact_sha256' \
  'source manifest content checksum mismatch' 'CREATE TABLE festapp_managed_source.provenance' \
  'same private snapshot directory' 'approved bounded export window' 'raw_managed_delta_seconds'; do
  rg -Fq "$required" "$MANAGED_STAGE_SCRIPT" || { echo "missing managed provenance contract: $required" >&2; exit 1; }
done

for required in 'Source DDL may reference auth.uid()' 'always-NULL compatibility stub' 'API roles cannot execute it'; do
  rg -Fq "$required" "$SOURCE_DATABASE_SCRIPT" || { echo "missing isolated auth.uid exception contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM|fs\.rm|unlinkSync' "$STORAGE_RECEIVER_SCRIPT" "$STORAGE_COPY_SCRIPT"; then
  echo "Storage payload tooling contains a destructive statement" >&2
  exit 1
fi

for required in \
  'prepare-a-deterministic-id-mappings' \
  'identity decision file checksum mismatch' \
  'cardinality(con.conkey)=1' \
  "a.atttypid IN ('int2'::regtype,'int4'::regtype,'int8'::regtype)" \
  'row_number() OVER (ORDER BY s.%I)' \
  'COPY festapp_merge.id_mappings' \
  "'public.user_info'" \
  'missing_decisions<>0' \
  'stale_decisions<>0' \
  'festapp_stage_a_managed.provenance' \
  "'a-id-mapping-preparation','pass'"; do
  rg -Fq "$required" "$A_MAPPING_SCRIPT" || { echo "missing source a mapping safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$A_MAPPING_SCRIPT"; then
  echo "source a mapping preparer contains a destructive statement" >&2
  exit 1
fi

for required in \
  'import-a-relational-data-with-derived-state-blocked' \
  'WITH RECURSIVE import_run AS' \
  'festapp_a_mapping_domains' \
  'ambiguous mapping domain' \
  "relation.table_name LIKE 'client_%'" \
  'raw_snapshot_preserved' \
  'requires_forced_full_sync' \
  'identity-merged-default-profile-preferred-review-required' \
  'collision profile preservation count mismatch' \
  'a row mismatch' \
  'foreign_key_orphans' \
  "SET status='blocked'" \
  "'a-auth-and-storage-import','blocked'"; do
  rg -Fq "$required" "$A_IMPORT_SCRIPT" || { echo "missing source a import safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$A_IMPORT_SCRIPT"; then
  echo "source a canonical importer contains a destructive statement" >&2
  exit 1
fi

for contract in \
  "$DEFAULT_IMPORT_SCRIPT:organization_notification_secrets:default OneSignal credentials did not converge" \
  "$A_IMPORT_SCRIPT:organization_notification_secrets:source a OneSignal credentials did not converge" \
  "$A_SEMANTIC_REPAIR_SCRIPT:source_record.data - 'ONESIGNAL_REST_API_KEY':organization JSON reference repair did not converge" \
  "$A_REFERENCE_VALIDATION_SCRIPT:2026-08-28.1:ONESIGNAL_REST_API_KEY"; do
  IFS=: read -r script required_a required_b <<<"$contract"
  for required in "$required_a" "$required_b"; do
    rg -Fq "$required" "$script" || {
      echo "missing server-only notification credential contract $required in $script" >&2
      exit 1
    }
  done
done

for required in \
  'import-a-auth-preserve-password-hashes' \
  "'auth.refresh_tokens'" \
  'refresh-token ID mapping count mismatch' \
  'source a audit log has conflicting duplicate IDs' \
  "DISTINCT ON (row_data->>''id'')" \
  'identical_rehearsal_audit_duplicates_deduplicated' \
  "relation.table_name='users'" \
  "relation.table_name='identities'" \
  'source_rows-collision_users' \
  'changed_hashes<>0' \
  'Auth foreign key' \
  "'a-auth-import','pass'" \
  "'storage_imported',false"; do
  rg -Fq "$required" "$A_AUTH_IMPORT_SCRIPT" || { echo "missing source a Auth import safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$A_AUTH_IMPORT_SCRIPT"; then
  echo "source a Auth importer contains a destructive statement" >&2
  exit 1
fi

for required in \
  'import-a-storage-metadata-preserve-runtime-ledger' \
  'Storage bucket overlap is not semantically identical' \
  'source-only Storage bucket count mismatch' \
  "column_record.column_name IN ('owner','owner_id')" \
  'source_object_rows' \
  'runtime_migration_ledger_rows' \
  "'a-storage-object-payloads','blocked'" \
  "'storage_payloads_imported',false"; do
  rg -Fq "$required" "$A_STORAGE_IMPORT_SCRIPT" || { echo "missing source a Storage metadata safety contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' "$A_STORAGE_IMPORT_SCRIPT"; then
  echo "source a Storage metadata importer contains a destructive statement" >&2
  exit 1
fi

for required in \
  'rebuild-a-client-derived-state-forward-only' \
  'forward-only rebuild after canonical merge' \
  'revision_epoch' \
  'aggregate_epoch' \
  'private_program' \
  'client_sync_release_revision_seq' \
  "'a-client-derived-state-rebuild'" \
  "'production_r2_writes',0"; do
  rg -Fq "$required" "$A_DERIVED_REBUILD_SCRIPT" || { echo "missing derived rebuild safety contract: $required" >&2; exit 1; }
done

for required in 'validate-a-approved-identity-merges' 'changed_default_hashes' \
  'email_mismatches' "check_name='a-identity-profile-review'" "SET status='pass'"; do
  rg -Fq "$required" "$A_IDENTITY_VALIDATION_SCRIPT" || { echo "missing identity validation contract: $required" >&2; exit 1; }
done

for required in 'prepare-new-isolated-runtime-foundation' 'supabase_admin' \
  'GRANT CONNECT ON DATABASE' '_realtime.schema_migrations' 'realtime.schema_migrations' \
  'Preserve the runtime ACLs'; do
  rg -Fq "$required" "$ISOLATED_FOUNDATION_SCRIPT" || { echo "missing isolated foundation contract: $required" >&2; exit 1; }
done

for required in \
  'validate-merged-client-derived-state' \
  'content_catalog' \
  '2097152' \
  'merged-client-materialization' \
  'non_enabled_over_budget_components' \
  "'production_r2_writes',0"; do
  rg -Fq "$required" "$MERGED_DERIVED_VALIDATION_SCRIPT" || { echo "missing merged derived validation contract: $required" >&2; exit 1; }
done

for required in \
  'preserve-unclassifiable-companions-without-activation' \
  'zero-common-occasion-legacy-orphan' \
  'privately_preserved_unclassifiable_rows' \
  "'invented_relationships',0" \
  "'deleted_rows',0"; do
  rg -Fq "$required" "$DEFAULT_COMPANION_VALIDATION_SCRIPT" || { echo "missing companion validation contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM' \
  "$A_DERIVED_REBUILD_SCRIPT" "$MERGED_DERIVED_VALIDATION_SCRIPT" "$DEFAULT_COMPANION_VALIDATION_SCRIPT"; then
  echo "derived-state validation tooling contains a destructive statement" >&2
  exit 1
fi

for contract in \
  "$A_SEMANTIC_REPAIR_SCRIPT:registered-forward-only-repair-v1:a-reference-registry-completeness:deleted_rows" \
  "$A_PAYLOAD_REPAIR_SCRIPT:registered-embedded-payload-repair-v1:retained_unmapped_historical_snapshot_ids:deleted_rows" \
  "$A_OPERATIONAL_REPAIR_SCRIPT:service_role_external_sync_execute:storage_url_rewrite_deferred_to_api_hostname:deleted_rows" \
  "$A_REFERENCE_VALIDATION_SCRIPT:known_reference_mismatches:api.festapp.net-cutover:deleted_rows" \
  "$ENCRYPTED_BACKUP_SCRIPT:runtime-stopped-zero-client-sessions-and-before-after-state-stable:rolpassword:object_security_sha256" \
  "$ENCRYPTED_RESTORE_SCRIPT:globals_restored:-U supabase_admin:clean_cluster_stopped"; do
  IFS=: read -r script required_a required_b required_c <<<"$contract"
  for required in "$required_a" "$required_b" "$required_c"; do
    rg -Fq -- "$required" "$script" || { echo "missing repair/recovery contract $required in $script" >&2; exit 1; }
  done
done


for required in 'storage:' 'DATABASE_URL:' 'FESTAPP_RUNTIME_DATABASE:?set FESTAPP_RUNTIME_DATABASE'; do
  rg -Fq "$required" "$RUNTIME_DATABASE_COMPOSE" || { echo "missing database target contract: $required" >&2; exit 1; }
done
for required in 'switch-validated-rehearsal-runtime-database' 'readonly SERVICES=(auth rest realtime storage meta functions studio)' \
  'storage:DATABASE_URL' 'rolled back to' '200|200|200|101' 'deleted_databases:[]'; do
  rg -Fq "$required" "$RUNTIME_SWITCH_SCRIPT" || { echo "missing runtime switch contract: $required" >&2; exit 1; }
done
for required in 'promote-validated-runtime-without-opening-write-authority' \
  'festapp-source-registry.json' 'festapp-reference-registry.json' \
  'target import registry mismatch' 'client_activation_documents_published:false' \
  'external_write_authority_opened:false' '.env.pre-production-promotion-' \
  'instance-install must not be present' "tgname='push_log_notifications'" \
  'AWS_SNS_TOPIC_ARN' 'NOTIFY_WEBHOOK_TOKEN'; do
  rg -Fq "$required" "$RUNTIME_PROMOTION_SCRIPT" || { echo "missing production promotion contract: $required" >&2; exit 1; }
done
for required in 'upgrade-installed-production-runtime-additively' \
  'bootstrap-missing-production-runtime-registries' 'forbidden partial state' \
  'install-runtime-registries.mjs' 'docker-compose.database-target.yml' 'chmod 0444' 'deleted_entries'; do
  rg -Fq "$required" "$RUNTIME_UPGRADE_SCRIPT" "$PROJECT_ROOT/automation/hetzner-supabase/runtime/install-runtime-registries.mjs" || {
    echo "missing installed runtime upgrade contract: $required" >&2; exit 1;
  }
done
for required in 'docker-compose.database-target.yml' 'caddy/Caddyfile' 'switch-rehearsal-runtime-database.sh' \
  'promote-production-runtime.sh' 'upgrade-installed-production-runtime.sh' 'festapp-reference-registry.json'; do
  rg -Fq "$required" "$RUNTIME_DEPLOY_SCRIPT" || { echo "missing deploy runtime contract: $required" >&2; exit 1; }
done

if rg -n 'DROP (DATABASE|SCHEMA|TABLE)|TRUNCATE|DELETE FROM|rm -|unlink' \
  "$A_SEMANTIC_REPAIR_SCRIPT" "$A_PAYLOAD_REPAIR_SCRIPT" \
  "$A_OPERATIONAL_REPAIR_SCRIPT" "$A_REFERENCE_VALIDATION_SCRIPT" \
  "$ENCRYPTED_BACKUP_SCRIPT" "$ENCRYPTED_RESTORE_SCRIPT" "$RUNTIME_SWITCH_SCRIPT" \
  "$RUNTIME_PROMOTION_SCRIPT" "$RUNTIME_UPGRADE_SCRIPT"; then
  echo "repair/recovery tooling contains an unapproved destructive statement" >&2
  exit 1
fi

echo "Rehearsal canonical-schema safety contract passed."
