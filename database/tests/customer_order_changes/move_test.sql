-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/customer_order_changes/fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); oid bigint:=(x->>'order')::bigint; fid bigint:=(x->>'form')::bigint; oc bigint:=(x->>'occasion')::bigint;
 target bigint; pt bigint; product bigint; field bigint; policy jsonb; payload jsonb; token text; preview jsonb; command uuid:=extensions.gen_random_uuid(); result jsonb;
 before_payment jsonb; old_symbol text; new_symbol text; hidden bigint; scan_code text:='TEST_'||extensions.gen_random_uuid();
BEGIN
 UPDATE eshop.orders SET data=jsonb_set(data,'{fields}',jsonb_build_array(jsonb_build_object(x->>'field','+420 777 123 456'))) WHERE id=oid;
 UPDATE public.forms SET term_start_at=now()+interval '3 days',term_end_at=now()+interval '3 days 2 hours' WHERE id=fid;
 INSERT INTO public.forms(occasion,title,bank_account,is_open,participant_capacity,term_start_at,term_end_at)
 VALUES(oc,'Next evening',(x->>'bank')::bigint,true,1,now()+interval '4 days',now()+interval '4 days 2 hours') RETURNING id INTO target;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Target admission','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,title,product_type,price,currency_code,is_hidden,maximum) VALUES(oc,'Next evening ticket',pt,1000,'CZK',false,1) RETURNING id INTO product;
 INSERT INTO public.form_fields(form,title,type,product_type,is_ticket_field,is_hidden,is_required) VALUES(target,'Admission','product_type',pt,true,false,true);
 INSERT INTO public.form_fields(form,title,type,is_ticket_field,is_hidden,is_required) VALUES(target,'Phone','phone',false,false,true) RETURNING id INTO field;
 PERFORM public.save_customer_order_policy_internal(target,jsonb_build_object('move',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day','targets','[]'::jsonb)));
 policy:=public.customer_order_policy_internal(fid)->'policy';
 policy:=policy||jsonb_build_object('move',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day','targets',jsonb_build_array(
  jsonb_build_object('formId',target,'products',jsonb_build_object(x->>'product',product),'fields',jsonb_build_object(x->>'field',field)))));
 PERFORM public.save_customer_order_policy_internal(fid,policy);
 UPDATE public.forms SET term_end_at=NULL WHERE id=target;
 PERFORM assert_true((public.order_term_occasion_internal(oid)).end_time IS NOT NULL,'source term has real end');
 PERFORM assert_eq(public.customer_move_preview_internal(oid,target)->>'reason','term_unavailable','unknown target end requires manual review');
 UPDATE public.forms SET term_end_at=term_start_at+interval '2 hours' WHERE id=target;
 PERFORM pg_temp.payment_pair(x,1000);
 SELECT to_jsonb(pi) INTO before_payment FROM eshop.payment_info pi WHERE id=(x->>'payment')::bigint;
 SELECT ticket_symbol INTO old_symbol FROM eshop.tickets WHERE id=(x->>'ticket')::bigint;
 payload:=jsonb_build_object('targetFormId',target,'reason','Another date');token:=pg_temp.customer_cap(x,'move',payload);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'move',payload,command);
 PERFORM assert_eq(preview->>'effect','move','equal-price non-seated mapped term can move automatically');
 result:=public.customer_order_change_gateway('command',token,NULL,'move',payload,command,preview->>'fingerprint');
 result:=public.customer_order_change_gateway('command',token,NULL,'move',payload,command,preview->>'fingerprint');
 RESET ROLE;
 PERFORM assert_eq((SELECT form FROM eshop.orders WHERE id=oid),target,'order moves to explicit target');
 PERFORM assert_eq((SELECT to_jsonb(pi) FROM eshop.payment_info pi WHERE id=(x->>'payment')::bigint),before_payment,'every original payment field remains unchanged');
 PERFORM assert_eq((SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=oid AND ticket=(x->>'ticket')::bigint),1::bigint,'existing ticket identity retained');
 PERFORM assert_eq((SELECT x.product FROM eshop.order_product_ticket x WHERE x."order"=oid),product,'products use explicit mapping');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(fid)->>'occupiedPeople')::bigint,0::bigint,'source allocation released');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal(target)->>'occupiedPeople')::bigint,1::bigint,'target allocation acquired');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),1000::numeric,'move cannot reprice');
 result:=public.get_customer_order_overview_internal(x->>'readToken',oid);
 PERFORM assert_eq(result->>'code','200','existing email overview capability follows the same order');
 SELECT ticket_symbol INTO new_symbol FROM eshop.tickets WHERE id=(x->>'ticket')::bigint;
 PERFORM assert_true(new_symbol<>old_symbol,'old QR rotated with canonical generator');
 INSERT INTO public.occasions_hidden(secret) VALUES(scan_code) RETURNING id INTO hidden;
 UPDATE public.occasions SET occasion_hidden=hidden WHERE id=oc;
 INSERT INTO public.scanner_settings(occasion_id,config) VALUES(oc,public.scanner_default_settings_internal(oc));
 result:=public.scan_ticket(old_symbol,scan_code);
 PERFORM assert_true(result->>'code'<>'200','old PDF QR cannot verify');
 result:=public.scan_ticket(new_symbol,scan_code);
 PERFORM assert_eq(result->>'code','200','new QR verifies through existing scanner owner');
 PERFORM assert_eq((public.order_term_occasion_internal(oid)).start_time,(SELECT term_start_at FROM public.forms WHERE id=target),'PDF and wallet use target actual term');
END $$;
