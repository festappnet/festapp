-- Draft overrides cannot target another hierarchy or arbitrary template codes.
CREATE OR REPLACE FUNCTION public.validate_setup_email_templates_internal(p_templates jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=coalesce(p_templates,'{}'); item record;
BEGIN
 IF jsonb_typeof(result)<>'object' OR octet_length(result::text)>196608 THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid draft email templates'; END IF;
 FOR item IN SELECT * FROM jsonb_each(result) LOOP
  IF item.key NOT IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE')
    OR jsonb_typeof(item.value)<>'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid draft email template'; END IF;
  IF jsonb_typeof(item.value->'subject') IS DISTINCT FROM 'string'
    OR jsonb_typeof(item.value->'html') IS DISTINCT FROM 'string'
    OR length(item.value->>'subject')>2000 OR octet_length(item.value->>'html')>65536
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(item.value) k WHERE k NOT IN ('subject','html')) THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid draft email template'; END IF;
  PERFORM public.validate_email_template_content_internal(item.key,item.value->>'html');
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.validate_setup_email_templates_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
