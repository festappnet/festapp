CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_client_sync_v1(
  p_source_form_id bigint,p_target_occasion_link text,p_command_id uuid,
  p_locale text DEFAULT 'en'
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_source_occasion bigint; v_source_unit bigint;
  v_target bigint; v_begin jsonb; v_hash text; v_form bigint;
BEGIN
  SELECT f.occasion,o.unit INTO v_source_occasion,v_source_unit
    FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
    WHERE f.id=p_source_form_id;
  SELECT o.id INTO v_target FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_target_occasion_link);
  IF v_actor IS NULL OR v_target IS NULL
    OR NOT public.can_copy_form_target(v_target) THEN
    RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  IF v_source_occasion IS NULL OR NOT public.can_copy_form_source(v_source_occasion) THEN RAISE insufficient_privilege USING MESSAGE='form copy permission required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'sourceFormId',p_source_form_id,'targetOccasion',v_target,'locale',p_locale)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.duplicate',v_target,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.duplicate_form_to_occasion_internal_v1(
    p_source_form_id,p_target_occasion_link,p_locale);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_target,
    'inventory.form.duplicate',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','insert',
      'safeLabel','Duplicated form','changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('formId',v_form,'authoring',public.get_form_authoring_snapshot_internal(v_form)));
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion_client_sync_v1(bigint,text,uuid,text) TO authenticated;
