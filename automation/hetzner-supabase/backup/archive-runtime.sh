#!/usr/bin/env bash
set -euo pipefail
# Plaintext stream only: the caller must pipe directly to age, never to a log.
readonly runtime_root="${1:-/opt/festapp-supabase}"
readonly system_root="${2:-/}"
[[ "$runtime_root" == /* && "$system_root" == /* ]] || exit 1
runtime_paths=(docker/.env docker/docker-compose.yml docker/docker-compose.festapp.yml
  docker/docker-compose.database-target.yml docker/caddy/Caddyfile docker/volumes/functions
  docker/volumes/proxy docker/volumes/api docker/volumes/pooler
  docker/volumes/snippets docker/studio-customization)
# Only initialization SQL belongs in runtime, never live PGDATA or its WAL.
for config in "$runtime_root"/docker/volumes/db/*.sql; do
  [[ -f "$config" ]] || { echo 'Missing database initialization SQL' >&2; exit 1; }
  runtime_paths+=("${config#"$runtime_root"/}")
done
for override in docker-compose.email.yml docker-compose.pgbackrest.yml docker-compose.resource-budget.yml; do
  [[ ! -f "$runtime_root/docker/$override" ]] || runtime_paths+=("docker/$override")
done
for config in "${runtime_paths[@]}"; do
  [[ -e "$runtime_root/$config" ]] || { echo 'Missing required runtime configuration' >&2; exit 1; }
done
# The canonical Access tunnel uses this root-only secret file. Its copy stays
# inside the age-encrypted runtime artifact; never load it in an isolated drill.
[[ -f "$system_root/etc/festapp-cloudflared/admin-tunnel.token" ]] || {
  echo 'Missing canonical admin tunnel recovery credential' >&2; exit 1;
}
extra_paths=(-C "$system_root" etc/festapp-cloudflared/admin-tunnel.token)
if [[ -f "$system_root/etc/festapp-pgbackrest/enabled" ]]; then
  for config in etc/festapp-pgbackrest/pgbackrest.conf etc/festapp-pgbackrest/recovery.json.age opt/festapp-backup/pgbackrest/Dockerfile; do
    [[ -f "$system_root/$config" ]] || { echo 'Missing PITR recovery configuration' >&2; exit 1; }
    extra_paths+=("$config")
  done
fi
if [[ -f "$system_root/etc/festapp-backup/images.env" ]]; then
  extra_paths+=(etc/festapp-backup/images.env)
fi
COPYFILE_DISABLE=1 tar -C "$runtime_root" -cf - "${runtime_paths[@]}" "${extra_paths[@]}"
