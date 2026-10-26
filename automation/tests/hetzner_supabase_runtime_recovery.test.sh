#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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


[[ -x "$ENCRYPTED_BACKUP_SCRIPT" ]] || { echo "encrypted backup script must be executable" >&2; exit 1; }
[[ -x "$ENCRYPTED_RESTORE_SCRIPT" ]] || { echo "encrypted restore drill must be executable" >&2; exit 1; }

for required in \
  'FESTAPP_BACKUP_INACTIVE_TARGET_ACK' \
  'backup-complete-inactive-rehearsal-target' \
  'SOURCE_WAS_ACTIVE_RUNTIME=false' \
  'runtime_database:$runtimeDatabase' \
  'source_was_active_runtime:$sourceWasActiveRuntime'; do
  rg -Fq "$required" "$ENCRYPTED_BACKUP_SCRIPT" || {
    echo "missing inactive rehearsal recovery safety contract: $required" >&2
    exit 1
  }
done
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
for required in FESTAPP_SUPABASE_SITE_ADDRESSES \
  'http://{$FESTAPP_SUPABASE_ADMIN_HOSTNAME:supabase.festapp.net}:8999' \
  'bind 127.0.0.1' \
  'request_header Authorization "Basic {$FESTAPP_SUPABASE_ADMIN_BASIC_AUTH}"' \
  trusted_proxies_strict CF-Connecting-IP 'reverse_proxy 127.0.0.1:8000' \
  '/auth/v1' '/rest/v1' '/storage/v1' '/realtime/v1' '/functions/v1' \
  'Strict-Transport-Security' 'X-Frame-Options' 'respond "Not Found" 404'; do
  rg -Fq "$required" "$RUNTIME_CADDYFILE" || { echo "missing public-origin contract $required in $RUNTIME_CADDYFILE" >&2; exit 1; }
done
for required in FESTAPP_SUPABASE_HOSTNAME FESTAPP_SUPABASE_SITE_ADDRESSES \
  FESTAPP_SUPABASE_ADMIN_SITE \
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

for contract in \
  "$ENCRYPTED_BACKUP_SCRIPT:runtime-stopped-zero-client-sessions-and-before-after-state-stable:rolpassword:object_security_sha256" \
  "$ENCRYPTED_RESTORE_SCRIPT:globals_restored:-U supabase_admin:clean_cluster_stopped"; do
  IFS=: read -r script required_a required_b required_c <<<"$contract"
  for required in "$required_a" "$required_b" "$required_c"; do
    rg -Fq -- "$required" "$script" || { echo "missing repair/recovery contract $required in $script" >&2; exit 1; }
  done
done


for required in 'auth:' 'GOTRUE_DB_DATABASE_URL:' 'FESTAPP_RUNTIME_DATABASE:?set FESTAPP_RUNTIME_DATABASE'; do
  rg -Fq "$required" "$RUNTIME_DATABASE_COMPOSE" || { echo "missing database target contract: $required" >&2; exit 1; }
done
for required in 'switch-validated-rehearsal-runtime-database' 'readonly SERVICES=(auth rest realtime meta functions studio)' \
  'canonical_asset_cutover' 'rolled back to' '200|200|410|101' 'deleted_databases:[]'; do
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
  "$ENCRYPTED_BACKUP_SCRIPT" "$ENCRYPTED_RESTORE_SCRIPT" "$RUNTIME_SWITCH_SCRIPT" \
  "$RUNTIME_PROMOTION_SCRIPT" "$RUNTIME_UPGRADE_SCRIPT"; then
  echo "repair/recovery tooling contains an unapproved destructive statement" >&2
  exit 1
fi

echo "Runtime and recovery safety contract passed."
