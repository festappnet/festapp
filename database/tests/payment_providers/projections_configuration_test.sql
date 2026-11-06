-- This rollback-only matrix unregisters providers. Remove other disposable
-- fixtures' financial rows first, retaining the real registry foreign key.
TRUNCATE eshop.payment_info CASCADE;

CREATE FUNCTION public.test_isolated_provider(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_operation='form_availability' THEN RETURN '{"providerId":"aaa_gateway","configured":true,"available":true,"supportedSurfaces":["web"],"recipient":{"connectionId":"12345678-1234-4234-8234-123456789abc"},"bank":false,"reservationSeconds":1}'; END IF;
 IF p_operation='unit_fields' THEN RETURN '{"stripe_preview_enabled":"collision","other":"private namespace"}'; END IF;
 IF p_operation='form_editor_fields' THEN RETURN '{"stripeRecipient":"collision"}'; END IF;
 IF p_operation='unit_feature' THEN RETURN 'false'; END IF;
 RAISE EXCEPTION 'unexpected operation';
END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field)
 VALUES('aaa_gateway','public.test_isolated_provider(text,jsonb)'::regprocedure,'aaaSource');
CREATE FUNCTION public.test_failed_provider(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$ BEGIN RAISE EXCEPTION 'private provider diagnostic'; END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field)
 VALUES('zzz_failed','public.test_failed_provider(text,jsonb)'::regprocedure,'zzzSource');
DO $$
DECLARE fx jsonb:=public.scanner_test_fixture(1); f bigint:=(fx->>'form')::bigint; u bigint; value jsonb; before_value jsonb; saved jsonb; recipient_id text:='12345678-1234-4234-8234-123456789abc';
BEGIN
 SELECT unit INTO u FROM public.occasions WHERE id=(fx->>'occasion')::bigint;
 value:=public.form_payment_availability_internal(f);
 PERFORM assert_true(value->'available' ? 'bank','unconfigured connector never removes bank');
 PERFORM assert_true(NOT value->'available' ? 'aaa_gateway','unconfigured provider cannot advertise availability');
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',true,'providerConnections',jsonb_build_object('aaa_gateway',recipient_id))) WHERE id=f;
 value:=public.form_payment_availability_internal(f);
 PERFORM assert_true(value->'available' ?& ARRAY['bank','aaa_gateway'],'bank and explicit second provider coexist');
 PERFORM assert_eq(value->>'reservationSeconds','1860','provider cannot override sales policy');
 PERFORM assert_true(value#>'{bank,available}'='true'::jsonb,'provider cannot overwrite bank namespace');
 PERFORM assert_true(value#>'{providers,aaa_gateway,available}'='true'::jsonb,'canonical provider shape');
 PERFORM assert_true(value#>'{configured,stripe}'='false'::jsonb,'legacy root derives only Stripe');
 PERFORM assert_eq(value#>>'{providers,zzz_failed,reason,code}','not_configured','unconfigured failure is isolated');
 PERFORM assert_true(public.provider_unit_features_internal(u)->'zzz_failed'='false'::jsonb,'failed provider cannot block feature reads');
 PERFORM assert_eq(public.provider_unit_public_fields_internal(u)#>>'{providerFields,zzz_failed,reason,code}','provider_unavailable','unit diagnostic is namespaced');
 PERFORM assert_eq(public.provider_form_editor_fields_internal(u,(fx->>'occasion')::bigint,false)#>>'{providerEditorFields,zzz_failed,reason,code}','provider_unavailable','editor isolates an unrelated provider failure');
 before_value:=value;
 DELETE FROM eshop.payment_providers WHERE provider_key='stripe';
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'bank',before_value->'bank','bank without Stripe is unchanged');
 value:=public.provider_unit_public_fields_internal(u);
 PERFORM assert_true(NOT value ? 'stripe_preview_enabled','other provider cannot publish Stripe root fields');
 PERFORM assert_eq(value#>>'{providerFields,aaa_gateway,stripe_preview_enabled}','collision','colliding field stays in its namespace');
 saved:=jsonb_build_object('bankEnabled',false,'stripeConnectionId',recipient_id,'providerConnections',jsonb_build_object('aaa_gateway',recipient_id));
 -- Restore registration only for legacy alias validation.
 INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId');
 value:=public.merge_form_payments_internal(saved,NULL);
 PERFORM assert_true(NOT value ? 'stripeConnectionId','only canonical provider map is stored');
 PERFORM assert_eq(value#>>'{providerConnections,stripe}',recipient_id,'legacy recipient preserved');
 value:=public.merge_form_payments_internal(saved,'{"bankEnabled":true}');
 PERFORM assert_true(NOT (value->'providerConnections') ? 'stripe','legacy omission explicitly removes only Stripe');
 PERFORM assert_eq(value#>>'{providerConnections,aaa_gateway}',recipient_id,'legacy save preserves another binding');
 PERFORM assert_eq(public.merge_form_payments_internal(saved,NULL),public.merge_form_payments_internal(public.merge_form_payments_internal(saved,NULL),NULL),'normalization is idempotent');
 value:=public.merge_form_payments_internal(saved,'{"bankEnabled":true,"providerConnections":{}}');
 PERFORM assert_eq(value->'providerConnections','{}'::jsonb,'modern revisioned snapshot can explicitly remove all bindings');
 BEGIN
  PERFORM public.merge_form_payments_internal(saved,jsonb_build_object('stripeConnectionId','22345678-1234-4234-8234-123456789abc','providerConnections',jsonb_build_object('stripe',recipient_id)));
  RAISE EXCEPTION 'conflicting recipient accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_RECIPIENT_CONFLICT' THEN RAISE; END IF; END;
 value:=public.normalize_setup_payments_internal(jsonb_build_object('paymentMethod','both','formDraft',jsonb_build_object('data',jsonb_build_object('payments',saved))));
 PERFORM assert_true(NOT value ? 'paymentMethod','both is not stored as another authority');
 PERFORM assert_eq(value#>>'{payments,providerConnections,aaa_gateway}',recipient_id,'draft roundtrip preserves provider identity');
 PERFORM assert_true(public.normalize_setup_payments_internal('{"paymentMethod":"stripe"}')->'paymentRepairRequired'='true'::jsonb,'ambiguous draft requires repair');
 DELETE FROM eshop.payment_providers WHERE handler IS NOT NULL;
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','["bank"]'::jsonb,'bank works with zero online providers');
END $$;
