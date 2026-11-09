#!/usr/bin/env bash
set -euo pipefail

[[ $(id -u) == 0 && $(hostname -s) == festapp-supabase-rehearsal-01 ]] || {
  echo 'Run as root on the canonical Festapp host' >&2; exit 1;
}
[[ $(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' /opt/festapp-supabase/docker/.env) == festapp_rehearsal_20260909220601 ]] || {
  echo 'Canonical database identity mismatch' >&2; exit 1;
}
exec 9>/run/lock/festapp-build-cache-cleanup.lock
flock -n 9 || exit 0
# BuildKit excludes cache used by active builds. Age filtering also preserves
# recent cache. These are best-effort targets, never permission to prune images,
# containers, volumes, backup files or younger cache.
docker buildx prune --builder default --force --filter until=24h \
  --max-used-space 512MB --min-free-space 8GB
df -h /
