BEGIN;
ALTER FUNCTION public.notification_center_prepared_display_key(uuid,integer,integer,text[]) RENAME TO notification_display_key_test_original;
CREATE FUNCTION public.notification_center_prepared_display_key(p_token uuid,p_cursor integer,p_limit integer,p_scopes text[] DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $counter$
BEGIN
 PERFORM set_config('festapp_test.display_calls',(coalesce(nullif(current_setting('festapp_test.display_calls',true),''),'0')::integer+1)::text,true);
 RETURN public.notification_display_key_test_original(p_token,p_cursor,p_limit,p_scopes);
END $counter$;
-- Count real canonical ACL invocations without requiring privileged profiling.
-- The transaction restores the original function name and grants on rollback.
ALTER FUNCTION public.notification_center_allowed(public.notification_center_events,uuid) RENAME TO notification_center_allowed_test_original;
CREATE FUNCTION public.notification_center_allowed(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $counter$
BEGIN
 PERFORM set_config('festapp_test.notification_acl_calls',(coalesce(nullif(current_setting('festapp_test.notification_acl_calls',true),''),'0')::bigint+1)::text,true);
 RETURN public.notification_center_allowed_test_original(p_event,p_user);
END $counter$;
DO $$
DECLARE org bigint;oc bigint;first_oc bigint;viewer uuid:=gen_random_uuid();v jsonb;t timestamptz;ms numeric;n bigint;before_calls bigint;after_calls bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Více pořadatelových událostí') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(viewer);
 INSERT INTO public.user_info(id,organization) VALUES(viewer,org);
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,viewer,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day');
 FOR i IN 1..111 LOOP
  INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Ples '||i,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
  first_oc:=coalesce(first_oc,oc);
  INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,viewer,true);
  IF i<=89 THEN PERFORM public.notification_center_publish_internal(org,oc,'order_created','scope:'||i,jsonb_build_object('count',1,'formContext',jsonb_build_object('allowsMultiple',false)));END IF;
 END LOOP;
 FOR i IN 1..20 LOOP PERFORM public.project_notification_center(500);END LOOP;
 PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
 v:=public.get_notification_center_view(org,NULL);
 FOR i IN 1..20 LOOP PERFORM public.prepare_notification_center(100);END LOOP;
 PERFORM set_config('festapp_test.notification_acl_calls','0',true);
 SELECT count(*) INTO n FROM public.notification_center_prepared_allowed_scopes(org,NULL,viewer);
 after_calls:=current_setting('festapp_test.notification_acl_calls')::bigint;before_calls:=0;
 PERFORM assert_eq(n,445::bigint,'representative wide organization has 445 live scopes');
 PERFORM assert_true(after_calls-before_calls<=1,'candidate discovery must not authorize three dummy events per occasion');
 PERFORM set_config('festapp_test.display_calls','0',true);
 t:=clock_timestamp();v:=public.get_notification_center_view(org,NULL);ms:=extract(epoch FROM clock_timestamp()-t)*1000;
 PERFORM assert_eq(current_setting('festapp_test.display_calls'),'1','one open computes its live display fingerprint once');
 PERFORM assert_eq(v->>'state','ready','wide organization opens ready');
 PERFORM assert_eq(jsonb_array_length(v->'items'),30,'wide organization opens thirty nonempty rows');
 PERFORM assert_true(ms<750,'wide organization opening must stay below the existing 750ms loading gate');
 RAISE NOTICE 'Wide notification open: % ms, 445 scopes, 30 rows',round(ms,1);
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=first_oc AND "user"=viewer;
 v:=public.get_notification_center_view(org,NULL,p_mode=>'refresh',p_view=>(v->>'viewToken')::uuid,p_revision=>v->>'revision');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') x WHERE (x->>'occasionId')::bigint=first_oc AND x->>'state'='ready'),'live role revocation cannot reuse a private unchanged payload');
END $$;
ROLLBACK;
