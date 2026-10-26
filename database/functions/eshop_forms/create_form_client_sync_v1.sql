CREATE OR REPLACE FUNCTION public.create_form_client_sync_v1(
  p_occasion_link text,p_link text,p_title text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_form jsonb;
BEGIN
  SELECT o.id,o.unit INTO v_occasion,v_unit FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_occasion_link);
  IF v_actor IS NULL OR v_occasion IS NULL
    OR length(p_link)>80 OR length(COALESCE(p_title,''))>500
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'link',p_link,'title',p_title)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.create',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.create_form_internal_v1(v_occasion,p_link,p_title);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.create',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form->>'id','operation','insert',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('form',v_form));
END; $$;
REVOKE ALL ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) TO authenticated;
