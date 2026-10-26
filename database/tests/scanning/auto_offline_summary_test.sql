-- test-setup: database/functions/scanning/admission.sql
BEGIN;
DO $$
DECLARE fixture jsonb; oc bigint; session jsonb; result jsonb; manifest jsonb; sid uuid; token text;
BEGIN
 fixture:=public.scanner_test_fixture(4);oc:=(fixture->>'occasion')::bigint;
 UPDATE eshop.tickets SET state='ordered' WHERE id=(fixture#>>'{tickets,1}')::bigint;
 UPDATE eshop.tickets SET state='storno' WHERE id=(fixture#>>'{tickets,2}')::bigint;
 UPDATE eshop.orders SET state='stock' WHERE id IN (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=(fixture#>>'{tickets,3}')::bigint);
 session:=public.open_scanner_session(fixture->>'scan_code');sid:=(session#>>'{data,session_id}')::uuid;token:=session#>>'{data,token}';
 result:=public.get_scanner_summary(sid,token)->'data';
 PERFORM assert_eq((result->>'eligible_total')::bigint,1::bigint,'admission summary excludes unpaid, cancelled and stock');
 PERFORM assert_eq((result->>'snapshot_ticket_count')::bigint,4::bigint,'automatic preparation counts the entire offline population');
 manifest:=public.prepare_scanner_snapshot(sid,token)->'data';
 PERFORM assert_eq(result->>'snapshot_ticket_count',manifest->>'ticket_count','summary population matches actual immutable snapshot');
END $$;
ROLLBACK;
