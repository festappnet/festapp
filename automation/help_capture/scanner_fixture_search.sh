#!/bin/sh
set -eu
# This overlay is restricted to the retained disposable help fixture.
[ "$(docker inspect -f '{{.Name}}' supabase_db_festapp-wizard-help-20261025)" = '/supabase_db_festapp-wizard-help-20261025' ]
[ "$(docker exec supabase_db_festapp-wizard-help-20261025 psql -U postgres -d postgres -Atc "select count(*) from public.occasions where id=2 and unit=1 and title in ('Slavnostní ples U Lípy','Linden Gala Ball')")" = 1 ]
case "$1" in off) state=false;; on) state=true;; *) exit 1;; esac
docker exec -i supabase_db_festapp-wizard-help-20261025 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -v value="$state" <<'SQL'
UPDATE public.scanner_settings SET config=jsonb_set(jsonb_set(config,'{manual_search,tickets}',(:'value')::jsonb),'{manual_search,users}',(:'value')::jsonb) WHERE occasion_id=2;
SQL
