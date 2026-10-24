CREATE OR REPLACE FUNCTION public.mark_news_read_client_sync_v1(p_occasion bigint, p_news_id bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_revision bigint;
  v_begin jsonb;
  v_commit jsonb;
  v_read_at timestamptz;
  v_data jsonb;
  v_response jsonb;
  v_request_sha256 text;
  v_is_member boolean;
BEGIN
  IF v_user IS NULL
     OR NOT public.can_read_news_data_security_v1(p_occasion)
     OR NOT EXISTS (SELECT 1 FROM public.user_info ui JOIN public.occasions o
       ON o.organization=ui.organization WHERE ui.id=v_user AND o.id=p_occasion)
     OR NOT EXISTS (SELECT 1 FROM public.news n
       WHERE n.id=p_news_id AND n.occasion=p_occasion)
  THEN RETURN jsonb_build_object('code',403); END IF;

  v_request_sha256:=encode(extensions.digest(convert_to(
    jsonb_build_object('occasion',p_occasion,'newsId',p_news_id)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'news.mark_read',
    p_occasion,v_user,v_request_sha256);
  IF v_begin->>'disposition'='replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_occasion::text,0));

  SELECT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=v_user) INTO v_is_member;
  SELECT COALESCE(source_revision,0) INTO v_revision
  FROM (SELECT 1) seed LEFT JOIN public.client_sync_private_scopes s
    ON s.component='private_news' AND s.occasion=p_occasion AND s.user_id=v_user;
  -- A delayed command never moves the high-water mark backwards.
  SELECT greatest(p_news_id,coalesce(max(news_id),0)) INTO p_news_id
    FROM public.user_news WHERE "user"=v_user AND occasion=p_occasion;
  IF (SELECT count(*)=1 AND max(news_id)=p_news_id
      FROM public.user_news
      WHERE "user"=v_user AND occasion=p_occasion) THEN
    v_data:=jsonb_build_object('revision',v_revision,'payload',jsonb_build_array(
      jsonb_build_object('newsId',p_news_id)));
    v_response:=jsonb_build_object('status','unchanged','code',200,'data',v_data,
      'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
        'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
      'sync',jsonb_build_object('replacements','[]'::jsonb));
    RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
  END IF;

  v_read_at:=clock_timestamp();
  v_data:=jsonb_build_object('revision',v_revision+1,'payload',jsonb_build_array(
    jsonb_build_object('newsId',p_news_id,'readAt',v_read_at)));
  DELETE FROM public.user_news WHERE "user"=v_user AND occasion=p_occasion;
  INSERT INTO public.user_news(news_id,"user",occasion) VALUES(p_news_id,v_user,p_occasion);
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'mark_news_read','private',
    jsonb_build_array(jsonb_build_object('entityType','news_marker',
      'entityId',p_news_id,'operation','update','safeLabel','News read marker',
    'changedFields',jsonb_build_array('news_id'))),ARRAY['live_public'],CASE WHEN v_is_member THEN jsonb_build_array(
      jsonb_build_object('component','private_news','userId',v_user)) ELSE '[]'::jsonb END,jsonb_build_array(
      jsonb_build_object('component','live_public','entityId',p_news_id)),
    'user',NULL);
  SELECT source_revision INTO v_revision FROM public.client_sync_private_scopes
    WHERE component='private_news' AND occasion=p_occasion AND user_id=v_user;
  v_data:=v_data||jsonb_build_object('revision',coalesce(v_revision,0));
  v_response:=jsonb_build_object('status','applied','code',200,'data',v_data,
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit->>'commitId','replayed',false,
      'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',CASE WHEN v_is_member THEN jsonb_build_array(jsonb_build_object(
      'component','private_news','revision',v_revision,'payload',v_data->'payload')) ELSE '[]'::jsonb END));
  RETURN public.finish_client_mutation_v1(
    p_command_id,v_response,(v_commit->>'commitId')::uuid);
END; $function$;


REVOKE ALL ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid) TO authenticated,service_role;
