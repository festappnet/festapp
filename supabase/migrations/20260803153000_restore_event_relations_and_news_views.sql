-- Event commands own the child's parent links, while editor reads also need
-- the inverse child links to render a complete aggregate. Keep that inverse
-- relation read-only so saving a parent never rewrites child aggregates.
CREATE OR REPLACE FUNCTION public.get_event_editor_v1(
  p_occasion bigint,p_event bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_event jsonb; v_version bigint;
BEGIN
  IF NOT public.get_is_editor_view_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT public.get_event_command_data_v1(e.id)||jsonb_build_object(
      'childEventIds',COALESCE((SELECT jsonb_agg(g.event_child ORDER BY g.event_child)
        FROM public.event_groups g WHERE g.event_parent=e.id),'[]'::jsonb)
    ),COALESCE(v.version,0)
    INTO v_event,v_version FROM public.events e
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event'
      AND v.scope_type='occasion' AND v.scope_id=p_occasion
      AND v.aggregate_id=e.id::text
    WHERE e.id=p_event AND e.occasion=p_occasion;
  IF v_event IS NULL THEN RETURN jsonb_build_object('code',404,'data',NULL); END IF;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'version',v_version,'event',v_event));
END; $$;
REVOKE ALL ON FUNCTION public.get_event_editor_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_event_editor_v1(bigint,bigint) TO authenticated;

-- Preserve the legacy get_news_with_views semantics: user_news stores one
-- last-read marker per user, and a news item is viewed when the marker is on
-- that item or any newer item (the former client accumulated exact counts in
-- descending news-id order).
CREATE OR REPLACE FUNCTION public.get_news_view_counts_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'newsId',n.id,
    'views',(SELECT count(*) FROM public.user_news un
      WHERE un.occasion=p_occasion AND un.news_id>=n.id)
  ) ORDER BY n.id),'[]'::jsonb)
  FROM public.news n
  WHERE n.occasion=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.get_news_view_counts_v1(bigint)
  FROM PUBLIC,anon,authenticated;

-- The same canonical intent owns the private marker and its anonymous public
-- aggregate. Record both projections in the source registry.
INSERT INTO public.client_sync_component_sources(
  registry_version,component,source_relation,scope_resolver,tracked_columns,
  canonical_writers,legacy_writers,disposition,test_factory,cutover_ready
)
SELECT max(registry_version),'live_public','public.user_news'::regclass,
  'user_news.occasion',ARRAY['news_id','user','occasion'],
  ARRAY['mark_news_read_client_sync_v1'],'{}'::text[],'migrate',
  'user_news_factory',true
FROM public.client_sync_component_sources
ON CONFLICT (registry_version,component,source_relation) DO UPDATE SET
  scope_resolver=EXCLUDED.scope_resolver,
  tracked_columns=EXCLUDED.tracked_columns,
  canonical_writers=EXCLUDED.canonical_writers,
  legacy_writers=EXCLUDED.legacy_writers,
  disposition=EXCLUDED.disposition,
  test_factory=EXCLUDED.test_factory,
  cutover_ready=EXCLUDED.cutover_ready;

-- Public component payloads remain one canonical function. News content is
-- immutable content_catalog data; its volatile aggregate belongs to
-- live_public alongside participant and cleaning counts.
CREATE OR REPLACE FUNCTION public.get_public_client_sync_component_v1(
  p_component text, p_scope_type text, p_scope_id bigint
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_revision bigint; v_payload jsonb; v_organization bigint; v_generated_at timestamptz;
BEGIN
  IF NOT public.is_service_role()
     AND NOT public.get_is_editor_on_occasion(p_scope_id) THEN
    RAISE insufficient_privilege USING MESSAGE='publisher or occasion editor required';
  END IF;
  IF p_scope_type <> 'occasion' OR NOT EXISTS (
    SELECT 1 FROM public.occasions WHERE id=p_scope_id AND NOT is_hidden
  ) THEN RAISE EXCEPTION 'scope is not publicly publishable'; END IF;
  SELECT source_revision,updated_at INTO v_revision,v_generated_at FROM public.client_sync_scopes
    WHERE component=p_component AND scope_type=p_scope_type AND scope_id=p_scope_id;
  v_revision := COALESCE(v_revision,0);

  CASE p_component
    WHEN 'occasion_config' THEN
      SELECT jsonb_build_object('id',o.id,'title',o.title,'startTime',o.start_time,
        'endTime',o.end_time,'isOpen',o.is_open,'features',o.features,'data',o.data,
        'services',o.services,'unitId',o.unit) INTO v_payload
      FROM public.occasions o WHERE o.id=p_scope_id AND NOT o.is_hidden;
    WHEN 'program_catalog' THEN
      SELECT jsonb_build_object(
        'events',COALESCE(jsonb_agg(DISTINCT jsonb_build_object('id',e.id,'title',e.title,
          'startTime',e.start_time,'endTime',e.end_time,'maxParticipants',e.max_participants,
          'description',e.description,'placeId',e.place,'type',e.type,'data',e.data,
          'order',e."order",'isGroupEvent',e.is_group_event,'splitForMenWomen',e.split_for_men_women)) FILTER (WHERE e.id IS NOT NULL),'[]'),
        'eventGroups',(SELECT COALESCE(jsonb_agg(jsonb_build_object('parentId',eg.event_parent,'childId',eg.event_child) ORDER BY eg.event_parent,eg.event_child),'[]') FROM public.event_groups eg JOIN public.events ep ON ep.id=eg.event_parent JOIN public.events ec ON ec.id=eg.event_child WHERE ep.occasion=p_scope_id AND ec.occasion=p_scope_id AND NOT ep.is_hidden AND NOT ec.is_hidden),
        'eventRoles',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',er.event,'roleId',er.role) ORDER BY er.event,er.role),'[]') FROM public.event_roles er JOIN public.events e2 ON e2.id=er.event WHERE e2.occasion=p_scope_id AND NOT e2.is_hidden),
        'eventSpeakers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',es.event,'speakerId',es.speaker) ORDER BY es.event,es.speaker),'[]') FROM public.event_speakers es JOIN public.events e3 ON e3.id=es.event JOIN public.speakers sp ON sp.id=es.speaker WHERE e3.occasion=p_scope_id AND NOT e3.is_hidden AND NOT sp.is_hidden)
      ) INTO v_payload FROM public.events e WHERE e.occasion=p_scope_id AND NOT e.is_hidden;
    WHEN 'map_catalog' THEN
      SELECT o.organization INTO v_organization FROM public.occasions o WHERE o.id=p_scope_id;
      WITH visible_places AS (
        SELECT p.*,COALESCE(v.version,0) aggregate_version FROM public.places p
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=p.id::text
        WHERE p.occasion=p_scope_id AND NOT p.is_hidden
      ), visible_types AS (
        SELECT pt.*,COALESCE(v.version,0) aggregate_version FROM public.place_types pt
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place_type'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=pt.id::text
        WHERE pt.occasion=p_scope_id AND NOT pt.is_hidden
      ), visible_paths AS (
        SELECT pg.*,COALESCE(v.version,0) aggregate_version FROM public.path_groups pg
        LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='path'
          AND v.scope_type='occasion' AND v.scope_id=p_scope_id
          AND v.aggregate_id=pg.id::text
        WHERE pg.occasion=p_scope_id AND NOT pg.is_hidden
      ), icon_ids AS (
        SELECT icon FROM visible_places WHERE icon IS NOT NULL UNION
        SELECT icon FROM visible_types WHERE icon IS NOT NULL UNION
        SELECT icon FROM visible_paths WHERE icon IS NOT NULL
      ), missing AS (
        SELECT i.icon FROM icon_ids i LEFT JOIN public.icons x ON x.id=i.icon AND x.organization=v_organization
        WHERE x.id IS NULL
      )
      SELECT CASE WHEN EXISTS(SELECT 1 FROM missing) THEN NULL ELSE jsonb_build_object(
        'places',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'description',p.description,'type',p.type,'coordinates',p.coordinates,'order',p."order",'icon',p.icon,'aggregateVersion',p.aggregate_version) ORDER BY p."order",p.id),'[]') FROM visible_places p),
        'placeTypes',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pt.id,'code',pt.code,'title',pt.title,'icon',pt.icon,'order',pt."order",'isDefault',pt.is_default,'aggregateVersion',pt.aggregate_version) ORDER BY pt."order",pt.id),'[]') FROM visible_types pt),
        'paths',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pg.id,'title',pg.title,'pathData',pg.path_data,'data',pg.data,'icon',pg.icon,'order',pg."order",'aggregateVersion',pg.aggregate_version) ORDER BY pg."order",pg.id),'[]') FROM visible_paths pg),
        'icons',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',i.id,'link',i.link,'svg',i.data) ORDER BY i.id),'[]') FROM public.icons i JOIN icon_ids refs ON refs.icon=i.id)
      ) END INTO v_payload;
      IF v_payload IS NULL THEN RAISE EXCEPTION 'map_catalog has a dangling or foreign icon reference'; END IF;
    WHEN 'content_catalog' THEN
      SELECT jsonb_build_object(
        'information',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',i.id,'title',i.title,'description',i.description,'order',i."order",'type',i.type,'data',i.data,'aggregateVersion',COALESCE(v.version,0)) ORDER BY i."order",i.id),'[]') FROM public.information i LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='information' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=i.id::text WHERE i.occasion=p_scope_id AND NOT i.is_hidden),
        'news',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',n.id,'message',n.message,'createdAt',n.created_at,'updatedAt',n.updated_at,'aggregateVersion',COALESCE(v.version,0)) ORDER BY n.created_at,n.id),'[]') FROM public.news n LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='news' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=n.id::text WHERE n.occasion=p_scope_id),
        'speakers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'subtitle',s.subtitle,'description',s.description,'image',s.image,'order',s."order",'data',s.data,'aggregateVersion',COALESCE(v.version,0)) ORDER BY s."order",s.id),'[]') FROM public.speakers s LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=s.id::text WHERE s.occasion=p_scope_id AND NOT s.is_hidden),
        'topics',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'order',t."order",'aggregateVersion',COALESCE(v.version,0)) ORDER BY t."order",t.id),'[]') FROM public.speaker_topics t LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker_topic' AND v.scope_type='occasion' AND v.scope_id=p_scope_id AND v.aggregate_id=t.id::text WHERE t.occasion=p_scope_id AND NOT t.is_hidden),
        'topicLinks',(SELECT COALESCE(jsonb_agg(jsonb_build_object('speakerId',l.speaker,'topicId',l.topic) ORDER BY l.speaker,l.topic),'[]') FROM public.speaker_topic_links l JOIN public.speakers s ON s.id=l.speaker JOIN public.speaker_topics t ON t.id=l.topic WHERE s.occasion=p_scope_id AND t.occasion=p_scope_id AND NOT s.is_hidden AND NOT t.is_hidden)
      ) INTO v_payload;
    WHEN 'unit_catalog' THEN
      SELECT jsonb_build_object('unit',jsonb_build_object('id',u.id,'title',u.title,'data',u.data,'features',u.features),
        'occasions',COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'title',o.title,'link',o.link,'startTime',o.start_time,'endTime',o.end_time,'description',o.description,'isOpen',o.is_open,'isPromoted',o.is_promoted) ORDER BY o.start_time,o.id) FILTER (WHERE o.id IS NOT NULL),'[]')) INTO v_payload
      FROM public.occasions current_o JOIN public.units u ON u.id=current_o.unit
      LEFT JOIN public.occasions o ON o.unit=u.id AND NOT o.is_hidden
      WHERE current_o.id=p_scope_id GROUP BY u.id;
    WHEN 'live_public' THEN
      SELECT jsonb_build_object(
        'events',(SELECT COALESCE(jsonb_agg(jsonb_build_object('eventId',s.event,'participantCount',s.participant_count,'savedCount',s.saved_count,'remainingCapacity',s.remaining_capacity) ORDER BY s.event),'[]') FROM public.event_public_state s JOIN public.events e ON e.id=s.event WHERE s.occasion=p_scope_id AND NOT e.is_hidden),
        'cleaning',(SELECT COALESCE(jsonb_agg(jsonb_build_object('placeId',s.place,'status',s.status,'openReportCount',s.open_report_count) ORDER BY s.place),'[]') FROM public.cleaning_public_state s WHERE s.occasion=p_scope_id),
        'newsViews',public.get_news_view_counts_v1(p_scope_id)
      ) INTO v_payload;
    ELSE RAISE EXCEPTION 'unsupported public component %',p_component;
  END CASE;
  RETURN jsonb_build_object('protocol',1,'schema',1,'component',p_component,
    'scope',((SELECT organization FROM public.occasions WHERE id=p_scope_id))::text||'/'||p_scope_id::text,
    'revision',v_revision,'generatedAt',COALESCE(v_generated_at,'epoch'::timestamptz),'payload',v_payload);
END; $$;
REVOKE ALL ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_client_sync_component_v1(text,text,bigint)
  TO service_role;

-- A changed read marker affects both the user's private marker and the public
-- cumulative counts. One commit advances both revisions atomically.
CREATE OR REPLACE FUNCTION public.mark_news_read_client_sync_v1(
  p_occasion bigint,p_news_id bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '' AS $$
DECLARE
  v_user uuid:=auth.uid();
  v_revision bigint;
  v_begin jsonb;
  v_commit jsonb;
  v_read_at timestamptz;
  v_data jsonb;
  v_response jsonb;
  v_request_sha256 text;
BEGIN
  IF v_user IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
       WHERE ou.occasion=p_occasion AND ou."user"=v_user)
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

  SELECT COALESCE(source_revision,0) INTO v_revision
  FROM (SELECT 1) seed LEFT JOIN public.client_sync_private_scopes s
    ON s.component='private_news' AND s.occasion=p_occasion AND s.user_id=v_user;
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
    'changedFields',jsonb_build_array('news_id'))),ARRAY['live_public'],jsonb_build_array(
      jsonb_build_object('component','private_news','userId',v_user)),jsonb_build_array(
      jsonb_build_object('component','live_public','entityId',p_news_id)),
    'user',NULL);
  SELECT source_revision INTO v_revision FROM public.client_sync_private_scopes
    WHERE component='private_news' AND occasion=p_occasion AND user_id=v_user;
  v_data:=v_data||jsonb_build_object('revision',v_revision);
  v_response:=jsonb_build_object('status','applied','code',200,'data',v_data,
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit->>'commitId','replayed',false,
      'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(jsonb_build_object(
      'component','private_news','revision',v_revision,'payload',v_data->'payload'))));
  RETURN public.finish_client_mutation_v1(
    p_command_id,v_response,(v_commit->>'commitId')::uuid);
END; $$;
REVOKE ALL ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_news_read_client_sync_v1(bigint,bigint,uuid)
  TO authenticated;

-- Publish the newly added live field once for already-enabled scopes. Future
-- changes are advanced by mark_news_read_client_sync_v1 above.
DO $$
DECLARE v_occasion bigint;
BEGIN
  FOR v_occasion IN
    SELECT o.id FROM public.occasions o
    WHERE NOT o.is_hidden
      AND COALESCE((o.data->>'client_sync_v1')::boolean,false)
  LOOP
    PERFORM public.record_client_sync_commit_v1(
      v_occasion,'migration.news_views_projection','news',
      jsonb_build_array(jsonb_build_object(
        'entityType','news_views','entityId',NULL,'operation','update',
        'safeLabel','News views','changedFields',jsonb_build_array('views'))),
      ARRAY['live_public'],'[]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'component','live_public','entityId',0)),
      'service',NULL
    );
  END LOOP;
END $$;
