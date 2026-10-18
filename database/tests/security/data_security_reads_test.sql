DO $$
DECLARE o bigint; other_o bigint; org bigint; unit_id bigint; g bigint; p bigint;
 member uuid; stranger uuid; editor uuid; n bigint; n2 bigint; result jsonb; cnt bigint;
BEGIN
 PERFORM create_user_for_test('ds_member','ds_member@test.local');member:=get_user_id('ds_member');
 PERFORM create_user_for_test('ds_stranger','ds_stranger@test.local');stranger:=get_user_id('ds_stranger');
 PERFORM create_user_for_test('ds_editor','ds_editor@test.local');editor:=get_user_id('ds_editor');
 INSERT INTO public.organizations(title) VALUES('DS target') RETURNING id INTO org;
 INSERT INTO public.units(organization,title) VALUES(org,'DS unit') RETURNING id INTO unit_id;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden,data)
 VALUES(org,unit_id,'Secret occasion',gen_random_uuid()::text,now(),now()+interval '1 day',true,true,'{"secret":"private"}') RETURNING id INTO o;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden)
 VALUES(org,unit_id,'Public occasion',gen_random_uuid()::text,now(),now()+interval '1 day',true,false) RETURNING id INTO other_o;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_approved)
 VALUES(o,member,false,false,true),(o,editor,true,true,true);
 INSERT INTO public.places(occasion,title,type,is_hidden) VALUES(o,'Secret location','group',true) RETURNING id INTO p;
 INSERT INTO public.user_group_info(occasion,title,place) VALUES(o,'Secret group',p) RETURNING id INTO g;
 INSERT INTO public.user_groups("group","user",is_admin) VALUES(g,member,false),(g,editor,true);
 UPDATE public.user_info SET phone='secret',data='{"secret":true}' WHERE id=editor;
 INSERT INTO public.news(occasion,message) VALUES(o,'One') RETURNING id INTO n;
 INSERT INTO public.news(occasion,message) VALUES(o,'Two') RETURNING id INTO n2;
 INSERT INTO public.user_news(occasion,"user",news_id) VALUES(o,member,n2);
 PERFORM set_config('request.jwt.claim.sub',member::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 SELECT count(*) INTO cnt FROM public.user_group_info WHERE id=g;
 IF cnt<>1 THEN RAISE EXCEPTION 'member lost group'; END IF;
 result:=public.get_user_group_info_with_users(g);
 IF result#>>'{places,title}'<>'Secret location' THEN RAISE EXCEPTION 'member lost private location'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'user_groups') peer
   WHERE (peer->'user_info')-ARRAY['id','name','surname']<>'{}'::jsonb) THEN RAISE EXCEPTION 'peer fields leaked'; END IF;
 result:=public.get_occasion_for_context_v1(o);
 IF (result->>'id')::bigint<>o THEN RAISE EXCEPTION 'member lost hidden context'; END IF;
 result:=public.mark_news_read_client_sync_v1(o,n,gen_random_uuid());
 IF result->>'code'<>'200' THEN RAISE EXCEPTION 'marker command failed'; END IF;
 result:=public.get_news_read_state_v1(o);
 IF (result->>'newsId')::bigint<>n2 THEN RAISE EXCEPTION 'delayed marker moved backwards'; END IF;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',stranger::text,true);
 SET LOCAL ROLE authenticated;
 SELECT count(*) INTO cnt FROM public.user_group_info WHERE id=g;
 IF cnt<>0 THEN RAISE EXCEPTION 'foreign group leaked'; END IF;
 SELECT count(*) INTO cnt FROM public.user_groups WHERE "group"=g;
 IF cnt<>0 THEN RAISE EXCEPTION 'foreign membership leaked'; END IF;
 SELECT count(*) INTO cnt FROM public.user_news WHERE occasion=o;
 IF cnt<>0 THEN RAISE EXCEPTION 'foreign markers leaked'; END IF;
 SELECT count(*) INTO cnt FROM public.occasions WHERE id=o;
 IF cnt<>0 THEN RAISE EXCEPTION 'hidden occasion enumerated'; END IF;
 IF public.can_read_group_data_security_v1(g) THEN RAISE EXCEPTION 'predicate exposed group'; END IF;
 BEGIN PERFORM public.get_occasion_for_context_v1(o); RAISE EXCEPTION 'foreign hidden context accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_news_read_state_v1(o); RAISE EXCEPTION 'foreign marker RPC accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 SET LOCAL ROLE anon;
 SELECT count(*) INTO cnt FROM public.places WHERE id=p;
 IF cnt<>0 THEN RAISE EXCEPTION 'private location leaked'; END IF;
 result:=public.get_occasion_for_context_v1(other_o);
 IF result ?| ARRAY['services','occasion_hidden'] OR result#>'{data,secret}' IS NOT NULL THEN RAISE EXCEPTION 'public context leaked'; END IF;
 BEGIN PERFORM public.get_occasion_for_context_v1(o); RAISE EXCEPTION 'anon hidden context accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;

-- Transport schemas cannot restore table access via effective column grants.
DO $$
DECLARE t text; r text;
BEGIN
 FOREACH t IN ARRAY ARRAY['user_group_info','user_groups','user_news','email_templates'] LOOP
 IF has_any_column_privilege('anon','public.'||t,'SELECT') THEN RAISE EXCEPTION 'anon column access: %',t; END IF;
 END LOOP;
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
 IF has_any_column_privilege(r,'public.email_templates','SELECT') THEN RAISE EXCEPTION 'template column access'; END IF;
 FOREACH t IN ARRAY ARRAY['news','user_news','user_groups','user_group_info'] LOOP
 IF has_any_column_privilege(r,'public.'||t,'INSERT,UPDATE') THEN RAISE EXCEPTION 'column write bypass: % %',r,t; END IF;
 END LOOP;
 END LOOP;
END $$;

-- The same canonical news commands serve occasions with and without sync readers.
DO $$
DECLARE o bigint; actor uuid; n bigint; r jsonb; c uuid:=gen_random_uuid();
BEGIN
 PERFORM create_user_for_test('ds_news_editor','ds_news_editor@test.local');actor:=get_user_id('ds_news_editor');
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden)
 SELECT organization,id,'DS news non-sync',gen_random_uuid()::text,now(),now()+interval '1 day',true,false FROM public.units LIMIT 1 RETURNING id INTO o;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view) VALUES(o,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 r:=public.save_news_client_sync_v1(o,c,NULL,'{"message":"News"}');
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'non-sync news create failed'; END IF;
 n:=(r#>>'{data,news,id}')::bigint;
 r:=public.get_news_for_context_v1(o);
 IF r#>>'{0,aggregate_version}'<>'1' THEN RAISE EXCEPTION 'legacy reader lost version'; END IF;
 r:=public.save_news_client_sync_v1(o,gen_random_uuid(),1,jsonb_build_object('id',n,'message','Edited'));
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'non-sync news update failed'; END IF;
 r:=public.delete_news_client_sync_v1(o,n,gen_random_uuid(),2);
 IF r->>'status'<>'applied' THEN RAISE EXCEPTION 'non-sync news delete failed'; END IF;
 BEGIN INSERT INTO public.news(occasion,message) VALUES(o,'Bypass'); RAISE EXCEPTION 'direct news write accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END $$;
