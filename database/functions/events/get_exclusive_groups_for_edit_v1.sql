CREATE OR REPLACE FUNCTION public.get_exclusive_groups_for_edit_v1(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_exclusive_group_command_data_v1(g.id)
    ORDER BY g.title,g.id),'[]'::jsonb) INTO v_result
  FROM public.exclusive_groups g WHERE g.occasion=p_occasion;
  RETURN v_result;
END; $function$
;
REVOKE ALL ON FUNCTION public.get_exclusive_groups_for_edit_v1(p_occasion bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_exclusive_groups_for_edit_v1(p_occasion bigint) TO authenticated;
