-- Delegation adapter only: existing UI commands retain the single transaction,
-- receipt, validation, allocation, notification and sync ownership.
CREATE OR REPLACE FUNCTION public.manage_form(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; link text; form_id bigint; source_id bigint; allowed text[]; state jsonb;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('create','save','duplicate','delete','public_link') OR p_payload IS NULL
  OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form command'; END IF;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END);
 SELECT o.link INTO link FROM public.occasions o WHERE o.id=p_occasion;
 IF p_action IN ('save','delete','public_link') THEN
  form_id:=(p_payload->>'id')::bigint;
  IF form_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=p_occasion)
   AND NOT (p_action='delete' AND EXISTS(SELECT 1 FROM public.client_mutation_receipts
    WHERE command_id=p_command_id AND actor_id=auth.uid() AND occasion=p_occasion AND command_name='inventory.form.delete')) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  IF NOT p_payload ? 'expected_aggregate_version' OR jsonb_typeof(p_payload->'expected_aggregate_version')<>'number'
    OR (p_payload->>'expected_aggregate_version')::bigint<0 THEN
   RAISE invalid_parameter_value USING MESSAGE='original form version required'; END IF;
 END IF;
 allowed:=CASE p_action
  WHEN 'public_link' THEN ARRAY['id','expected_aggregate_version','link']
  WHEN 'create' THEN ARRAY['title']
  WHEN 'save' THEN ARRAY['id','expected_aggregate_version','expected_product_versions','expected_product_type_versions',
   'title','header','header_off','is_open','blueprint','bank_account','deadline_duration_seconds',
   'participant_capacity','waitlist_enabled','show_remaining_capacity','waitlist_offer_duration_seconds',
   'form_fields','deleted_field_ids','deleted_product_ids','settings']
  WHEN 'duplicate' THEN ARRAY['source_form_id','source_occasion_id','source_unit_id','locale']
  WHEN 'delete' THEN ARRAY['id','expected_aggregate_version']
 END;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE NOT k=ANY(allowed)) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported form fields'; END IF;
 CASE p_action
 WHEN 'public_link' THEN
  IF jsonb_typeof(p_payload->'link') IS DISTINCT FROM 'string' THEN RAISE invalid_parameter_value USING MESSAGE='public slug required'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion,'expected_product_versions','{}'::jsonb,'expected_product_type_versions','{}'::jsonb),p_command_id);
 WHEN 'create' THEN
  IF NOT p_payload ? 'title' OR jsonb_typeof(p_payload->'title')<>'string' OR length(p_payload->>'title')>500 THEN
   RAISE invalid_parameter_value USING MESSAGE='form title required'; END IF;
  result:=public.create_form_client_sync_v1(link,'',p_payload->>'title',p_command_id);
 WHEN 'save' THEN
  IF jsonb_typeof(p_payload->'expected_product_versions') IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_payload->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(coalesce(p_payload->'deleted_product_ids','[]')) id
    WHERE NOT (p_payload->'expected_product_versions') ? id) THEN
   RAISE invalid_parameter_value USING MESSAGE='deleted product baseline required'; END IF;
  -- The field transport can edit common definitions and reference a catalog
  -- type; inline product mutation remains in the existing aggregate UI owner.
  IF p_payload ? 'form_fields' AND (jsonb_typeof(p_payload->'form_fields')<>'array' OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'form_fields') f WHERE
      jsonb_typeof(f)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f) k WHERE k NOT IN
       ('id','title','description','type','is_required','is_hidden','is_ticket_field','order','data','product_type_id','product_type')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form fields'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'data' AND f->'data'<>'null'::jsonb AND
     (jsonb_typeof(f->'data')<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(f->'data') k
       WHERE k NOT IN ('options','max_tickets','selection_type','default_value','label','is_group_feature','min_year','max_year','is_hard','message','show_expiry_date','expiry_date_label','show_surcharge_description')))) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported field settings'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_payload->'form_fields','[]')) f
    WHERE f ? 'product_type' AND f ? 'product_type_id') THEN RAISE invalid_parameter_value USING MESSAGE='choose product reference or aggregate'; END IF;
  result:=public.update_form_client_sync_v1(p_payload||jsonb_build_object('occasion',p_occasion),p_command_id);
 WHEN 'duplicate' THEN
  source_id:=(p_payload->>'source_occasion_id')::bigint;
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source');
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=(p_payload->>'source_form_id')::bigint AND occasion=source_id) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign source form'; END IF;
  IF p_payload->>'locale' IS NULL OR p_payload->>'locale' NOT IN ('cs','en','sk','de','pl','uk') THEN
   RAISE invalid_parameter_value USING MESSAGE='copy locale required'; END IF;
  result:=public.duplicate_form_to_occasion_client_sync_v1((p_payload->>'source_form_id')::bigint,link,p_command_id,p_payload->>'locale');
  PERFORM public.check_form_authoring_scope_internal(source_id,p_organization,(p_payload->>'source_unit_id')::bigint,'source',true);
 WHEN 'delete' THEN
  result:=public.delete_form_client_sync_v1(form_id,p_command_id,(p_payload->>'expected_aggregate_version')::bigint);
 END CASE;
 PERFORM public.check_form_authoring_scope_internal(p_occasion,p_organization,p_unit,CASE WHEN p_action='public_link' THEN 'save' ELSE p_action END,true);
 IF (result->>'code')::int=200 THEN
  state:=result->'data'->'authoring';
  IF octet_length(state::text)>1048576 OR jsonb_array_length(state->'fields')>500 THEN
   RAISE program_limit_exceeded USING MESSAGE='form snapshot too large'; END IF;
  form_id:=coalesce((state->'form'->>'id')::bigint,form_id);
  RETURN result||jsonb_build_object('data',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'authoring',state),
   'sync',jsonb_build_object('replacements','[]'::jsonb))
   ||CASE WHEN p_action='public_link' THEN jsonb_build_object('publicLink',jsonb_build_object('occasionId',p_occasion,'formId',form_id,'slug',result#>>'{data,link}')) ELSE '{}'::jsonb END;
 END IF;
 RETURN result||jsonb_build_object('data',jsonb_build_object('reason','FORM_COMMAND_REJECTED'),
   'sync',jsonb_build_object('replacements','[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_form(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;
