-- Canonical publication ordering retained; admission precedes both existing push paths.

CREATE OR REPLACE FUNCTION public.complete_client_sync_publication_classes_v1(p_scope_type text, p_scope_id bigint, p_release_revision bigint, p_manifest jsonb, p_manifest_url text, p_manifest_sha256 text, p_manifest_bytes bigint, p_live jsonb, p_head_json jsonb, p_head_etag text, p_catalog_claim_tokens uuid[], p_live_claim_tokens uuid[])
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_head public.client_sync_public_heads%ROWTYPE; v_component record;
  v_next_catalog bigint := (p_head_json#>>'{catalog,revision}')::bigint;
  v_next_live bigint := (p_head_json#>>'{live,revision}')::bigint;
  v_content_revision bigint; v_notification uuid;
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
  -- explicit dispatch therefore cannot outrun content_catalog.
  v_content_revision:=(p_manifest#>>'{components,content_catalog,revision}')::bigint;
  IF p_scope_type='occasion' AND v_content_revision IS NOT NULL THEN
    FOR v_notification IN WITH ready AS (
      DELETE FROM public.news_notification_outbox q
      WHERE q.occasion=p_scope_id
        AND q.required_content_revision<=v_content_revision
      RETURNING q.*
    )
    INSERT INTO public.log_notifications
      (id,occasion,organization,user_id,"to",heading,content,data,created_at,abuse_admitted_at)
    SELECT r.id,r.occasion,r.organization,r.user_id,r."to",r.heading,r.content,
      r.data,r.created_at,r.abuse_admitted_at
    FROM ready r
    ON CONFLICT (id) DO NOTHING RETURNING id LOOP
      PERFORM public.dispatch_log_notification_v1(v_notification);
    END LOOP;
  END IF;

  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_catalog_claim_tokens,'{}')) AND component<>'live_public';
  DELETE FROM public.client_projection_dirty_keys
    WHERE claim_token=ANY(COALESCE(p_live_claim_tokens,'{}')) AND component='live_public';
  RETURN true;
END; $function$;







REVOKE ALL ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_client_sync_publication_classes_v1(text,bigint,bigint,jsonb,text,text,bigint,jsonb,jsonb,text,uuid[],uuid[]) TO service_role;
