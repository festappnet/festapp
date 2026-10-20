-- Keep one canonical ordering for a combined news publication: the news enters
-- content_catalog first, then its push becomes visible to the existing
-- log_notifications delivery boundary. A failed publisher leaves the request
-- durably pending instead of sending a push whose destination is still stale.
CREATE TABLE public.news_notification_outbox (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  command_id uuid NOT NULL UNIQUE,
  occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  required_content_revision bigint NOT NULL CHECK (required_content_revision > 0),
  content text NOT NULL,
  heading text,
  "to" jsonb,
  data jsonb
);

CREATE INDEX news_notification_outbox_ready_idx
  ON public.news_notification_outbox(occasion,required_content_revision);

ALTER TABLE public.news_notification_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.news_notification_outbox FROM PUBLIC,anon,authenticated;

-- complete_client_sync_publication_classes_v1 is the sole publisher completion
-- contract. The superseded all-or-nothing completion has no repository caller.
DROP FUNCTION public.complete_client_sync_publication_v1(
  text,bigint,bigint,jsonb,text,text,bigint,jsonb,text,uuid[]);

CREATE OR REPLACE FUNCTION public.complete_client_sync_publication_classes_v1(
  p_scope_type text,p_scope_id bigint,p_release_revision bigint,p_manifest jsonb,
  p_manifest_url text,p_manifest_sha256 text,p_manifest_bytes bigint,p_live jsonb,
  p_head_json jsonb,p_head_etag text,p_catalog_claim_tokens uuid[],p_live_claim_tokens uuid[]
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE v_head public.client_sync_public_heads%ROWTYPE; v_component record;
  v_next_catalog bigint := (p_head_json#>>'{catalog,revision}')::bigint;
  v_next_live bigint := (p_head_json#>>'{live,revision}')::bigint;
  v_content_revision bigint;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT * INTO v_head FROM public.client_sync_public_heads
    WHERE scope_type=p_scope_type AND scope_id=p_scope_id FOR UPDATE;
  IF FOUND AND (v_next_catalog < COALESCE(v_head.release_revision,-1)
      OR COALESCE(v_next_live,-1) < COALESCE(v_head.live_revision,-1)
      OR (v_next_catalog = v_head.release_revision
          AND v_next_live IS NOT DISTINCT FROM v_head.live_revision
          AND v_head.head_json IS DISTINCT FROM p_head_json)) THEN
    RETURN false;
  END IF;
  IF p_release_revision IS NOT NULL THEN
    IF p_manifest IS NULL OR p_manifest_sha256 IS NULL
       OR p_release_revision <> v_next_catalog THEN RAISE EXCEPTION 'invalid catalog completion'; END IF;
    INSERT INTO public.client_sync_release_manifests
      (scope_type,scope_id,release_revision,manifest,artifact_url,sha256,byte_size)
    VALUES (p_scope_type,p_scope_id,p_release_revision,p_manifest,p_manifest_url,
      p_manifest_sha256,p_manifest_bytes) ON CONFLICT DO NOTHING;
    FOR v_component IN SELECT key,value FROM jsonb_each(p_manifest->'components') LOOP
      INSERT INTO public.client_sync_publications
        (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
      VALUES (v_component.key,p_scope_type,p_scope_id,
        (v_component.value->>'revision')::bigint,v_component.value->>'mediaType',
        v_component.value->>'url',v_component.value->>'sha256',(v_component.value->>'bytes')::bigint)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
  IF p_live IS NOT NULL THEN
    INSERT INTO public.client_sync_publications
      (component,scope_type,scope_id,published_revision,media_type,artifact_url,sha256,byte_size)
    VALUES ('live_public',p_scope_type,p_scope_id,(p_live->>'revision')::bigint,
      p_live->>'mediaType',p_live->>'url',p_live->>'sha256',(p_live->>'bytes')::bigint)
    ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.client_sync_public_heads
    (scope_type,scope_id,release_revision,manifest_sha256,live_revision,live_sha256,head_etag,head_json)
  VALUES (p_scope_type,p_scope_id,v_next_catalog,p_head_json#>>'{catalog,sha256}',
    v_next_live,p_head_json#>>'{live,sha256}',p_head_etag,p_head_json)
  ON CONFLICT (scope_type,scope_id) DO UPDATE SET
    release_revision=EXCLUDED.release_revision,manifest_sha256=EXCLUDED.manifest_sha256,
    live_revision=EXCLUDED.live_revision,live_sha256=EXCLUDED.live_sha256,
    head_etag=EXCLUDED.head_etag,head_json=EXCLUDED.head_json,updated_at=now();

  -- R2 artifacts and the accepted public head already exist at this point.
  -- Moving ready rows into log_notifications is atomic with recording that head;
  -- its existing AFTER INSERT hook therefore cannot outrun content_catalog.
  v_content_revision:=(p_manifest#>>'{components,content_catalog,revision}')::bigint;
  IF p_scope_type='occasion' AND v_content_revision IS NOT NULL THEN
    WITH ready AS (
      DELETE FROM public.news_notification_outbox q
      WHERE q.occasion=p_scope_id
        AND q.required_content_revision<=v_content_revision
      RETURNING q.*
    )
    INSERT INTO public.log_notifications
      (id,occasion,organization,user_id,"to",heading,content,data,created_at)
    SELECT r.id,r.occasion,r.organization,r.user_id,r."to",r.heading,r.content,
      r.data,r.created_at
    FROM ready r
    ON CONFLICT (id) DO NOTHING;
  END IF;

  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_catalog_claim_tokens,'{}')) AND component<>'live_public';
  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_live_claim_tokens,'{}')) AND component='live_public';
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) TO service_role;

CREATE OR REPLACE FUNCTION public.publish_news_client_sync_v1(
  p_occasion bigint,p_add_to_news boolean,p_news_message text,
  p_send_notification boolean,p_notification_heading text,
  p_notification_content text,p_recipients jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_organization bigint; v_begin jsonb; v_hash text;
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
      (occasion,organization,user_id,"to",heading,content,data)
    VALUES (p_occasion,v_organization,v_actor,p_recipients,
      p_notification_heading,p_notification_content,jsonb_build_object('path','news'));
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
       "to",heading,content,data)
    VALUES (p_command_id,p_occasion,v_organization,v_actor,v_required_revision,
      p_recipients,p_notification_heading,p_notification_content,
      jsonb_build_object('path','news'));
  END IF;
  RETURN v_response;
END; $$;
REVOKE ALL ON FUNCTION public.publish_news_client_sync_v1(bigint,boolean,text,boolean,text,text,jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.publish_news_client_sync_v1(bigint,boolean,text,boolean,text,text,jsonb,uuid)
  TO authenticated;
