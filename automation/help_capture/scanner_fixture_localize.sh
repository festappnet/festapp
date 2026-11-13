#!/bin/sh
set -eu
# This overlay is restricted to the retained disposable help fixture.
[ "$(docker inspect -f '{{.Name}}' supabase_db_festapp-wizard-help-20261025)" = '/supabase_db_festapp-wizard-help-20261025' ]
[ "$(docker exec supabase_db_festapp-wizard-help-20261025 psql -U postgres -d postgres -Atc "select count(*) from public.occasions where id=2 and unit=1 and title in ('Slavnostní ples U Lípy','Linden Gala Ball')")" = 1 ]
case "$1" in
cs) event='Slavnostní ples U Lípy'; unit='Spolek U Lípy'; product='Vstupenka na ples'; kind='Vstupné'; name='Jana'; surname='Nováková';;
en) event='Linden Gala Ball'; unit='Linden Community Association'; product='Gala admission'; kind='Admission'; name='Jane'; surname='Taylor';;
*) exit 1;;
esac
docker exec -i supabase_db_festapp-wizard-help-20261025 psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -v event="$event" -v unit="$unit" -v product="$product" -v kind="$kind" -v person="$name" -v surname="$surname" <<'SQL'
UPDATE eshop.tickets SET updated_at=clock_timestamp()-interval '5 minutes' WHERE occasion=2 AND ticket_symbol IN ('IOSPAID25A','IOSPAIDEN') AND state='used';
UPDATE public.scanner_settings SET config=jsonb_set(config,'{fields,0,form_title}',to_jsonb(:'event'::text)) WHERE occasion_id=2 AND config#>>'{fields,0,key}'='order:2:7';
UPDATE public.occasions SET title=:'event' WHERE id=2 AND unit=1;
UPDATE public.units SET title=:'unit' WHERE id=1;
UPDATE public.forms SET title=:'event' WHERE id=2 AND occasion=2;
UPDATE eshop.products SET title=:'product',title_short=:'product' WHERE id=3 AND occasion=2;
UPDATE eshop.product_types SET title=:'kind' WHERE id=3 AND occasion=2;
UPDATE public.form_fields SET title=:'kind' WHERE id=9 AND form=2;
UPDATE eshop.orders SET data=jsonb_set(jsonb_set(jsonb_set(jsonb_set(data,'{name}',to_jsonb(:'person'::text)),'{surname}',to_jsonb(:'surname'::text)),'{tickets,0,name}',to_jsonb(:'person'::text)),'{tickets,0,surname}',to_jsonb(:'surname'::text)) WHERE id IN (2,3,4,5) AND occasion=2;
SQL
