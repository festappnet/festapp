-- Occasion image rows are the authoritative media manifest for offline-first
-- clients. Keep the existing projection builder as a private implementation
-- detail and enrich its occasion_config envelope at the canonical boundary.
ALTER FUNCTION public.get_public_client_sync_component_v1(text,text,bigint)
  RENAME TO get_public_client_sync_component_core_v1;
REVOKE ALL ON FUNCTION public.get_public_client_sync_component_core_v1(text,text,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_client_sync_component_core_v1(text,text,bigint)
  TO service_role;

CREATE FUNCTION public.get_public_client_sync_component_v1(
  p_component text,p_scope_type text,p_scope_id bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_media jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  v_result:=public.get_public_client_sync_component_core_v1(
    p_component,p_scope_type,p_scope_id);
  IF p_component='occasion_config' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id',i.id,'url',i.link)
      ORDER BY i.id),'[]'::jsonb) INTO v_media
    FROM public.images i WHERE i.occasion=p_scope_id;
    v_result:=jsonb_set(v_result,'{payload,media}',v_media,true);
  END IF;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint)
  TO service_role;

INSERT INTO public.client_sync_component_sources(
  registry_version,component,source_relation,scope_resolver,tracked_columns,
  canonical_writers,legacy_writers,disposition,test_factory,cutover_ready
)
SELECT COALESCE(max(registry_version),1),'occasion_config','public.images'::regclass,
  'images.occasion',ARRAY['id','link','occasion'],
  ARRAY['add_image_record','remove_image_records'],'{}'::text[],'migrate',
  'occasion_image_factory',false
FROM public.client_sync_component_sources
ON CONFLICT (registry_version,component,source_relation) DO UPDATE SET
  scope_resolver=EXCLUDED.scope_resolver,
  tracked_columns=EXCLUDED.tracked_columns,
  canonical_writers=EXCLUDED.canonical_writers,
  legacy_writers=EXCLUDED.legacy_writers,
  disposition=EXCLUDED.disposition,
  test_factory=EXCLUDED.test_factory,
  cutover_ready=EXCLUDED.cutover_ready;

CREATE OR REPLACE FUNCTION public.add_image_record(
  p_link text,p_occasion_id bigint,p_unit_id bigint
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_image_id bigint;
BEGIN
  IF p_unit_id IS NOT NULL THEN
    IF NOT public.get_is_editor_on_unit(p_unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE='unit editor required';
    END IF;
  ELSIF p_occasion_id IS NOT NULL THEN
    IF NOT public.get_is_editor_on_occasion(p_occasion_id)
       AND NOT public.get_is_editor_order_on_occasion(p_occasion_id) THEN
      RAISE insufficient_privilege USING MESSAGE='occasion editor required';
    END IF;
  ELSE
    RAISE invalid_parameter_value USING MESSAGE='occasion or unit is required';
  END IF;

  INSERT INTO public.images(link,occasion,unit)
  VALUES (p_link,p_occasion_id,p_unit_id) RETURNING id INTO v_image_id;

  IF p_occasion_id IS NOT NULL THEN
    PERFORM public.record_client_sync_commit_v1(
      p_occasion_id,'image.add','content',jsonb_build_array(jsonb_build_object(
        'entityType','occasion_image','entityId',v_image_id::text,
        'operation','insert','safeLabel',left(p_link,240),
        'changedFields',jsonb_build_array('link'))),
      ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'user',NULL);
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.add_image_record(text,bigint,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_image_record(text,bigint,bigint)
  TO authenticated;

CREATE FUNCTION public.remove_image_records(p_links text[])
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_row record; v_occasion bigint;
BEGIN
  IF COALESCE(array_length(p_links,1),0)=0 THEN RETURN; END IF;
  FOR v_row IN SELECT DISTINCT i.occasion,i.unit FROM public.images i
    WHERE i.link=ANY(p_links)
  LOOP
    IF v_row.occasion IS NOT NULL THEN
      IF NOT public.get_is_editor_on_occasion(v_row.occasion)
         AND NOT public.get_is_editor_order_on_occasion(v_row.occasion) THEN
        RAISE insufficient_privilege USING MESSAGE='occasion editor required';
      END IF;
    ELSIF v_row.unit IS NOT NULL AND NOT public.get_is_editor_on_unit(v_row.unit) THEN
      RAISE insufficient_privilege USING MESSAGE='unit editor required';
    END IF;
  END LOOP;

  FOR v_occasion IN SELECT DISTINCT i.occasion FROM public.images i
    WHERE i.link=ANY(p_links) AND i.occasion IS NOT NULL
  LOOP
    DELETE FROM public.images i
      WHERE i.link=ANY(p_links) AND i.occasion=v_occasion;
    PERFORM public.record_client_sync_commit_v1(
      v_occasion,'image.remove','content',jsonb_build_array(jsonb_build_object(
        'entityType','occasion_image','entityId','batch','operation','delete',
        'safeLabel','occasion media','changedFields',jsonb_build_array('link'))),
      ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'user',NULL);
  END LOOP;

  DELETE FROM public.images i WHERE i.link=ANY(p_links);
END; $$;
REVOKE ALL ON FUNCTION public.remove_image_records(text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.remove_image_records(text[]) TO authenticated;
