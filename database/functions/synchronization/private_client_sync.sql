-- Canonical owner recovered from the recorded effective main schema.
-- Public signatures, response envelopes and existing execution roles are preserved.

CREATE OR REPLACE FUNCTION public.get_private_client_sync_v1(p_context jsonb, p_known_private_vector jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_occasion bigint := (p_context->>'occasionId')::bigint;
  v_user uuid := auth.uid();
  v_components jsonb;
  v_vector jsonb;
BEGIN
  IF p_context IS NULL OR jsonb_typeof(p_context) <> 'object'
     OR octet_length(p_context::text) > 4096
     OR EXISTS (
       SELECT 1 FROM jsonb_object_keys(p_context) key
       WHERE key NOT IN ('organizationId','occasionId'))
     OR p_known_private_vector IS NULL
     OR jsonb_typeof(p_known_private_vector) <> 'object'
     OR octet_length(p_known_private_vector::text) > 4096
     OR EXISTS (
       SELECT 1 FROM jsonb_each_text(p_known_private_vector) entry
       WHERE entry.key NOT IN ('private_program','private_profile',
         'private_inventory','private_activity','private_news','private_feedback')
         OR entry.value !~ '^[0-9]{1,19}$') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid private sync request';
  END IF;
  IF NOT public.can_read_private_client_sync((p_context->>'organizationId')::bigint,v_occasion) THEN RETURN jsonb_build_object('code', 403); END IF;

  WITH names(component) AS (VALUES
    ('private_program'),('private_profile'),('private_inventory'),
    ('private_activity'),('private_news'),('private_feedback')
  ), heads AS (
    SELECT n.component, COALESCE(s.source_revision, 0) revision
    FROM names n LEFT JOIN public.client_sync_private_scopes s
      ON s.component=n.component AND s.occasion=v_occasion AND s.user_id=v_user
  ) SELECT jsonb_object_agg(component, revision) INTO v_vector FROM heads;

  WITH changed AS (
    SELECT key component, value::text::bigint revision FROM jsonb_each(v_vector)
    WHERE value::text::bigint > COALESCE((p_known_private_vector->>key)::bigint, -1)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'component', c.component, 'revision', c.revision, 'payload',
    CASE c.component
      WHEN 'private_program' THEN jsonb_build_object(
        'signedIn', (SELECT COALESCE(jsonb_agg(eu.event ORDER BY eu.event),'[]') FROM public.event_users eu JOIN public.events e ON e.id=eu.event WHERE eu."user"=v_user AND e.occasion=v_occasion),
        'saved', (SELECT COALESCE(jsonb_agg(es.event ORDER BY es.event),'[]') FROM public.event_users_saved es JOIN public.events e ON e.id=es.event WHERE es."user"=v_user AND e.occasion=v_occasion))
      WHEN 'private_profile' THEN public.get_private_profile_payload_v1(
        v_occasion,v_user)
      WHEN 'private_inventory' THEN public.get_user_inventory_for_occasion_v1(v_occasion)
      WHEN 'private_activity' THEN public.get_my_events_and_activities(v_occasion,true)->'data'
      WHEN 'private_news' THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('newsId',un.news_id,'readAt',un.created_at) ORDER BY un.news_id),'[]') FROM public.user_news un WHERE un.occasion=v_occasion AND un."user"=v_user)
      WHEN 'private_feedback' THEN public.get_private_feedback_payload_v1(
        v_occasion,v_user)
    END)),'[]') INTO v_components FROM changed c;

  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'serverTime',clock_timestamp(),'vector',v_vector,'components',v_components));
END;
$function$
;
REVOKE ALL ON FUNCTION public.get_private_client_sync_v1(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_private_client_sync_v1(jsonb,jsonb) TO postgres,authenticated,service_role;
