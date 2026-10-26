-- Isolated synthetic benchmark only. psql -v ON_ERROR_STOP=1 -f this-file
BEGIN;
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
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(occ,u,true);
  INSERT INTO eshop.bank_accounts(title) VALUES('Synthetic bank') RETURNING id INTO bank;
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  CREATE TEMP TABLE benchmark_payments AS WITH inserted AS (
    INSERT INTO eshop.payment_info(paid,returned,currency_code,deposit_amount)
    SELECT 120,20,'CZK',50 FROM generate_series(1,50000) RETURNING id
  ) SELECT id,row_number() OVER(ORDER BY id) AS n FROM inserted;
  INSERT INTO eshop.orders(occasion,price,state,payment_info)
    SELECT CASE WHEN n<=5000 THEN occ ELSE foreign_occ END,100,'paid',id FROM benchmark_payments;
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
  'occasion_link', quote_literal('report-benchmark')), ' INTO r,invalid_payment', '')
FROM pg_proc WHERE oid = 'public.get_report_ws(text)'::regprocedure
\gexec
CREATE INDEX orders_occasion_report_idx ON eshop.orders(occasion);
CREATE INDEX orders_payment_info_report_idx ON eshop.orders(payment_info);
-- Explain the actual installed canonical query, without copying its metrics.
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || replace(replace(
  substring(prosrc FROM '(?s)  WITH scope.*?FROM scope s CROSS JOIN invalid;'),
  'occasion_link', quote_literal('report-benchmark')), ' INTO r,invalid_payment', '')
FROM pg_proc WHERE oid = 'public.get_report_ws(text)'::regprocedure
\gexec
SELECT octet_length(public.get_report_ws('report-benchmark')::text) AS response_bytes;
ROLLBACK;
