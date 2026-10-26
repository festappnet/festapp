-- Administrative entrypoints delegate the same checkout and single receipt as
-- public/UI creation. No ticket/payment shadow writer or second intent exists.
CREATE OR REPLACE FUNCTION public.check_form_order_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_write boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,p_write);
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.form_order_input_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>1048576
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_input) k WHERE k NOT IN ('email','fields','ticket','lang','form','payment_method'))
  OR jsonb_typeof(p_input->'ticket') IS DISTINCT FROM 'array' OR jsonb_array_length(p_input->'ticket') NOT BETWEEN 1 AND 1000
  OR nullif(p_input->>'email','') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid administrative order'; END IF;
 IF p_input ? 'form' AND p_input->>'form' IS DISTINCT FROM (SELECT key::text FROM public.forms WHERE id=p_form) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form key'; END IF;
 IF p_input ? 'payment_method' AND p_input->>'payment_method' IS DISTINCT FROM 'bank' THEN
  RAISE invalid_parameter_value USING MESSAGE='administrative card payment unsupported'; END IF;
 RETURN p_input||jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=p_form),'payment_method','bank');
END $$;
CREATE OR REPLACE FUNCTION public.form_order_quote_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('newOrder',jsonb_build_object('amount',o.price::text,'currencyCode',o.currency_code,
  'state',o.state,'paymentMethod',p.payment_method,'bankAccountId',p.bank_account,
  'bankAccountNumber',ba.account_number,'bankAccountDisplay',ba.account_number_human_readable,
  'ticketCount',(SELECT count(DISTINCT ticket) FROM eshop.order_product_ticket WHERE "order"=o.id)))
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info LEFT JOIN eshop.bank_accounts ba ON ba.id=p.bank_account WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.form_order_facts_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('form',(SELECT to_jsonb(f)-ARRAY['key','link','created_at'] FROM public.forms f WHERE id=p_form),
  'fields',snap->'fields','products',snap->'products','productTypes',snap->'productTypes')
 FROM (SELECT public.get_form_authoring_snapshot_internal(p_form) snap) s;
$$;
CREATE OR REPLACE FUNCTION public.preview_form_order_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE result jsonb; quote jsonb; facts jsonb; snap jsonb;
BEGIN
 facts:=public.form_order_facts_internal(p_form);
 BEGIN
  result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),extensions.gen_random_uuid(),extensions.gen_random_uuid(),NULL);
  IF (result->>'code')::int=200 THEN quote:=public.form_order_quote_internal((result#>>'{data,order,id}')::bigint); END IF;
  RAISE SQLSTATE 'P0F90' USING MESSAGE='rollback administrative order quote';
 EXCEPTION WHEN SQLSTATE 'P0F90' THEN NULL; END;
 IF (result->>'code')::int<>200 THEN RETURN jsonb_build_object('code',422,'reason','ORDER_NOT_CREATABLE'); END IF;
 RETURN jsonb_build_object('code',200,'quote',quote,'confirmationHash',encode(extensions.digest(
  jsonb_build_object('actor',auth.uid(),'form',p_form,'input',p_input,'facts',facts,'quote',quote)::text,'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.lock_form_order_internal(p_occasion bigint,p_form bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Same parent order as actual checkout and the administration seat flow.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 PERFORM 1 FROM eshop.product_types WHERE id IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.products WHERE product_type IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.preview_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 RETURN public.preview_form_order_internal(p_form,p_input)||jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid());
END $$;
CREATE OR REPLACE FUNCTION public.create_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb,
 p_confirmation_hash text,p_expected_actor uuid,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior jsonb; receipt_status text; preview jsonb; quote jsonb; result jsonb; context jsonb;
BEGIN
 IF p_expected_actor IS DISTINCT FROM auth.uid() OR auth.uid() IS NULL OR p_confirmation_hash IS NULL OR p_confirmation_hash !~ '^[a-f0-9]{64}$' THEN
  RAISE insufficient_privilege USING MESSAGE='confirmed order actor required'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 SELECT response,status INTO prior,receipt_status FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid()
  AND occasion=p_occasion AND command_name='inventory.order.create';
 IF receipt_status='expired' THEN RETURN jsonb_build_object('code',410,'errorCode','COMMAND_EXPIRED_DO_NOT_REPLAY'); END IF;
 IF prior IS NOT NULL THEN quote:=prior#>'{data,adminQuote}';
 ELSE
  preview:=public.preview_form_order_internal(p_form,p_input);
  IF preview->>'confirmationHash' IS DISTINCT FROM p_confirmation_hash THEN
   RETURN jsonb_build_object('code',409,'errorCode','ORDER_CHANGED_REPREVIEW_REQUIRED'); END IF;
  quote:=preview->'quote';
 END IF;
 context:=jsonb_build_object('occasion',p_occasion,'organization',p_organization,'unit',p_unit,'form',p_form,
  'actor',auth.uid(),'confirmationHash',p_confirmation_hash,'quote',quote);
 result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),p_command_id,p_client_id,context);
 IF prior IS NULL AND (result->>'code')::int=200 AND
   public.form_order_quote_internal((result#>>'{data,order,id}')::bigint) IS DISTINCT FROM quote THEN
  RAISE serialization_failure USING MESSAGE='order quote changed during creation'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 RETURN result||jsonb_build_object('data',(result->'data')||jsonb_build_object('quote',result#>'{data,adminQuote}',
  'adminScope',jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid())));
END $$;
REVOKE ALL ON FUNCTION public.check_form_order_scope_internal(bigint,bigint,bigint,bigint,boolean),
 public.form_order_input_internal(bigint,jsonb),public.form_order_quote_internal(bigint),public.preview_form_order_internal(bigint,jsonb),
 public.form_order_facts_internal(bigint),public.lock_form_order_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) TO authenticated;
