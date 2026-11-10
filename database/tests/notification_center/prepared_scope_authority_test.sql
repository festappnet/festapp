BEGIN;
ALTER FUNCTION public.notification_center_bank_admin(bigint,uuid) RENAME TO notification_bank_admin_test_original;
CREATE FUNCTION public.notification_center_bank_admin(p_bank bigint,p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $counter$
BEGIN
 PERFORM set_config('festapp_test.bank_calls',(coalesce(nullif(current_setting('festapp_test.bank_calls',true),''),'0')::integer+1)::text,true);
 RETURN public.notification_bank_admin_test_original(p_bank,p_user);
END $counter$;
DO $$
DECLARE org bigint;other_org bigint;un bigint;oc bigint;demo bigint;foreign_oc bigint;bank bigint;demo_bank bigint;conn bigint;alias_bank bigint;foreign_bank bigint;foreign_unit bigint;
 users uuid[]:=ARRAY[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];usr uuid;occasion_id bigint;kind text;affected bigint[];rights text[];e public.notification_center_events;expected boolean;actual boolean;checks integer:=0;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Oprávnění oznámení','{"IS_APP_SUPPORTED":true}') RETURNING id INTO org;
 INSERT INTO public.organizations(title,data) VALUES('Jiný pořadatel','{"IS_APP_SUPPORTED":true}') RETURNING id INTO other_org;
 INSERT INTO auth.users(id) SELECT unnest(users);
 INSERT INTO public.user_info(id,organization) SELECT u,org FROM unnest(users) u;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO un;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,un,'Ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,un,'Ukázka',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO demo;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES(other_org,'Cizí ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,users[1],true),(other_org,users[7],true);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor,is_manager,is_editor_view)
 SELECT o,users[2],true,false,false,false FROM unnest(ARRAY[oc,demo]) o
 UNION ALL SELECT oc,users[3],false,true,false,false
 UNION ALL SELECT oc,users[4],false,false,true,false
 UNION ALL SELECT oc,users[6],false,false,false,true;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Banka pořadatele','FIO') RETURNING id INTO bank;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Ukázková banka','FIO') RETURNING id INTO demo_bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at) VALUES(demo,org,'ball','scope-authority',demo_bank,1,'Ukázka plesu',now());
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,users[5],true),(un,users[9],true);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,users[5],true),(bank,users[8],true),(bank,users[9],false);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256,bank_pull_at)
 VALUES(gen_random_uuid()::text,'festapp','123',bank,gen_random_uuid()::text,'FIO','api','connected',repeat('a',64),now()) RETURNING id INTO conn;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Sdílený účet','FIO') RETURNING id INTO alias_bank;
 INSERT INTO eshop.bank_accounts(title,type) VALUES('Účet jiného pořadatele','FIO') RETURNING id INTO foreign_bank;
 INSERT INTO public.units(title,organization) VALUES('Jiný pořadatel',other_org) RETURNING id INTO foreign_unit;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,alias_bank),(un,demo_bank),(foreign_unit,foreign_bank);
 INSERT INTO eshop.bank_sync_account_aliases(bank_account_id,connection_id) VALUES(alias_bank,conn),(demo_bank,conn),(foreign_bank,conn);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(alias_bank,users[9],true),(demo_bank,users[3],true),(foreign_bank,users[6],true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,users[3],true),(foreign_unit,users[6],true);
 FOREACH usr IN ARRAY users||ARRAY[NULL::uuid] LOOP
  PERFORM set_config('request.jwt.claim.sub',coalesce(usr::text,''),true);
  PERFORM set_config('festapp_test.bank_calls','0',true);
  SELECT ARRAY(SELECT scope FROM public.notification_center_prepared_allowed_scopes(org,NULL,usr) ORDER BY scope) INTO rights;
  PERFORM assert_true(current_setting('festapp_test.bank_calls')::bigint<=(SELECT count(*) FROM eshop.bank_account_users WHERE "user"=usr),'bank authority is evaluated at most once per user account during scope discovery');
  FOREACH occasion_id IN ARRAY ARRAY[oc,demo,foreign_oc,NULL::bigint] LOOP
   FOREACH kind IN ARRAY ARRAY['order_created','order_cancelled','waitlist_registered','offer_accepted','offer_declined','offer_expired','capacity_warning','capacity_full','sale_opened','occasion_joined','event_capacity_full','email_problem','bank_problem'] LOOP
    FOREACH affected SLICE 1 IN ARRAY ARRAY[ARRAY[oc],ARRAY[demo],ARRAY[foreign_oc]] LOOP
     e:=jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',org,'occasion',occasion_id,'kind',kind,'data',jsonb_build_object('bankConnectionId',conn),'affected_occasions',to_jsonb(affected)));
     expected:=public.notification_center_allowed(e,usr);actual:=public.notification_center_prepared_event_access(e,org,rights);
     PERFORM assert_true(actual IS NOT DISTINCT FROM expected,'batched live permissions match canonical event authority: '||kind);checks:=checks+1;
    END LOOP;
   END LOOP;
  END LOOP;
  e:=jsonb_populate_record(NULL::public.notification_center_events,jsonb_build_object('organization',org,'kind','order_created','affected_occasions','[]'::jsonb,'data','{}'::jsonb));
  PERFORM assert_false(public.notification_center_prepared_event_access(e,org,rights),'null occasion cannot authorize an unscoped order');
  PERFORM assert_false(public.notification_center_prepared_event_access(e,other_org,rights),'rights cannot cross the token organization');
 END LOOP;
 RAISE NOTICE 'Live scope authority equivalence: % cases',checks;
END $$;
ROLLBACK;
