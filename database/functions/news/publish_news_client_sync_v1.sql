CREATE OR REPLACE FUNCTION public.publish_news_client_sync_v1(p_occasion bigint, p_add_to_news boolean, p_news_message text, p_send_notification boolean, p_notification_heading text, p_notification_content text, p_recipients jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_notification uuid; v_actor uuid:=auth.uid(); v_organization bigint; v_begin jsonb; v_hash text;
  v_id bigint; v_version bigint:=0; v_entity jsonb; v_items jsonb:='[]'::jsonb;
  v_is_publishable boolean; v_response jsonb; v_required_revision bigint;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  SELECT o.organization,NOT o.is_hidden INTO v_organization,v_is_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_organization IS NULL OR NOT COALESCE(p_add_to_news,false)
      AND NOT COALESCE(p_send_notification,false)
    OR p_add_to_news AND (p_news_message IS NULL
      OR octet_length(p_news_message) NOT BETWEEN 1 AND 524288)
    OR p_send_notification AND (p_notification_content IS NULL
      OR octet_length(p_notification_content)>65536
      OR octet_length(COALESCE(p_notification_heading,''))>2048
      OR p_recipients IS NOT NULL AND (jsonb_typeof(p_recipients)<>'array'
        OR jsonb_array_length(p_recipients)>5000
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_recipients) value
          WHERE jsonb_typeof(value)<>'string'
            OR octet_length(value#>>'{}')>512))) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid news publication'; END IF;
  IF COALESCE(p_add_to_news,false) AND COALESCE(p_send_notification,false)
      AND NOT v_is_publishable THEN
    RAISE invalid_parameter_value
      USING MESSAGE='news push requires a publicly publishable occasion';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'addToNews',p_add_to_news,'newsMessage',p_news_message,
    'sendNotification',p_send_notification,'notificationHeading',p_notification_heading,
    'notificationContent',p_notification_content,'recipients',p_recipients)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'content.news.publish',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF coalesce(p_send_notification,false) THEN PERFORM public.charge_notification_intent_v1(p_occasion,v_actor,p_recipients,p_notification_heading,p_notification_content); END IF;
  IF COALESCE(p_add_to_news,false) THEN
    INSERT INTO public.news(message,created_by,occasion)
      VALUES (p_news_message,v_actor,p_occasion) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('news','occasion',p_occasion,v_id::text,v_version);
    SELECT to_jsonb(n)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.news n WHERE n.id=v_id;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','news','entityId',v_id,'operation','insert','safeLabel','News',
      'changedFields',jsonb_build_array('message')));
  END IF;
  IF COALESCE(p_send_notification,false) THEN
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'entityType','notification','entityId',NULL,'operation','publish',
      'safeLabel','Notification','changedFields',jsonb_build_array('delivery_request')));
  END IF;

  -- A notification-only test has no news publication to wait for.
  IF COALESCE(p_send_notification,false) AND NOT COALESCE(p_add_to_news,false) THEN
    INSERT INTO public.log_notifications
      (occasion,organization,user_id,"to",heading,content,data,abuse_admitted_at)
    VALUES (p_occasion,v_organization,v_actor,p_recipients,
      p_notification_heading,p_notification_content,jsonb_build_object('path','news'),statement_timestamp()) RETURNING id INTO v_notification;
    PERFORM public.dispatch_log_notification_v1(v_notification);
  END IF;

  v_response:=public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'content.news.publish','content',v_items,
    CASE WHEN COALESCE(p_add_to_news,false) AND v_is_publishable
      THEN ARRAY['content_catalog'] ELSE '{}'::text[] END,'[]','[]',
    jsonb_build_object('version',v_version,'news',v_entity,
      'notificationQueued',COALESCE(p_send_notification,false)));

  IF COALESCE(p_add_to_news,false) AND COALESCE(p_send_notification,false) THEN
    SELECT c.resulting_revision INTO v_required_revision
    FROM public.client_commit_components c
    WHERE c.commit_id=(v_response#>>'{mutation,commitId}')::uuid
      AND c.component='content_catalog' AND c.scope_type='occasion'
      AND c.scope_id=p_occasion AND c.user_id IS NULL;
    IF v_required_revision IS NULL THEN
      RAISE EXCEPTION 'news publication did not produce a content revision';
    END IF;
    INSERT INTO public.news_notification_outbox
      (command_id,occasion,organization,user_id,required_content_revision,
       "to",heading,content,data,abuse_admitted_at)
    VALUES (p_command_id,p_occasion,v_organization,v_actor,v_required_revision,
      p_recipients,p_notification_heading,p_notification_content,
      jsonb_build_object('path','news'),statement_timestamp());
  END IF;
  RETURN v_response;
END; $function$
;
REVOKE ALL ON FUNCTION public.publish_news_client_sync_v1(p_occasion bigint, p_add_to_news boolean, p_news_message text, p_send_notification boolean, p_notification_heading text, p_notification_content text, p_recipients jsonb, p_command_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_news_client_sync_v1(p_occasion bigint, p_add_to_news boolean, p_news_message text, p_send_notification boolean, p_notification_heading text, p_notification_content text, p_recipients jsonb, p_command_id uuid) TO authenticated;
