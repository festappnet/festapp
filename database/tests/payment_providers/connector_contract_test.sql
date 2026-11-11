-- A second connector exercises real order creation, receipts and projections.
-- Nothing in this fixture talks to an external provider or moves money.
CREATE FUNCTION public.test_other_payment_provider(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE pi bigint; expires timestamptz:=now()+interval '20 minutes';
BEGIN
 IF p_operation='initialize_payment' THEN
  INSERT INTO eshop.payment_info(amount,currency_code,payment_method)
   VALUES((p_args->>'amount')::numeric,p_args->>'currency','other_gateway') RETURNING id INTO pi;
  RETURN jsonb_build_object('paymentInfoId',pi);
 ELSIF p_operation='create_attempt' THEN
  UPDATE eshop.payment_info SET deadline=expires WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint);
  RETURN jsonb_build_object('expiresAt',expires);
 ELSIF p_operation='projection' THEN RETURN jsonb_build_object('method','other_gateway','status','open','admissionState','pending');
 ELSIF p_operation='attach_source' THEN
  IF p_args->'source' IS DISTINCT FROM '{"test":"sealed"}'::jsonb THEN RAISE EXCEPTION 'wrong provider source'; END IF;
  RETURN NULL;
 ELSIF p_operation='totals' THEN RETURN '{"received":80,"returned":10,"held":5,"invalid":false}';
 ELSIF p_operation='movements' THEN RETURN '[{"kind":"payment","amount_minor":8000,"currency":"CZK","occurred_at":"2026-11-01T12:00:00Z"}]';
 ELSIF p_operation='paid_guard' THEN RETURN '{"code":409,"message":"PROVIDER_CONFIRMATION_REQUIRED"}';
 ELSIF p_operation='unit_feature' THEN RETURN 'false';
 ELSIF p_operation IN ('validate_form','form_editor_fields','unit_fields') THEN RETURN '{}';
 ELSIF p_operation='form_availability' THEN RETURN '{"providerId":"other_gateway","available":true,"configured":true,"recipient":{"connectionId":"12345678-1234-4234-8234-123456789abc"},"supportedSurfaces":["web"]}';
 END IF;
 RAISE EXCEPTION 'unknown test provider operation';
END $$;
REVOKE ALL ON FUNCTION public.test_other_payment_provider(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout)
 VALUES('other_gateway','public.test_other_payment_provider(text,jsonb)'::regprocedure,'otherPaymentSource',true);
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; pt bigint; product bigint; result jsonb; repeated jsonb; payload jsonb;
 ord bigint; pi bigint; totals record; command uuid:=extensions.gen_random_uuid();client uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.organizations(title,data) VALUES('Connector contract','{"DEFAULT_URL":"https://tickets.example"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Connector organizer',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
  VALUES('Connector order',org,u,'connector-'||extensions.gen_random_uuid(),now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,data,is_open,key) VALUES(occ,'{"payments":{"bankEnabled":false,"providerConnections":{"other_gateway":"12345678-1234-4234-8234-123456789abc"}}}',true,extensions.gen_random_uuid()) RETURNING id INTO f;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden) VALUES(pt,occ,'Ticket',123.45,'CZK',false) RETURNING id INTO product;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','connector@example.test','payment_method','other_gateway',
  'otherPaymentSource','{"test":"sealed"}'::jsonb,'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',product)))));
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','a second connector creates through the canonical order command: '||result::text);
 ord:=(result#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO STRICT pi FROM eshop.orders WHERE id=ord;
 PERFORM assert_eq((SELECT payment_method FROM eshop.payment_info WHERE id=pi),'other_gateway','provider identity persisted');
 PERFORM assert_eq(result#>>'{data,payment,method}','other_gateway','projection dispatched to selected provider');
 PERFORM assert_true(NOT (SELECT data ? 'otherPaymentSource' FROM eshop.orders WHERE id=ord),'private source never enters order projection');
 PERFORM assert_true((SELECT bank_account IS NULL AND variable_symbol IS NULL FROM eshop.payment_info WHERE id=pi),'external provider never receives bank instructions');
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pi);
 PERFORM assert_eq(totals.gross_received,80::numeric,'financial totals use connector contribution');
 PERFORM assert_eq(totals.refunded,10::numeric,'refund facts remain separate');
 PERFORM assert_eq(totals.available,65::numeric,'dispute hold is not a refund');
 PERFORM assert_eq(public.mark_order_and_tickets_paid_internal_v1(ord)->>'code','409','provider guard prevents granting tickets');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=ord),'ordered','no browser or unverified callback grants admission');
 PERFORM assert_true(public.form_payment_availability_internal(f)->'available' ? 'other_gateway','availability includes installed connector');
 PERFORM assert_true(public.form_payment_availability_internal(f)->'providers' ? 'other_gateway','availability scoped to provider');
 repeated:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(repeated#>>'{data,order,id}',ord::text,'replay retains original order');
 PERFORM assert_true(NOT has_function_privilege('anon','public.payment_provider_call_internal(text,text,jsonb)','EXECUTE'),'no anonymous dispatcher execution');
 PERFORM assert_true(NOT has_table_privilege('authenticated','eshop.payment_providers','INSERT,UPDATE,DELETE'),'clients cannot install connectors');
 BEGIN
  PERFORM public.payment_provider_call_internal('uninstalled','projection','{}');
  RAISE EXCEPTION 'unknown provider was accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_PROVIDER_UNAVAILABLE' THEN RAISE; END IF; END;
END $$;
