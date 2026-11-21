-- Isolated synthetic benchmark only. psql -v ON_ERROR_STOP=1 -f this-file
BEGIN;
SET LOCAL jit=off;
SET LOCAL max_parallel_workers_per_gather=0;
-- Rollback restores these indexes when benchmarking an already migrated DB.
DROP INDEX IF EXISTS eshop.orders_occasion_report_idx;
DROP INDEX IF EXISTS eshop.orders_payment_info_report_idx;
\i database/tests/helpers/assertions.sql
DO $$
DECLARE u uuid; org bigint; unit_id bigint; occ bigint; foreign_occ bigint; bank bigint;
BEGIN
  PERFORM create_user_for_test('report_benchmark','report-benchmark@test.local');
  u:=get_user_id('report_benchmark');
  INSERT INTO public.organizations(title) VALUES('Synthetic benchmark') RETURNING id INTO org;
  UPDATE public.user_info SET organization=org WHERE id=u;
  INSERT INTO public.units(title,organization) VALUES('Synthetic benchmark',org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(title,link,start_time,end_time,organization,unit)
    VALUES('Synthetic benchmark','report-benchmark',now(),now(),org,unit_id) RETURNING id INTO occ;
  INSERT INTO public.occasions(title,link,start_time,end_time,organization,unit)
    VALUES('Synthetic foreign','report-benchmark-foreign',now(),now(),org,unit_id) RETURNING id INTO foreign_occ;
  PERFORM pg_temp.adopt_public_link_fixtures();
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(occ,u,true);
  INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit_id,u,true);
  INSERT INTO eshop.bank_accounts(title) VALUES('Synthetic bank') RETURNING id INTO bank;
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  CREATE TEMP TABLE benchmark_payments AS WITH inserted AS (
    INSERT INTO eshop.payment_info(paid,returned,currency_code,deposit_amount)
    SELECT 120,20,'CZK',50 FROM generate_series(1,50000) RETURNING id
  ) SELECT id,row_number() OVER(ORDER BY id) AS n FROM inserted;
  CREATE TEMP TABLE benchmark_forms AS WITH inserted AS (
    INSERT INTO public.forms(occasion,title)
    SELECT event_id,'Benchmark form '||n FROM unnest(ARRAY[occ,foreign_occ]) event_id CROSS JOIN generate_series(1,10) n
    RETURNING id,key,occasion
  ) SELECT id,key,occasion,row_number() OVER(PARTITION BY occasion ORDER BY id)-1 AS n FROM inserted;
  INSERT INTO eshop.orders(occasion,price,state,payment_info,order_symbol,order_sequence,form,data)
    SELECT f.occasion,100,'paid',p.id,
      (SELECT string_agg(substr('1A2A3A4A5A6A7A8A9A1C',d::int*2+1,2),'' ORDER BY i)
       FROM regexp_split_to_table(lpad(p.n::text,5,'0'),'') WITH ORDINALITY AS digits(d,i)),p.n,f.id,jsonb_build_object('form',f.key)
    FROM benchmark_payments p JOIN benchmark_forms f
      ON f.occasion=CASE WHEN p.n<=5000 THEN occ ELSE foreign_occ END AND f.n=p.n%10;
  INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_type)
    SELECT now(),60,'CZK',bank,p.id,'manual' FROM benchmark_payments p CROSS JOIN generate_series(1,2);
  INSERT INTO eshop.products(title,occasion) VALUES('Benchmark product',occ);
  INSERT INTO eshop.tickets(occasion,state) SELECT occ,'paid' FROM generate_series(1,5000);
  INSERT INTO eshop.order_product_ticket("order",product,ticket)
    SELECT o.id,p.id,t.id FROM (SELECT id,row_number() OVER(ORDER BY id) n FROM eshop.orders WHERE occasion=occ) o
    JOIN (SELECT id,row_number() OVER(ORDER BY id) n FROM eshop.tickets WHERE occasion=occ) t USING(n)
    CROSS JOIN eshop.products p CROSS JOIN generate_series(1,3) WHERE p.occasion=occ;
  INSERT INTO eshop.spots(occasion,title,secret)
    SELECT occ,'Seat',gen_random_uuid() FROM generate_series(1,5000);
END $$;
ANALYZE eshop.orders; ANALYZE eshop.payment_info; ANALYZE eshop.transactions;
ANALYZE eshop.tickets; ANALYZE eshop.order_product_ticket; ANALYZE eshop.spots;
-- Explain the actual installed canonical query, without copying its metrics.
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || replace(replace(
  substring(prosrc FROM '(?s)  WITH scope.*?FROM scope s CROSS JOIN invalid;'),
  '(occasion_link)', '('||quote_literal('report-benchmark')||')'), ' INTO r,invalid_payment', '')
FROM pg_proc WHERE oid = 'public.get_report_ws(text)'::regprocedure
\gexec
CREATE INDEX orders_occasion_report_idx ON eshop.orders(occasion);
CREATE INDEX orders_payment_info_report_idx ON eshop.orders(payment_info);
-- Explain the actual installed canonical query, without copying its metrics.
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || replace(replace(
  substring(prosrc FROM '(?s)  WITH scope.*?FROM scope s CROSS JOIN invalid;'),
  '(occasion_link)', '('||quote_literal('report-benchmark')||')'), ' INTO r,invalid_payment', '')
FROM pg_proc WHERE oid = 'public.get_report_ws(text)'::regprocedure
\gexec
DO $$
DECLARE report jsonb:=public.get_report_ws('report-benchmark');
BEGIN
  IF report->>'code' IS DISTINCT FROM '200' OR report#>>'{report,orders,total}' IS DISTINCT FROM '5000' THEN
    RAISE EXCEPTION 'Benchmark did not read the authorized 5000-order report';
  END IF;
  IF (SELECT sum((f#>>'{stats,total}')::int) FROM jsonb_array_elements(public.get_forms_by_link('report-benchmark')) f)
     IS DISTINCT FROM 5000::bigint THEN
    RAISE EXCEPTION 'Benchmark did not read the authorized 10-form catalog';
  END IF;
END $$;
SET LOCAL pg_stat_statements.track='all';
CREATE TEMP TABLE baseline_statements AS
 SELECT userid,queryid,toplevel,calls FROM extensions.pg_stat_statements WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database());
EXPLAIN (ANALYZE, BUFFERS) SELECT public.get_forms_by_link('report-benchmark');
SELECT sum(s.calls-coalesce(b.calls,0)) AS catalog_nested_sql_calls,
 sum(s.calls-coalesce(b.calls,0)) FILTER(WHERE s.query ILIKE '%count(*) filter%') AS catalog_order_aggregate_calls
FROM extensions.pg_stat_statements s LEFT JOIN baseline_statements b USING(userid,queryid,toplevel)
WHERE s.dbid=(SELECT oid FROM pg_database WHERE datname=current_database()) AND NOT s.toplevel;

SELECT octet_length(public.get_report_ws('report-benchmark')::text) AS response_bytes;

-- Optional paired comparison. Supply pg_get_functiondef from the predecessor,
-- saved in predecessor_catalog_file by an owned local database lease.
\if :{?predecessor_catalog_file}
SELECT string_agg(pg_get_functiondef(signature::regprocedure)||';',E'\n') AS candidate_catalog_ddl
FROM unnest(ARRAY['public.get_forms_by_link(text)','public.get_form_registration_mode_internal(bigint,timestamp with time zone)']) signature
\gset
CREATE TEMP TABLE paired_read_timings(variant text, surface text, elapsed_ms numeric);
CREATE FUNCTION pg_temp.time_authorized_reads(p_variant text,p_samples int DEFAULT 1) RETURNS void LANGUAGE plpgsql AS $$
DECLARE started timestamptz;
BEGIN
 FOR sample IN 1..p_samples LOOP
  started:=clock_timestamp();
  PERFORM public.get_report_ws('report-benchmark');
  INSERT INTO paired_read_timings VALUES(p_variant,'occasion_report',extract(epoch FROM clock_timestamp()-started)*1000);
  started:=clock_timestamp();
  PERFORM public.get_forms_by_link('report-benchmark');
  INSERT INTO paired_read_timings VALUES(p_variant,'form_catalog',extract(epoch FROM clock_timestamp()-started)*1000);
 END LOOP;
END $$;
-- Alternate order across three series of three samples per version. Warm each
-- definition following a switch before recording timings.
\i :predecessor_catalog_file
SELECT pg_temp.time_authorized_reads('warmup'),pg_temp.time_authorized_reads('predecessor',3);
:candidate_catalog_ddl
SELECT pg_temp.time_authorized_reads('warmup'),pg_temp.time_authorized_reads('candidate',3);
SELECT pg_temp.time_authorized_reads('candidate',3);
\i :predecessor_catalog_file
SELECT pg_temp.time_authorized_reads('warmup'),pg_temp.time_authorized_reads('predecessor',3);
SELECT pg_temp.time_authorized_reads('predecessor',3);
:candidate_catalog_ddl
SELECT pg_temp.time_authorized_reads('warmup'),pg_temp.time_authorized_reads('candidate',3);

SELECT surface,variant,count(*) AS samples,
 round(percentile_disc(0.95) WITHIN GROUP(ORDER BY elapsed_ms),3) AS p95_ms
FROM paired_read_timings WHERE variant<>'warmup' GROUP BY surface,variant ORDER BY surface,variant;
\endif
ROLLBACK;
