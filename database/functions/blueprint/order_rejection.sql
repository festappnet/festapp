-- Only structured domain errors cross the new preview/command boundary.
CREATE OR REPLACE FUNCTION public.blueprint_order_rejection_internal(p_message text,p_detail text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE failure jsonb:='{}';reason text;result jsonb;
BEGIN
 BEGIN
  IF left(p_detail,1)='{' THEN failure:=p_detail::jsonb;
  ELSIF left(p_message,1)='{' THEN failure:=p_message::jsonb; END IF;
 EXCEPTION WHEN invalid_text_representation THEN failure:='{}';
 END;
 reason:=coalesce(failure->>'errorCode',failure->>'message',p_message);
 IF reason IS NULL OR NOT reason=ANY(ARRAY['REQUIRED_FIELD_MISSING','PRODUCT_CAPACITY_EXCEEDED','FORM_CAPACITY_EXCEEDED',
  'PRODUCT_SCOPE_MISMATCH','FORM_FIELD_SCOPE_MISMATCH','FORM_FIELD_TYPE_MISMATCH','FORM_FIELD_AMBIGUOUS','FORM_FIELD_VALUE_CONFLICT',
  'BATCH_TICKET_PRINT_IMMUTABLE','BLUEPRINT_ORDER_MONEY_UNAVAILABLE','BLUEPRINT_SEAT_PROTECTED','BLUEPRINT_SELECTION_UNIT_USED',
  'BLUEPRINT_INCOMPLETE_SELECTION_UNIT','STRIPE_REPLACEMENT_UNSUPPORTED','BLUEPRINT_CURRENCY_MISMATCH']) THEN
  reason:='BLUEPRINT_ORDER_INPUT_OR_STATE_REJECTED'; END IF;
 result:=jsonb_build_object('code',409,'reason',reason);
 IF reason='REQUIRED_FIELD_MISSING' AND coalesce(failure->>'fieldId','')~'^[1-9][0-9]{0,14}$' THEN
  result:=result||jsonb_build_object('fieldId',(failure->>'fieldId')::bigint); END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_order_rejection_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;
