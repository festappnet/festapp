CREATE OR REPLACE FUNCTION public.remove_image_records(p_links text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_row record; v_occasion bigint;
BEGIN
  IF COALESCE(array_length(p_links,1),0)=0 THEN RETURN; END IF;
  FOR v_row IN SELECT DISTINCT i.occasion,i.unit FROM public.images i
    WHERE i.link=ANY(p_links)
  LOOP
    IF v_row.occasion IS NOT NULL THEN
      IF NOT public.can_upload_occasion_media(v_row.occasion) THEN
        RAISE insufficient_privilege USING MESSAGE='occasion editor required';
      END IF;
    ELSIF v_row.unit IS NOT NULL AND NOT public.can_upload_unit_media(v_row.unit) THEN
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
END; $function$
;
REVOKE ALL ON FUNCTION public.remove_image_records(text[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.remove_image_records(text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.remove_image_records(text[]) TO authenticated;
