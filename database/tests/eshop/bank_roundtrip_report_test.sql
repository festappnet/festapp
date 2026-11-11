-- test-setup: database/functions/payment_providers/operations_schema.sql
-- test-setup: database/functions/eshop_transactions/payment_totals.sql
-- test-setup: database/functions/eshop/get_report_ws.sql
BEGIN;
DO $$
DECLARE u uuid; org bigint; un bigint; oc bigint; pi bigint; bank bigint; r jsonb; m jsonb; facts record;
BEGIN
 PERFORM create_user_for_test('bank_roundtrip_report','bank-roundtrip@test.local');
 u:=get_user_id('bank_roundtrip_report');
 INSERT INTO public.organizations(title) VALUES('Bank roundtrip report') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=u;
 INSERT INTO public.units(title,organization) VALUES('Bank roundtrip',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,link,start_time,end_time,organization,unit)
 VALUES('Bank roundtrip','bank-roundtrip',now(),now(),org,un) RETURNING id INTO oc;
 PERFORM pg_temp.adopt_public_link_fixtures();
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,u,true);
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 INSERT INTO eshop.bank_accounts(title) VALUES('Bank roundtrip') RETURNING id INTO bank;
 -- Historical cached paid/returned values were netted to zero.
 INSERT INTO eshop.payment_info(paid,returned,currency_code) VALUES(0,0,'CZK') RETURNING id INTO pi;
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,price,state,payment_info)
 VALUES(public.next_order_sequence(oc),public.generate_order_symbol(),oc,400,'ordered',pi);
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_type,ingest_source)
 VALUES('2026-11-11',600,'CZK',bank,pi,'Okamžitá příchozí platba','banksync_api'),
 ('2026-11-11',-600,'CZK',bank,pi,'Okamžitá odchozí platba','banksync_api');
 SELECT * INTO facts FROM public.payment_financial_totals_internal(pi);
 PERFORM assert_eq(facts.gross_received,600::numeric,'bank receipts are gross');
 PERFORM assert_eq(facts.refunded,600::numeric,'paired outgoing bank movement is returned money');
 PERFORM assert_eq(facts.net_received,0::numeric,'bank roundtrip has zero net');
 SET LOCAL ROLE authenticated;
 r:=public.get_report_ws('bank-roundtrip');
 RESET ROLE;
 PERFORM assert_eq((r->>'code')::int,200,'report succeeds');
 m:=r->'report'->'money_by_currency'->0;
 PERFORM assert_eq((m->>'received')::numeric,600::numeric,'report retains gross incoming 600');
 PERFORM assert_eq((m->>'returned')::numeric,600::numeric,'report retains gross outgoing 600');
 PERFORM assert_eq((m->>'net_received')::numeric,0::numeric,'report net zero');
 PERFORM assert_true(r->'report'->'timeline'->'payments' @> '[{"day":"2026-11-11","currency":"CZK","received":"600.00","returned":"600.00"}]','chart shows incoming and returned separately');
 UPDATE eshop.orders SET state='storno',price=0 WHERE occasion=oc;
 r:=public.get_report_ws('bank-roundtrip');
 PERFORM assert_eq((r#>>'{report,money_by_currency,0,received}')::numeric,600::numeric,'storno keeps incoming history');
 PERFORM assert_eq((r#>>'{report,money_by_currency,0,returned}')::numeric,600::numeric,'storno keeps returned history');
 -- An explicit negative manual adjustment remains a correction to receipts.
 INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,payment_info,transaction_type,ingest_source)
 VALUES(now(),-25,'CZK',bank,pi,'manual','manual');
 SELECT * INTO facts FROM public.payment_financial_totals_internal(pi);
 PERFORM assert_eq(facts.gross_received,575::numeric,'manual negative remains a receipt correction');
 PERFORM assert_eq(facts.refunded,600::numeric,'manual correction is not reclassified as refund');
END $$;
ROLLBACK;
