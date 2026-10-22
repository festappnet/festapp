DO $$
DECLARE org bigint; u bigint; occ bigint; pi bigint; ord bigint; bank bigint; conn uuid; attempt uuid;
 totals record; unpaired_transaction_id bigint; actor uuid; report jsonb; money jsonb; occasion_link text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Stripe totals fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Organizer totals',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Stripe totals',org,u,'stripe-totals-'||extensions.gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 VALUES(org,u,'acct_totals',false,'connected') RETURNING id INTO conn;
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method,stripe_connection_id,paid_externally)
 VALUES(100,'CZK','stripe',conn,25) RETURNING id INTO pi;
 INSERT INTO eshop.orders(occasion,payment_info,state,price,currency_code,order_sequence,order_symbol)
 VALUES(occ,pi,'ordered',100,'CZK',1,public.generate_order_symbol()) RETURNING id INTO ord;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
 amount_minor,currency,order_revision,idempotency_key,reservation_expires_at)
 VALUES(ord,pi,org,u,conn,false,10000,'CZK',1,'totals:'||extensions.gen_random_uuid(),now()+interval '30 minutes') RETURNING id INTO attempt;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Manual facts','CASH',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type)
 VALUES(bank,pi,75,'CZK','2026-10-20 23:59:00','manual'),(bank,pi,-10,'CZK','2026-10-21 00:01:00','return');
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_totals',attempt,'payment',5000,'CZK','2026-10-20 21:59:00Z'),
 (conn,'re_totals',attempt,'refund',2000,'CZK','2026-10-20 22:01:00Z');
 INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at)
 VALUES(conn,'dp_totals',attempt,1000,'needs_response',now());
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pi);
 PERFORM assert_eq(totals.gross_received,125::numeric,'bank + provider gross without fees');
 PERFORM assert_eq(totals.refunded,30::numeric,'refunds separate from dispute');
 PERFORM assert_eq(totals.external_received,25::numeric,'external settlement remains separate');
 PERFORM assert_eq(totals.net_received,95::numeric,'unattributed external field is not silently added to ledger money');
 PERFORM assert_eq(totals.available,85::numeric,'hold reduces availability, not refunded money');
 PERFORM public.refresh_payment_info_totals_internal(pi);
 PERFORM public.refresh_payment_info_totals_internal(pi);
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),125::numeric,'repeat projection cannot double revenue');
 PERFORM assert_eq((SELECT paid_externally FROM eshop.payment_info WHERE id=pi),25::numeric,'refresh does not erase external settlement');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),30::numeric,'refund remains a separate summary');
 UPDATE eshop.stripe_disputes SET status='won' WHERE provider_id='dp_totals';
 PERFORM assert_eq((SELECT available FROM public.payment_financial_totals_internal(pi)),95::numeric,'won dispute releases availability');
 PERFORM assert_eq((SELECT refunded FROM public.payment_financial_totals_internal(pi)),30::numeric,'won dispute does not undo refunds');
 UPDATE eshop.stripe_disputes SET status='needs_response' WHERE provider_id='dp_totals';
 PERFORM public.create_user_for_test('stripe_report_viewer','stripe-report@example.test');actor:=get_user_id('stripe_report_viewer');
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(occ,actor,true);
 SELECT link INTO occasion_link FROM public.occasions WHERE id=occ;
 PERFORM public.reserve_public_link_internal('occasion',occ,occasion_link,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SET LOCAL ROLE authenticated;
 report:=public.get_report_ws(occasion_link);
 RESET ROLE;
 PERFORM assert_eq(report->>'code','200','canonical report includes Stripe facts');
 money:=report#>'{report,money_by_currency,0}';
 PERFORM assert_eq((money->>'received')::numeric,125::numeric,'report never double counts bank/manual/Stripe');
 PERFORM assert_eq((money->>'returned')::numeric,30::numeric,'report includes actual bank and Stripe refunds');
 PERFORM assert_eq((money->>'net_received')::numeric,95::numeric,'legacy external field is preserved without inflating net money');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(report#>'{report,timeline,payments}') day
  WHERE (day->>'received') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (day->>'returned') !~ '^[0-9]+([.][0-9]{1,2})?$'),
  'provider daily amounts obey the two-decimal report client contract');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM jsonb_each_text(money) value
  WHERE value.key IN ('stripe_received','stripe_refunded','disputed','available_after_disputes')
   AND value.value !~ '^[0-9]+([.][0-9]{1,2})?$'), 'Stripe report amounts have canonical cents without display padding');
 PERFORM assert_eq((money->>'stripe_received')::numeric,50::numeric,'Stripe gross is an identified subset of received');
 PERFORM assert_eq((money->>'stripe_refunded')::numeric,20::numeric,'Stripe refunds are a separate identified subset');
 PERFORM assert_eq((money->>'disputed')::numeric,10::numeric,'dispute is not a refund');
 PERFORM assert_eq((money->>'available_after_disputes')::numeric,85::numeric,'report distinguishes cash net and availability');
 PERFORM assert_eq((money->>'external_unattributed')::numeric,25::numeric,'unattributed external value remains visible');
 PERFORM assert_true(report#>'{report,warnings}' @> '[{"code":"external_unattributed","count":1}]'::jsonb,'unknown external attribution is explicit');
 PERFORM assert_eq((SELECT sum((day->>'received')::numeric) FROM jsonb_array_elements(report#>'{report,timeline,payments}') day WHERE day->>'day'='2026-10-20'),125::numeric,'provider occurrence time is converted to the Prague payment day');
 PERFORM assert_eq((SELECT sum((day->>'returned')::numeric) FROM jsonb_array_elements(report#>'{report,timeline,payments}') day WHERE day->>'day'='2026-10-21'),30::numeric,'refund day uses original provider time, never ingest time');
 PERFORM assert_true(NOT report::text LIKE '%acct_%' AND NOT report::text LIKE '%pi_totals%','report exposes aggregate facts without provider account/object identities');
 INSERT INTO eshop.transactions(bank_account_id,amount,currency,date,transaction_type)
 VALUES(bank,5,'CZK',now(),'manual') RETURNING id INTO unpaired_transaction_id;
 BEGIN
  PERFORM public.apply_transaction_pairing(unpaired_transaction_id,pi,'manual','system');RAISE EXCEPTION 'new bank pairing changed Stripe balance';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_BANK_PAIRING_UNSUPPORTED' THEN RAISE; END IF; END;
 PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.transactions WHERE id=unpaired_transaction_id),'unsupported new pairing leaves bank money intact and unassigned');
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type)
 VALUES(bank,pi,99,'EUR',now(),'manual');
 BEGIN
  PERFORM public.refresh_payment_info_totals_internal(pi);
  RAISE EXCEPTION 'foreign currency was accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_FACT_IDENTITY_MISMATCH' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),125::numeric,'failed refresh must not damage summary');
END $$;
