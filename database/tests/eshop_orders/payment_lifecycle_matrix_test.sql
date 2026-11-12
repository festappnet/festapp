-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Target contracts complementing the three independent regression assertions.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(300); oid bigint:=(x->>'order')::bigint;
 h jsonb; v bigint;
BEGIN
 PERFORM pg_temp.payment_pair(x,200);
 h:=pg_temp.payment_history(oid);
 SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 PERFORM pg_temp.payment_edit(x,200);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'discount below original deposit uses current total as threshold');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,'discount below deposit restores admission');
 PERFORM assert_eq((SELECT deposit_amount FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),300::numeric,'discount retains agreed deposit snapshot');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'discount crossing eligibility invalidates exactly once');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets' AND source_version=v+1),1::bigint,'discount creates one final-version ticket intent');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'paid',200);
 h:=pg_temp.payment_history(oid);
 PERFORM public.recalculate_order_payment_status(oid);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'bank reconciliation uses same capped deposit threshold');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'repeated financial reconciliation adds no version');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'repeated financial reconciliation adds no history');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(300); oid bigint:=(x->>'order')::bigint; h jsonb; v bigint; paid_before numeric;
BEGIN
 SELECT paid INTO paid_before FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 h:=pg_temp.payment_history(oid); SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 PERFORM pg_temp.payment_edit(x,0);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'zero total is free despite retained deposit');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,'free order grants ordinary admission');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),paid_before,'free edit does not invent money');
 PERFORM assert_eq((SELECT deposit_amount FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),300::numeric,'free edit does not rewrite deposit');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'free transition and edit share one version bump');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets' AND source_version=v+1),1::bigint,'free transition enqueues exactly one current ticket intent');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'paid',0);
 PERFORM public.recalculate_order_payment_status(oid);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'subsequent bank reconciliation retains free eligibility');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint;
 h jsonb; v bigint; n bigint; command uuid:=gen_random_uuid(); result jsonb; receipt jsonb;
BEGIN
 PERFORM pg_temp.payment_pair(x,1200);
 h:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_edit(x,1100,command);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'overpayment covers raised total');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),1200::numeric,'product edit preserves ledger total');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'paid',1100);
 PERFORM pg_temp.payment_accept_tickets(x);
 h:=pg_temp.payment_history(oid);
 SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 SELECT count(*) INTO n FROM public.email_messages WHERE order_id=oid;
 -- A second movement must update money without resending already delivered tickets.
 PERFORM pg_temp.payment_pair(x,50);
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),1250::numeric,'second movement updates actual received money');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'second payment preserves delivered order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'sent'::text,'second payment preserves sent admission');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v,'second payment without eligibility change adds no version');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid),n,'second payment creates no duplicate intent');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'second payment creates no order snapshot');
 -- An unchanged new command and a receipted replay must preserve sent as well.
 result:=pg_temp.payment_edit(x,1100);
 receipt:=pg_temp.payment_edit(x,1100,command);
 PERFORM assert_eq(receipt->>'status','applied'::text,'original applied command is replayable after delivery');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'same-price command preserves sent');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v,'same-price and replay create no invalidation');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid),n,'same-price and replay create no email');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'same-price and replay create no snapshot');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint;
 h jsonb; v bigint; used_id bigint; cancelled_id bigint;
BEGIN
 PERFORM pg_temp.payment_pair(x,1000); PERFORM pg_temp.payment_accept_tickets(x);
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'used') RETURNING id INTO used_id;
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'storno') RETURNING id INTO cancelled_id;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,used_id),(oid,cancelled_id);
 SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid; h:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_edit(x,900);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'price change preserving eligibility keeps sent order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'sent'::text,'eligible price edit keeps sent ticket');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_id),'used'::text,'eligible edit protects used admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=cancelled_id),'storno'::text,'eligible edit protects cancelled admission');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'content edit invalidates old versions even while sent');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'sent',900);
 h:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_edit(x,1100);
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_id),'used'::text,'debt edit protects used admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=cancelled_id),'storno'::text,'debt edit protects cancelled admission');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'ordered',1100);
 PERFORM pg_temp.payment_pair(x,100);
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,'new payment after edited debt restores ordinary admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_id),'used'::text,'restored payment protects used admission');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=cancelled_id),'storno'::text,'restored payment protects cancelled admission');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint; h jsonb; result jsonb;
BEGIN
 UPDATE eshop.orders SET state='expired' WHERE id=oid;
 -- Expiration belongs to the order; its unconsumed ticket remains ordered.
 h:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_pair(x,1000);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'late bank payment restores expired bank order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,'late bank payment restores expired bank ticket');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'late bank payment does not fabricate history');
 SET LOCAL ROLE authenticated;
 result:=public.storno_order_client_sync_v1(oid,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied'::text,'cancel before later bank fact');
 h:=pg_temp.payment_history(oid);
 PERFORM pg_temp.payment_pair(x,100);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno'::text,'later bank money cannot restore cancelled order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'storno'::text,'later bank money cannot restore cancelled admission');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'later cancelled-order bank fact leaves history intact');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint; h jsonb; n bigint; result jsonb; paid_before numeric;
BEGIN
 SELECT paid INTO paid_before FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 h:=pg_temp.payment_history(oid); SELECT count(*) INTO n FROM public.email_messages WHERE order_id=oid;
 SET LOCAL ROLE authenticated;
 result:=public.update_order_and_tickets_to_paid_ws(oid);
 RESET ROLE;
 PERFORM assert_eq(result->>'code','200'::text,'manual mark-paid keeps authorized operation');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'manual mark-paid changes order state');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'paid'::text,'manual mark-paid changes ordinary ticket state');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),paid_before,'manual mark-paid does not manufacture bank facts');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid),n,'manual mark-paid does not send automatically');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'manual mark-paid preserves established no-snapshot contract');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oid bigint:=(x->>'order')::bigint;
 connection uuid; snapshot jsonb; command uuid:=gen_random_uuid(); rejected boolean:=false;
BEGIN
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 SELECT o.organization,o.unit,'acct_'||replace(gen_random_uuid()::text,'-',''),false,'connected' FROM public.occasions o
 WHERE o.id=(x->>'occasion')::bigint RETURNING id INTO connection;
 UPDATE eshop.payment_info SET payment_method='stripe',stripe_connection_id=connection,bank_account=NULL,
  variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL WHERE id=(x->>'payment')::bigint;
 snapshot:=jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
  'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=(x->>'payment')::bigint),'history',pg_temp.payment_history(oid));
 BEGIN
  PERFORM pg_temp.payment_edit(x,0,command);
 EXCEPTION WHEN OTHERS THEN
  IF position('STRIPE_ORDER_PRICE_IMMUTABLE' in SQLERRM)>0 THEN rejected:=true; ELSE RAISE; END IF;
 END;
 PERFORM assert_true(rejected,'product edit rejects Stripe price mutation at existing provider boundary');
 PERFORM public.recalculate_order_payment_status(oid);
 PERFORM assert_eq(jsonb_build_object('order',(SELECT to_jsonb(o) FROM eshop.orders o WHERE id=oid),
  'payment',(SELECT to_jsonb(p) FROM eshop.payment_info p WHERE id=(x->>'payment')::bigint),'history',pg_temp.payment_history(oid)),snapshot,
  'Stripe rejection and bank reconciliation preserve provider-owned data');
 PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts WHERE command_id=command),0::bigint,'rejected Stripe edit leaves no receipt');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); result jsonb; oid bigint; waiting bigint; h jsonb;
BEGIN
 UPDATE public.forms SET participant_capacity=1,waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=(x->>'form')::bigint;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 result:=public.execute_waitlist_command_client_sync_v1('register',jsonb_build_object(
  'form',(SELECT key FROM public.forms WHERE id=(x->>'form')::bigint),'email','waiting@example.invalid',
  'tickets',jsonb_build_array(jsonb_build_object('fields','[]'::jsonb))),gen_random_uuid(),gen_random_uuid(),NULL,
  jsonb_build_array(jsonb_build_object('orderId',NULL,'recipient','waiting@example.invalid','templateCode','waitlist_confirmation',
   'tokenHash',encode(extensions.digest('payment-lifecycle-waiting','sha256'),'hex'),'contentHash',repeat('f',64),
   'sealed',jsonb_build_object('ciphertext','sealed-test-double'))));
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(result#>>'{data,code}','200'::text,'real waitlist registration succeeds: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT DISTINCT ticket INTO STRICT waiting FROM eshop.order_product_ticket WHERE "order"=oid;
 h:=pg_temp.payment_history(oid);
 PERFORM public.recalculate_order_payment_status(oid);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'waitlisted'::text,'reconciliation cannot pay a waiting order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=waiting),'waitlisted'::text,'reconciliation cannot revive waiting admission');
 PERFORM assert_true((SELECT ticket_symbol IS NULL FROM eshop.tickets WHERE id=waiting),'waiting ticket still has no admission symbol');
 PERFORM assert_true((SELECT payment_info IS NULL FROM eshop.orders WHERE id=oid),'waiting order still has no finance');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'waiting reconciliation changes no history');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'),0::bigint,'waiting reconciliation creates no admission delivery');
END $$;

-- Seat swaps share product-edit eligibility, content and history ownership.
CREATE FUNCTION pg_temp.swap_target(x jsonb, p_price numeric, p_same_product boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE pid bigint; sid bigint;
BEGIN
 pid:=(x->>'product')::bigint;
 IF NOT p_same_product THEN
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
  SELECT occasion,product_type,'Premium seat',p_price,currency_code,false FROM eshop.products WHERE id=pid RETURNING id INTO pid;
 END IF;
 INSERT INTO eshop.spots(occasion,blueprint,product,title)
 SELECT occasion,blueprint,pid,'6G' FROM eshop.spots WHERE id=(x->>'spot')::bigint RETURNING id INTO sid;
 RETURN sid;
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_attach_spot(pg_temp.payment_fixture()); oid bigint:=(x->>'order')::bigint;
 sid bigint; cmd uuid:=gen_random_uuid(); r jsonb; h jsonb; v bigint; summary jsonb;
BEGIN
 PERFORM pg_temp.payment_pair(x,1000); PERFORM pg_temp.payment_accept_tickets(x);
 -- The sent snapshot is the actual customer baseline used by product editing.
 UPDATE eshop.orders_history SET data=data||'{"is_sent_to_customer":true}'::jsonb WHERE "order"=oid AND state='sent';
 sid:=pg_temp.swap_target(x,1000,true);
 h:=pg_temp.payment_history(oid); SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 r:=public.preview_blueprint_swap((x->>'spot')::bigint,sid);
 PERFORM assert_eq((r->>'code')::int,200,'same price swap preview succeeds');
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'preview leaves history untouched');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v,'preview leaves email version untouched');
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,cmd);
 PERFORM assert_eq(r->>'status','applied'::text,'same price swap commits');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'same price swap retains sent order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'sent'::text,'same price swap retains sent ticket');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'seat change invalidates email content once');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'sent',1000);
 summary:=public.get_order_change_summary_v1(oid);
 PERFORM assert_true((summary->>'hasChanges')::boolean,'seat-only change exposes update email button');
 PERFORM assert_eq(summary#>>'{productChanges,0,changed,0,to,spot_title}','6G'::text,'change summary includes destination seat');
 h:=pg_temp.payment_history(oid);
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,cmd);
 PERFORM assert_eq(pg_temp.payment_history(oid),h,'receipt replay adds no history');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'receipt replay adds no email version');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_attach_spot(pg_temp.payment_fixture()); oid bigint:=(x->>'order')::bigint;
 sid bigint; r jsonb; h jsonb;
BEGIN
 PERFORM pg_temp.payment_pair(x,1000); PERFORM pg_temp.payment_accept_tickets(x);
 sid:=pg_temp.swap_target(x,1500); h:=pg_temp.payment_history(oid);
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied'::text,'higher price product swap commits');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'extra balance demotes order');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'ordered'::text,'extra balance demotes ticket');
 PERFORM assert_eq((SELECT amount-paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),500::numeric,'extra balance is actual price delta');
 PERFORM assert_eq((SELECT product FROM eshop.order_product_ticket WHERE ticket=(x->>'ticket')::bigint),(SELECT product FROM eshop.spots WHERE id=sid),'destination product replaces original link');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'ordered',1500);
 PERFORM assert_true((public.get_order_change_summary_v1(oid)->>'hasChanges')::boolean,'different product exposes update email button');
 PERFORM assert_eq(public.get_products_for_ticket((x->>'ticket')::bigint)#>>'{data,order_history,is_newer_version_available}','true'::text,'product editor receives pending update through its existing RPC');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_update'),0::bigint,'swap does not automatically send an update email');
 PERFORM public.enqueue_order_email('TICKET_ORDER_UPDATE',jsonb_build_object('order_id',oid),
  (x->>'organization')::bigint,(x->>'occasion')::bigint,(SELECT unit FROM public.occasions WHERE id=(x->>'occasion')::bigint));
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_update'),1::bigint,'manual update reuses the canonical email queue');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_attach_spot(pg_temp.payment_fixture(300)); oid bigint:=(x->>'order')::bigint; sid bigint; r jsonb;
BEGIN
 PERFORM pg_temp.payment_pair(x,300); PERFORM pg_temp.payment_accept_tickets(x);
 sid:=pg_temp.swap_target(x,1500);
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied'::text,'deposit product swap commits');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'saved deposit preserves sent eligibility');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=(x->>'ticket')::bigint),'sent'::text,'saved deposit preserves ticket eligibility');
 PERFORM assert_eq((SELECT deposit_amount FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),300::numeric,'swap preserves agreed deposit');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_attach_spot(pg_temp.payment_fixture()); oid bigint:=(x->>'order')::bigint;
 sid bigint; r jsonb; h jsonb; v bigint; conn uuid;
BEGIN
 PERFORM pg_temp.payment_pair(x,1000); PERFORM pg_temp.payment_accept_tickets(x);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state)
 SELECT organization,unit,'acct_'||replace(gen_random_uuid()::text,'-',''),false,'connected' FROM public.occasions WHERE id=(x->>'occasion')::bigint RETURNING id INTO conn;
 -- Online providers keep their settlement owner even for an equal-price move.
 UPDATE eshop.payment_info SET payment_method='stripe',stripe_connection_id=conn,bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL WHERE id=(x->>'payment')::bigint;
 sid:=pg_temp.swap_target(x,1000);
 h:=pg_temp.payment_history(oid); SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied'::text,'online equal-price product swap commits');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'online seat change preserves sent order');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'online seat change invalidates customer content');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'sent',1000);
 UPDATE eshop.products SET price=1500 WHERE id=(SELECT product FROM eshop.spots WHERE id=(x->>'spot')::bigint);
 r:=public.preview_blueprint_swap(sid,(x->>'spot')::bigint);
 PERFORM assert_eq(r->>'reason','STRIPE_ORDER_PRICE_IMMUTABLE'::text,'online price-changing swap remains blocked');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.payment_attach_spot(pg_temp.payment_fixture()); oid bigint:=(x->>'order')::bigint;
 sid bigint; r jsonb; h jsonb; v bigint; tid bigint; item bigint;
BEGIN
 sid:=pg_temp.swap_target(x,1500);
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'sent') RETURNING id INTO tid;
 INSERT INTO eshop.order_product_ticket("order",ticket,product)
 SELECT oid,tid,product FROM eshop.spots WHERE id=sid RETURNING id INTO item;
 UPDATE eshop.spots SET order_product_ticket=item WHERE id=sid;
 UPDATE eshop.orders SET price=2500,data=jsonb_set(data,'{tickets}',data->'tickets'||jsonb_build_array(
  jsonb_build_object('id',tid,'products',jsonb_build_array(public._swap_spots_generate_product_json((SELECT product FROM eshop.spots WHERE id=sid),sid))))) WHERE id=oid;
 UPDATE eshop.payment_info SET amount=2500 WHERE id=(x->>'payment')::bigint;
 PERFORM pg_temp.payment_pair(x,2500); PERFORM pg_temp.payment_accept_tickets(x);
 h:=pg_temp.payment_history(oid); SELECT email_payment_version INTO v FROM eshop.orders WHERE id=oid;
 r:=public.swap_spot_tickets_client_sync_v1((x->>'spot')::bigint,sid,gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied'::text,'different-price seats within one order swap');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),2500::numeric,'same-order swap keeps final total');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent'::text,'same-order swap uses final eligibility');
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),v+1,'same-order swap reconciles only once');
 PERFORM pg_temp.payment_assert_edit_history(x,h,'sent',2500);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets' AND source_version=v+1),0::bigint,'sent swap does not automatically send another email');
END $$;
