CREATE OR REPLACE FUNCTION public.complete_profile_inventory_membership_mutation_v1(p_command_id uuid, p_occasion bigint, p_source text, p_items jsonb, p_before_users uuid[], p_data jsonb, p_actor_kind text DEFAULT 'user'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_after_users uuid[]; v_removed uuid[];
  v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT ARRAY(SELECT id FROM unnest(COALESCE(p_before_users,'{}')) id
    WHERE NOT id=ANY(v_after_users)) INTO v_removed;
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=p_occasion
    AND s.user_id=ANY(v_removed);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed) id));
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_after_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component',component,
    'userId',id) ORDER BY id,component),'[]'::jsonb) INTO v_impacts
  FROM unnest(v_after_users) id CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component;
  IF cardinality(v_removed)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=p_occasion;
  END IF;
  IF v_actor IS NOT NULL AND v_actor=ANY(v_after_users) THEN
    v_replacements:=jsonb_build_array(
      jsonb_build_object('component','private_profile','userId',v_actor,
        'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)),
      jsonb_build_object('component','private_inventory','userId',v_actor,
        'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
  END IF;
  IF p_source='profile.tickets.import' AND cardinality(v_removed)>0 THEN
    v_impacts:=v_impacts||COALESCE((SELECT jsonb_agg(jsonb_build_object('component','private_activity','userId',id) ORDER BY id) FROM unnest(v_after_users) id),'[]'::jsonb);
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    p_source,'inventory',p_items,v_public,v_impacts,v_dirty,p_data,
    '{}','[]',p_actor_kind,NULL,v_replacements);
END; $function$

;
