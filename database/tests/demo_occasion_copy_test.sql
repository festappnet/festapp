BEGIN;
DO $$
DECLARE actor uuid; source bigint; target bigint; copied bigint; command uuid:=gen_random_uuid(); result jsonb; replay jsonb;
BEGIN
 PERFORM create_user_for_test('demo_copy','demo-copy@example.invalid'); actor:=get_user_id('demo_copy');
 UPDATE public.user_info SET organization=1 WHERE id=actor;
 SELECT occasion INTO STRICT source FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='weekend';
 UPDATE public.demo_occasions SET is_listed=true WHERE occasion=source;
 INSERT INTO public.units(organization,title) VALUES(1,'Demo copy target') RETURNING id INTO target;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(target,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM assert_eq(jsonb_array_length(public.get_occasion_copy_units(source)),1,'only own destination');
 result:=public.duplicate_occasion_client_sync_v1(source,command,target); copied:=(result#>>'{data,occasionId}')::bigint;
 replay:=public.duplicate_occasion_client_sync_v1(source,command,target);
 PERFORM assert_eq(replay#>>'{data,occasionId}',copied::text,'same command replays copy');
 PERFORM assert_false(public.is_demo_occasion(copied),'copy is normal');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasions WHERE id=copied AND unit=target AND is_hidden AND NOT is_open AND NOT is_promoted AND occasion_hidden IS NULL),'copy starts hidden and clean');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.forms WHERE occasion=copied AND participant_capacity=24 AND waitlist_enabled AND NOT is_open AND bank_account IS NULL),'capacity copied without demo bank');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE occasion=copied),0::bigint,'no orders copied');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=copied),0::bigint,'no tickets copied');
 PERFORM assert_true(public.get_is_editor_on_occasion(copied),'copy author can edit');
 BEGIN PERFORM public.duplicate_occasion_client_sync_v1(source,gen_random_uuid(),(SELECT unit FROM public.occasions WHERE id=source));
 RAISE EXCEPTION 'demo destination accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
