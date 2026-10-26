BEGIN;

DO $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_occasion bigint;
  v_event bigint;
  v_empty_event bigint;
  v_user_one uuid;
  v_user_two uuid;
  v_news_old bigint;
  v_news_new bigint;
  v_live jsonb;
  v_config jsonb;
  v_media_revision bigint;
  v_token uuid;
  v_command uuid:=gen_random_uuid();
  v_client uuid:=gen_random_uuid();
  v_response jsonb;
  v_current_url text:='https://assets.festapp.net/client-sync/v1/test/current.json';
  v_candidate_url text:='https://assets.festapp.net/client-sync/v1/test/old.json';
BEGIN
  SELECT id INTO v_organization FROM public.organizations ORDER BY id LIMIT 1;
  SELECT id INTO v_unit FROM public.units WHERE organization=v_organization ORDER BY id LIMIT 1;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open)
  VALUES (v_organization,v_unit,'Hardening test',gen_random_uuid()::text,
    now(),now()+interval '1 day',true) RETURNING id INTO v_occasion;
  INSERT INTO public.events(occasion,title,start_time,end_time,is_hidden)
  VALUES (v_occasion,'Projected event',now(),now()+interval '1 hour',false)
  RETURNING id INTO v_event;
  INSERT INTO public.events(occasion,title,start_time,end_time,is_hidden)
  VALUES (v_occasion,'Empty projected event',now(),now()+interval '1 hour',false)
  RETURNING id INTO v_empty_event;
  PERFORM create_user_for_test('client_sync_live_one','client_sync_live_one@test.local');
  PERFORM create_user_for_test('client_sync_live_two','client_sync_live_two@test.local');
  v_user_one:=get_user_id('client_sync_live_one');
  v_user_two:=get_user_id('client_sync_live_two');
  INSERT INTO public.occasion_users(occasion,"user",is_approved) VALUES
    (v_occasion,v_user_one,true),(v_occasion,v_user_two,true);
  UPDATE public.occasion_users SET is_editor=true
    WHERE occasion=v_occasion AND "user"=v_user_one;
  INSERT INTO public.event_users(event,"user") VALUES(v_event,v_user_one);
  INSERT INTO public.event_users_saved(event,"user") VALUES
    (v_event,v_user_one),(v_event,v_user_two);
  INSERT INTO public.news(occasion,message,created_by)
  VALUES(v_occasion,'Older live-count fixture',v_user_one) RETURNING id INTO v_news_old;
  INSERT INTO public.news(occasion,message,created_by)
  VALUES(v_occasion,'Newer live-count fixture',v_user_one) RETURNING id INTO v_news_new;
  INSERT INTO public.user_news(news_id,"user",occasion) VALUES
    (v_news_old,v_user_one,v_occasion),(v_news_new,v_user_two,v_occasion);
  INSERT INTO public.client_sync_scopes(component,scope_type,scope_id,source_revision)
  VALUES ('live_public','occasion',v_occasion,1);
  INSERT INTO public.client_projection_dirty_keys
    (component,scope_type,scope_id,entity_id,source_revision)
  VALUES ('live_public','occasion',v_occasion,0,1);

  PERFORM set_config('request.jwt.claim.sub',v_user_one::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM public.add_image_record(
    'https://img.festapp.net/images/offline-description.webp',v_occasion,NULL);
  SELECT source_revision INTO v_media_revision
  FROM public.client_sync_scopes WHERE component='occasion_config'
    AND scope_type='occasion' AND scope_id=v_occasion;
  PERFORM assert_eq(v_media_revision::text,'1',
    'adding occasion media advances occasion_config');

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  v_config:=public.get_public_client_sync_component_v1(
    'occasion_config','occasion',v_occasion);
  PERFORM assert_eq(v_config#>>'{payload,media,0,url}',
    'https://img.festapp.net/images/offline-description.webp',
    'occasion_config publishes the complete media manifest');

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM public.remove_image_records(
    ARRAY['https://img.festapp.net/images/offline-description.webp']);
  SELECT source_revision INTO v_media_revision
  FROM public.client_sync_scopes WHERE component='occasion_config'
    AND scope_type='occasion' AND scope_id=v_occasion;
  PERFORM assert_eq(v_media_revision::text,'2',
    'removing occasion media advances occasion_config');

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  SELECT claim_token INTO STRICT v_token
  FROM public.claim_client_projection_dirty_scopes_v1(ARRAY[v_occasion],10)
  WHERE component='live_public';
  PERFORM assert_eq(public.release_client_projection_claims_v1(ARRAY[v_token]),1,
    'failed publisher class releases its exact claim');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.client_projection_dirty_keys
    WHERE scope_id=v_occasion AND claim_token IS NULL AND claimed_at IS NULL),
    'released work is immediately reclaimable');

  PERFORM public.refresh_event_public_state_v1(v_occasion,NULL);
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.event_public_state
    WHERE occasion=v_occasion AND event=v_event),
    'null event IDs perform a full visible-event refresh');
  v_live:=public.get_public_client_sync_component_v1(
    'live_public','occasion',v_occasion);
  PERFORM assert_eq((SELECT item->>'participantCount' FROM
    jsonb_array_elements(v_live#>'{payload,events}') item
    WHERE (item->>'eventId')::bigint=v_event),'1',
    'live projection publishes the authoritative participant count');
  PERFORM assert_eq((SELECT item->>'savedCount' FROM
    jsonb_array_elements(v_live#>'{payload,events}') item
    WHERE (item->>'eventId')::bigint=v_event),'2',
    'live projection publishes the authoritative saved count');
  PERFORM assert_eq((SELECT item->>'participantCount' FROM
    jsonb_array_elements(v_live#>'{payload,events}') item
    WHERE (item->>'eventId')::bigint=v_empty_event),'0',
    'an authoritative empty event is explicitly published as zero');
  PERFORM assert_eq((SELECT item->>'views' FROM
    jsonb_array_elements(v_live#>'{payload,newsViews}') item
    WHERE (item->>'newsId')::bigint=v_news_old),'2',
    'older news includes readers whose marker advanced past it');
  PERFORM assert_eq((SELECT item->>'views' FROM
    jsonb_array_elements(v_live#>'{payload,newsViews}') item
    WHERE (item->>'newsId')::bigint=v_news_new),'1',
    'newer news includes only readers who reached it');
  UPDATE public.events SET is_hidden=true WHERE id=v_event;
  PERFORM public.refresh_event_public_state_v1(v_occasion,ARRAY[v_event]);
  PERFORM assert_true(NOT EXISTS (SELECT 1 FROM public.event_public_state
    WHERE occasion=v_occasion AND event=v_event),
    'targeted refresh removes a newly hidden event without touching other rows');

  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_client_id,request_sha256,status,
     response,created_at,completed_at)
  VALUES (v_command,'hardening.expired',v_occasion,v_client,repeat('a',64),
    'completed',jsonb_build_object('status','applied','code',200),
    now()-interval '32 days',now()-interval '31 days');
  v_response:=public.compact_client_mutation_receipts_v1(
    now()-interval '30 days',10);
  PERFORM assert_eq(v_response->>'compacted','1','old exact response is compacted once');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.client_mutation_receipts
    WHERE command_id=v_command AND status='expired' AND response IS NULL
      AND expired_at IS NOT NULL),
    'compaction preserves a response-less command tombstone');

  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM set_config('request.jwt.claim.sub','',true);
  v_response:=public.begin_anonymous_client_mutation_v1(
    v_command,'hardening.expired',v_occasion,v_client,repeat('a',64));
  PERFORM assert_eq(v_response->>'disposition','replay',
    'expired command ID remains permanently claimed');
  PERFORM assert_eq(v_response#>>'{response,code}','410',
    'expired replay is deterministic and bounded');

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  INSERT INTO public.client_sync_publications
    (component,scope_type,scope_id,published_revision,media_type,artifact_url,
     sha256,byte_size,published_at)
  VALUES
    ('live_public','occasion',v_occasion,1,'application/json',v_current_url,
      repeat('1',64),10,now()-interval '20 days'),
    ('live_public','occasion',v_occasion,2,'application/json',v_candidate_url,
      repeat('2',64),10,now()-interval '20 days'),
    ('live_public','occasion',v_occasion,3,'application/json',
      'https://assets.festapp.net/client-sync/v1/test/young.json',repeat('3',64),10,now()),
    ('live_public','occasion',v_occasion,4,'application/json',
      'https://assets.festapp.net/csmostrava2026/v4/map.json',repeat('4',64),10,
      now()-interval '20 days');
  INSERT INTO public.client_sync_public_heads
    (scope_type,scope_id,release_revision,manifest_sha256,live_revision,live_sha256,
     head_etag,head_json)
  VALUES ('occasion',v_occasion,NULL,NULL,1,repeat('1',64),'"head"',
    jsonb_build_object('protocol',1,'live',jsonb_build_object(
      'revision',1,'url',v_current_url,'sha256',repeat('1',64))));
  PERFORM assert_eq((SELECT count(*) FROM
    public.get_client_sync_artifact_retention_candidates_v1(
      now()-interval '7 days',100) c WHERE c.artifact_url IN
      (v_current_url,v_candidate_url,
       'https://assets.festapp.net/client-sync/v1/test/young.json',
       'https://assets.festapp.net/csmostrava2026/v4/map.json')),1::bigint,
    'only old unprotected client-sync metadata is a retention candidate');
  PERFORM assert_true(NOT public.delete_client_sync_artifact_metadata_v1(
    v_current_url,now()-interval '7 days'),
    'metadata recheck refuses the current live descriptor');
  PERFORM assert_true(public.delete_client_sync_artifact_metadata_v1(
    v_candidate_url,now()-interval '7 days'),
    'metadata recheck acknowledges one exact old unprotected URL');
END $$;

ROLLBACK;
