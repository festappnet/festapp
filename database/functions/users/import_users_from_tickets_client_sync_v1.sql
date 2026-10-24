CREATE OR REPLACE FUNCTION public.import_users_from_tickets_client_sync_v1(p_occasion bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before_users uuid[];
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'profile.tickets.import',p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT id FROM eshop.orders WHERE occasion=p_occasion));
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.user_info ui WHERE ui.id IN(SELECT "user" FROM public.occasion_users WHERE occasion=p_occasion)
   OR (ui.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) AND ui.email_readonly IN(
    SELECT lower(btrim(o.data->>'email')) FROM eshop.orders o WHERE o.occasion=p_occasion)) ORDER BY ui.id FOR UPDATE;
  PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion ORDER BY "user" FOR UPDATE;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  v_result:=public.import_users_from_tickets_ws_internal_v1(p_occasion);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,p_occasion,'profile.tickets.import',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Ticket profile import','changedFields',jsonb_build_array(
        'profile','ticket','membership'))),v_before_users,v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.import_users_from_tickets_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_users_from_tickets_client_sync_v1(bigint,uuid) TO authenticated;
