-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(200); f bigint:=(x->>'form')::bigint; oc bigint:=(x->>'occasion')::bigint;
 result jsonb; payload jsonb; pi eshop.payment_info; oid bigint; ticket bigint; edit_scope jsonb; first_deadline timestamptz;
BEGIN
 -- An account with unknown currencies must not advertise a payable bank route.
 UPDATE eshop.bank_accounts SET supported_currencies=NULL WHERE id=(x->>'bank')::bigint;
 PERFORM assert_true(NOT (public.form_payment_availability_internal(f)->'available' ? 'bank'),'unknown bank currency support fails closed');
 UPDATE eshop.bank_accounts SET supported_currencies=ARRAY['EUR'] WHERE id=(x->>'bank')::bigint;
 PERFORM assert_true(NOT (public.form_payment_availability_internal(f)->'available' ? 'bank'),'unsupported bank currency fails closed');
 UPDATE eshop.bank_accounts SET supported_currencies=ARRAY['CZK'] WHERE id=(x->>'bank')::bigint;
 PERFORM assert_true(public.form_payment_availability_internal(f)->'available' ? 'bank','eligible account remains available');
 UPDATE eshop.bank_accounts SET account_number='CZ6508000000192000145399',account_number_human_readable='19-2000145399/0800' WHERE id=(x->>'bank')::bigint;
 UPDATE public.forms SET deadline_duration_seconds=NULL,data='{}' WHERE id=f;
 UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"deadline_duration_seconds":100}]' WHERE id=oc;
 PERFORM assert_eq(public.resolve_form_payment_policy_internal(f,'bank'),'{"mode":"custom","durationSeconds":100}'::jsonb,'NULL legacy duration inherits event');
 UPDATE public.forms SET deadline_duration_seconds=0,data='{"payment_deadline":{"mode":"custom"}}' WHERE id=f;
 PERFORM assert_eq(public.resolve_form_payment_policy_internal(f,'bank'),'{"mode":"custom","durationSeconds":0}'::jsonb,'zero duration is immediate, not none');
 UPDATE public.forms SET deadline_duration_seconds=NULL,data='{"payments":{"bankEnabled":true},"payment_deadline":{"mode":"inherit"}}' WHERE id=f;
 UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"payment_deadline":{"mode":"none"}},{"code":"deposit","deposit_deadline_days":7}]' WHERE id=oc;
 PERFORM assert_eq(public.resolve_form_payment_policy_internal(f,'bank'),'{"mode":"none"}'::jsonb,'new forms inherit explicit event none');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','none@example.invalid','payment_method','bank',
  'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 SET LOCAL ROLE authenticated;
 result:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied','bank none checkout: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid);
 PERFORM assert_true(pi.deadline IS NULL AND pi.deposit_deadline IS NULL,'none eliminates both deadlines with deposit feature');
 PERFORM assert_eq(pi.deposit_amount,200::numeric,'bank deposit amount preserved');
 PERFORM assert_true(public.customer_order_payment_internal(oid)->'qrPayment'<>'null'::jsonb,'bank none retains bank QR data');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=oid AND message_kind='order_reminder'),'bank none never queues ordinary or deposit reminder');
 -- Free cash still uses the canonical free lifecycle and keeps its method on repricing.
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}',bank_account=NULL WHERE id=f;
 UPDATE eshop.products SET price=0,data=data-'deposit' WHERE id=(x->>'product')::bigint;
 SET LOCAL ROLE authenticated;
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{payment_method}','"cash"'),gen_random_uuid(),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied','free cash checkout: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq(public.customer_order_payment_internal(oid)->>'status','free','zero price has no payment request');
 SELECT DISTINCT t.ticket INTO ticket FROM eshop.order_product_ticket t WHERE t."order"=oid;
 edit_scope:=x||jsonb_build_object('order',oid,'ticket',ticket);
 PERFORM pg_temp.payment_edit(edit_scope,250.50);
 SELECT * INTO pi FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid);
 PERFORM assert_eq(pi.payment_method,'cash','free-to-paid repricing retains cash identity');
 PERFORM assert_true(pi.bank_account IS NULL AND pi.variable_symbol IS NULL AND pi.deadline IS NULL,'free-to-paid cash never creates bank instructions');
 PERFORM assert_eq(public.customer_order_payment_internal(oid)->>'status','unpaid','positive repricing does not invent received money');
 -- Historical orders without the snapshot alone retain the documented bounded legacy calculation.
 UPDATE eshop.payment_info SET data=data-'payment_policy' WHERE id=(x->>'payment')::bigint;
 UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"deadline_duration_seconds":120}]' WHERE id=oc;
 PERFORM pg_temp.payment_edit(x,1200);
 PERFORM assert_eq((SELECT deadline FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),now()+interval '120 seconds','legacy repricing alone reads current event policy');
END $$;
