#!/usr/bin/env bash
# Narrow Caddy-only activation. Does not touch Auth, functions, DB or Compose.
set -euo pipefail
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ "${FESTAPP_SECURITY_CONFIG_ACK:-}" == 'reload-approved-storage-body-cap' ]] || fail 'explicit runtime activation acknowledgement required'
[[ $EUID == 0 && $(hostname -s) == festapp-supabase-rehearsal-01 ]] || fail 'unexpected runtime host'
[[ $# == 2 && $2 =~ ^[a-f0-9]{64}$ && -f $1 ]] || fail 'usage: apply-security-config.sh candidate-Caddyfile sha256'
readonly CANDIDATE="$(realpath "$1")"
readonly EXPECTED_SHA="$2"
readonly COMPOSE_DIR=/opt/festapp-supabase/docker
cd "$COMPOSE_DIR"
exec 9>.festapp-runtime-upgrade.lock
flock -n 9 || fail 'another runtime operation is active'
[[ $(sed -n 's/^FESTAPP_RUNTIME_DATABASE=//p' .env) == festapp_rehearsal_20260909220601 ]] || fail 'canonical database mismatch'
[[ $(sha256sum "$CANDIDATE" | awk '{print $1}') == "$EXPECTED_SHA" ]] || fail 'candidate digest mismatch'
[[ $(docker exec supabase-db psql -X -U postgres -d festapp_rehearsal_20260909220601 -Atqc 'BEGIN READ ONLY; SELECT id FROM public.organizations WHERE id=1; COMMIT' | sed '/^BEGIN$/d;/^COMMIT$/d') == 1 ]] || fail 'organization assertion failed'
readonly EVIDENCE="/var/lib/festapp-rehearsal-evidence/security-caddy-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -e "$EVIDENCE" ]] || fail 'evidence path already exists'
install -d -m 0700 "$EVIDENCE"
umask 077
cp caddy/Caddyfile "$EVIDENCE/previous.Caddyfile"
cp "$CANDIDATE" "$EVIDENCE/candidate.Caddyfile"
readonly SEALED_CANDIDATE="$EVIDENCE/candidate.Caddyfile"
[[ $(sha256sum "$SEALED_CANDIDATE" | awk '{print $1}') == "$EXPECTED_SHA" ]] || fail 'sealed candidate digest mismatch'
# Bind mounts retain the inode. Validate with the running image and its own env.
docker exec -i festapp-caddy caddy validate --adapter caddyfile --config - < "$SEALED_CANDIDATE" > "$EVIDENCE/validate.log" 2>&1
# Preserve the prior file in protected evidence, but never automatically restore
# weaker caps/ACLs. A reload failure requires an explicit forward correction.
cat "$SEALED_CANDIDATE" > caddy/Caddyfile
docker exec festapp-caddy caddy reload --adapter caddyfile --config /etc/caddy/Caddyfile > "$EVIDENCE/reload.log" 2>&1
[[ $(sha256sum caddy/Caddyfile | awk '{print $1}') == "$EXPECTED_SHA" ]] || fail 'installed file digest mismatch'
docker exec festapp-caddy caddy adapt --adapter caddyfile --config /etc/caddy/Caddyfile > "$EVIDENCE/expected.json" 2> "$EVIDENCE/adapt.log"
curl --fail --silent http://127.0.0.1:2019/config/ > "$EVIDENCE/active.json"
python3 - "$EVIDENCE" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
assert json.loads((p/'expected.json').read_text()) == json.loads((p/'active.json').read_text()), 'active Caddy configuration mismatch'
PY
printf '%s\n' "$EXPECTED_SHA" > "$EVIDENCE/caddy.sha256"
echo "Caddy configuration reloaded and read back: $EXPECTED_SHA"
