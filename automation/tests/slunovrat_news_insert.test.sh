#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
container="${FESTAPP_TEST_PG_CONTAINER:-supabase_db_festapp-db-tests-pg15}"
task_db="festapp_news_insert_${RANDOM}_$$"
docker exec "$container" createdb -U postgres "$task_db"
trap 'docker exec "$container" dropdb -U postgres "$task_db" >/dev/null' EXIT
python3 - "$root" "${1:-insert}" <<'PY' | docker exec -i "$container" psql -X -q -U postgres -d "$task_db" -v ON_ERROR_STOP=1 >/dev/null
from pathlib import Path
import sys
r = Path(sys.argv[1])
s = (r/'automation/tests/fixtures/slunovrat_news_insert.sql').read_text()
if len(sys.argv)>2 and sys.argv[2]=='delete':
    s += (r/'automation/tests/fixtures/slunovrat_news_delete.sql').read_text()
for name in ['20261013093000_slunovrat_news_insert.sql','20261013094500_news_search_extensions_usage.sql','20261013100000_verify_news_search_schema_grant.sql','20261013103000_slunovrat_news_delete.sql']:
    s = s.replace('\\ir ../../../supabase/migrations/'+name, (r/'supabase/migrations'/name).read_text())
print(s)
PY
printf '%s\n' "Slunovrat news ${1:-insert}: authorized operations and tenant/editor boundaries passed."
