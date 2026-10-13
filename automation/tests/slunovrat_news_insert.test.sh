#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
container="${FESTAPP_TEST_PG_CONTAINER:-supabase_db_festapp-db-tests-pg15}"
task_db="festapp_news_insert_${RANDOM}_$$"
docker exec "$container" createdb -U postgres "$task_db"
trap 'docker exec "$container" dropdb -U postgres "$task_db" >/dev/null' EXIT
python3 - "$root" <<'PY' | docker exec -i "$container" psql -X -q -U postgres -d "$task_db" -v ON_ERROR_STOP=1 >/dev/null
from pathlib import Path
import sys
r = Path(sys.argv[1])
s = (r/'automation/tests/fixtures/slunovrat_news_insert.sql').read_text()
for name in ['20261013093000_slunovrat_news_insert.sql','20261013094500_news_search_extensions_usage.sql']:
    s = s.replace('\\ir ../../../supabase/migrations/'+name, (r/'supabase/migrations'/name).read_text())
print(s)
PY
printf '%s\n' 'Slunovrat news insert: editor accepted; other tenant, spoofed author, explicit ID and non-editor denied.'
