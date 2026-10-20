DO $$
DECLARE actor uuid; org bigint; un bigint; oc bigint; first jsonb; second jsonb;
 result jsonb; history jsonb; newer_history jsonb; command uuid:=gen_random_uuid(); published bigint;
BEGIN
 PERFORM public.create_user_for_test('selected-draft','selected-draft@example.invalid');actor:=public.get_user_id('selected-draft');
 INSERT INTO public.organizations(title) VALUES('Selected draft') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Selected draft',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Selected draft',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view) VALUES(oc,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 ASSERT public.save_activity_history(oc,'{}','PUBLISH',NULL)->>'code'='426';
 ASSERT public.update_activities(oc,'[]')->>'code'='426';
 history:=public.activity_graph_history_internal_v1('[]');
 newer_history:=public.activity_graph_history_internal_v1(public.normalize_activity_graph_internal_v1(oc,
   jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'title','Newer draft','is_hidden',false,'order',0,'assignments','[]'::jsonb)),true));
 first:=public.save_activity_draft_client_sync_v1(oc,gen_random_uuid(),0,history,NULL);
 second:=public.save_activity_draft_client_sync_v1(oc,gen_random_uuid(),0,newer_history,NULL);
 ASSERT first#>>'{data,draftId}'<>second#>>'{data,draftId}';
 history:=history||jsonb_build_object('_consume_autosave',jsonb_build_object('id',first#>'{data,draftId}'));
 result:=public.publish_activities_client_sync_v1(oc,command,0,'[]',history,NULL);
 ASSERT result->>'code'='200';ASSERT result#>>'{data,draftConsumed}'='false';
 ASSERT public.publish_activities_client_sync_v1(oc,command,0,'[]',history,NULL)=result;
 ASSERT EXISTS(SELECT 1 FROM public.activity_history WHERE id=(second#>>'{data,draftId}')::bigint),'newer tab draft must survive publication and replay';
 SELECT id INTO published FROM public.activity_history WHERE occasion_id=oc AND history_type='PUBLISH';
 ASSERT (SELECT NOT activities_data ? '_consume_autosave' FROM public.activity_history WHERE id=published);
 history:=history||jsonb_build_object('_consume_autosave',jsonb_build_object('id',second#>'{data,draftId}'));
 result:=public.publish_activities_client_sync_v1(oc,gen_random_uuid(),0,'[]',history,published);
 ASSERT result->>'status'='conflict';
 ASSERT EXISTS(SELECT 1 FROM public.activity_history WHERE id=(second#>>'{data,draftId}')::bigint),'stale publish must not consume draft';
 result:=public.publish_activities_client_sync_v1(oc,gen_random_uuid(),1,'[]',history,published);
 ASSERT result->>'status'='applied';ASSERT result#>>'{data,draftConsumed}'='true';
 ASSERT NOT EXISTS(SELECT 1 FROM public.activity_history WHERE id=(second#>>'{data,draftId}')::bigint);
 second:=public.save_activity_draft_client_sync_v1(oc,gen_random_uuid(),1,newer_history,published);
 result:=public.publish_activities_client_sync_v1(oc,gen_random_uuid(),1,'[]',history-'_consume_autosave',published);
 ASSERT result->>'status'='unchanged';
 ASSERT EXISTS(SELECT 1 FROM public.activity_history WHERE id=(second#>>'{data,draftId}')::bigint),'legacy publication cannot clear a different draft graph';
END $$;
