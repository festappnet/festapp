#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
container="${FESTAPP_TEST_PG_CONTAINER:-supabase_db_festapp-db-tests-pg15}"
# Dedicated bootstrapped local test DB only. Every change, including ACLs, rolls back.
python3 - "$root" <<'PY' | docker exec -i "$container" psql -X -q -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null
from pathlib import Path
import sys
root = Path(sys.argv[1])
fixture = (root/'automation/tests/fixtures/slunovrat_news_emergency.sql').read_text()
fixture = fixture.replace('-- ASSERTION_HELPERS', (root/'database/tests/helpers/assertions.sql').read_text())
fixture = fixture.replace('-- EMERGENCY_POLICY', (root/'automation/hetzner-supabase/runtime/slunovrat-news-emergency.sql').read_text())
fixture = fixture.replace('-- REMOVE_EMERGENCY_POLICY', (root/'automation/hetzner-supabase/runtime/slunovrat-news-emergency-remove.sql').read_text())
fixture = fixture.replace('-- EXTEND_EMERGENCY_POLICY', (root/'automation/hetzner-supabase/runtime/slunovrat-news-emergency-extend.sql').read_text())
print(fixture)
PY
printf '%s\n' 'Slunovrat legacy news/push: publication gate, admission, scoped access, expiry and removal passed; no external delivery.'
