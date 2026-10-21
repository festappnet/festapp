-- test-setup: database/tests/blueprint/fixtures.sql
DO $$
DECLARE f jsonb; occ bigint; un bigint; actor uuid; outsider uuid:=gen_random_uuid();
BEGIN
 f:=public.blueprint_test_fixture_internal();occ:=(f->>'occasion')::bigint;actor:=(f->>'actor')::uuid;
 SELECT unit INTO un FROM public.occasions WHERE id=occ;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 SET LOCAL ROLE authenticated;
 PERFORM public.assert_true(public.can_write_blueprints(occ),'fixture geometry editor');
 PERFORM public.assert_true(public.admit_layout_resources_limits_v1(occ,1000) ? 'abuseLimits','geometry editor loads font and renamed-table text');
 PERFORM public.assert_true(public.admit_ticket_preview_limits_v1(occ,1000,false) IS NULL,'geometry permission does not grant editable ticket preview');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor=false,is_manager=true WHERE occasion=occ AND "user"=actor;
 SET LOCAL ROLE authenticated;
 PERFORM public.assert_true(public.admit_layout_resources_limits_v1(occ,1000) ? 'abuseLimits','geometry manager loads shared resources');
 RESET ROLE;
 UPDATE public.occasion_users SET is_manager=false,is_editor_order=true WHERE occasion=occ AND "user"=actor;
 SET LOCAL ROLE authenticated;
 PERFORM public.assert_true(public.admit_layout_resources_limits_v1(occ,1000) IS NULL,'order-only membership cannot prepare editor resources');
 RESET ROLE;
 INSERT INTO public.unit_users(unit,"user",is_editor) VALUES(un,actor,true);
 SET LOCAL ROLE authenticated;
 PERFORM public.assert_true(public.admit_layout_resources_limits_v1(occ,1000) ? 'abuseLimits','ticket editor retains shared font access');
 PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
 PERFORM public.assert_true(public.admit_layout_resources_limits_v1(occ,1000) IS NULL,'foreign actor cannot load resources');
 RESET ROLE;
 PERFORM public.assert_false(has_function_privilege('anon','public.admit_layout_resources_limits_v1(bigint,bigint)','execute'),'anonymous caller has no admission grant');
END $$;
