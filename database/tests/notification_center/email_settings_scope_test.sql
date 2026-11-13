BEGIN;
DO $$
DECLARE unit_a bigint; unit_b bigint; oc_b bigint; oc_null bigint; hidden_oc bigint; org bigint; oc bigint; u uuid:=gen_random_uuid(); metadata jsonb; snapshot jsonb; before_revision bigint; d uuid; event public.notification_center_events;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Portál pro pořadatele','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 INSERT INTO auth.users(id) VALUES(u);
 INSERT INTO public.user_info(id,organization,email_delivery) VALUES(u,org,'notification-settings@example.test');
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Ples hasičů',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order_view) VALUES(oc,u,true,true);
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day');
 UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000;
 PERFORM public.activate_notification_center_emails(org);
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 metadata:=public.notification_center_email_settings_internal(org);
 PERFORM assert_false(metadata->'catalog' ? 'occasion_joined','ticketing-only portal offers no participant email category');
 PERFORM assert_eq(metadata#>>'{catalog,waitlist_registered}','orders','waiting-list registrations share the order control without requiring application support');
 PERFORM assert_eq(metadata#>>'{catalog,offer_accepted}','orders','waiting-list offer responses share the same canonical order control');
 PERFORM assert_eq(metadata#>>'{catalog,order_created}','orders','orders and waiting-list registrations share one canonical category');
 PERFORM assert_false(metadata ? 'scopeCatalogs','settings expose no occasion override catalog');
 UPDATE public.organizations SET data='{"IS_APP_SUPPORTED":true}' WHERE id=org;
 metadata:=public.notification_center_email_settings_internal(org);
 PERFORM assert_eq(metadata#>>'{catalog,occasion_joined}','participants','application participant category is available only after support is enabled');
 PERFORM assert_eq(public.save_notification_center_email_settings(org,0,false,'cs','{"order_created":true,"waitlist_registered":true}'),1::bigint,'one portal category subscription saves');
 PERFORM assert_eq((SELECT count(*) FROM public.notification_center_email_subscriptions WHERE recipient=u AND organization=org),1::bigint,'one subscription per recipient and portal');
 -- The one retained wire adapter supports the last released null-scope client.
 PERFORM assert_eq(public.save_notification_center_email_settings(org,NULL,1,false,'cs','{"order_created":true,"waitlist_registered":true}'),2::bigint,'released default writer delegates to the canonical writer');
 BEGIN
  PERFORM public.save_notification_center_email_settings(org,oc,2,false,'cs','{"order_created":false}');
  RAISE EXCEPTION 'occasion override accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'notification_email_occasion_settings_removed' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT revision FROM public.notification_center_email_profiles WHERE recipient=u),2::bigint,'rejected legacy occasion write changes no preferences');
 -- One canonical mute controls both projection and optional external delivery.
 event:=jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',org,'occasion',oc,'kind','order_created','occurred_at',clock_timestamp()));
 PERFORM assert_not_null(public.notification_center_email_enabled_internal(event,u,ARRAY['orders:'||oc]),'unmuted accessible occasion follows portal categories');
 INSERT INTO public.notification_center_preferences(organization,recipient,occasion,muted) VALUES(org,u,oc,true);
 PERFORM assert_true(public.notification_center_email_enabled_internal(event,u,ARRAY['orders:'||oc]) IS NULL,'existing occasion mute suppresses optional email without another override');
 PERFORM assert_false(EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='notification_center_email_subscriptions' AND column_name='occasion'),'occasion subscription storage is removed');
 metadata:=public.notification_center_email_settings_internal(org);
 PERFORM assert_true(metadata#>'{kinds,order_created,enabled}'='true'::jsonb,'muting does not rewrite the portal category setting');
 INSERT INTO public.units(organization,title) VALUES(org,'Skauti') RETURNING id INTO unit_a;
 INSERT INTO public.units(organization,title) VALUES(org,'Obec Větřkovice') RETURNING id INTO unit_b;
 UPDATE public.occasions SET unit=unit_a WHERE id=oc;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,unit_b,'Obecní ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc_b;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(org,'Večerní koncert',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc_null;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,unit_b,'Soukromá akce',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO hidden_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc_b,u,true),(oc_null,u,true);
 metadata:=public.get_notification_center_settings(org,0,1);
 PERFORM assert_eq(metadata#>>'{items,0,unit}',unit_a::text,'unit metadata belongs to the authorized occasion');
 PERFORM assert_eq(metadata#>>'{items,0,unitTitle}','Skauti','unit label is supplied by the existing settings query');
 PERFORM assert_eq(metadata->>'nextCursor',oc::text,'unit metadata preserves occasion cursor order');
 metadata:=public.get_notification_center_settings(org,oc,1);
 PERFORM assert_eq(metadata#>>'{items,0,unitTitle}','Obec Větřkovice','a different unit remains independently labelled across pages');
 metadata:=public.get_notification_center_settings(org,oc_b,100);
 PERFORM assert_eq(jsonb_array_length(metadata->'items'),1,'group metadata does not expose another occasion merely from its unit');
 PERFORM assert_true(metadata#>'{items,0,unit}'='null'::jsonb,'occasions without a unit remain accessible without an invented organizer');
 PERFORM assert_false(has_function_privilege('anon','public.save_notification_center_email_settings(bigint,bigint,boolean,text,jsonb)','EXECUTE'),'anonymous clients cannot write subscription settings');
END $$;
ROLLBACK;
