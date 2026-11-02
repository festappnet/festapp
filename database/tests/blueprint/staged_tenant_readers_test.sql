-- test-setup: database/tests/blueprint/fixtures.sql


BEGIN;
DO $$
DECLARE f jsonb; selected jsonb; r jsonb; sid bigint; admin_r jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN
  UPDATE eshop.blueprints SET objects='[{"type":"spot"}]' WHERE id=(f->>'blueprint')::bigint;
  RAISE EXCEPTION 'Retired geometry accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'new blank plans already use canonical storage');
 r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((r->>'code')::int,200,'admin reads the same canonical blank plan');
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq((r->>'code')::int,200,'canonical aggregate saved');
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'converted public reader works');
 PERFORM public.assert_eq((r->'data') ? 'objects',false,'converted reader omits legacy geometry');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,spots}'),4,'converted reader uses bindings');
 admin_r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((admin_r->'data') ? 'objects',false,'converted admin omits legacy geometry');
 INSERT INTO public.organizations(id,title) VALUES(3,'Selected rollout tenant') ON CONFLICT(id) DO NOTHING;
 selected:=public.blueprint_test_fixture_internal(3);
 r:=public.get_blueprint(gen_random_uuid(),(selected->>'formKey')::uuid,(selected->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'selected tenant uses the same canonical reader');
 PERFORM public.assert_eq(to_regprocedure('public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint)') IS NULL,true,'legacy helper not callable publicly');
 PERFORM public.assert_eq(to_regprocedure('public.get_blueprint_for_edit_legacy_rollout_internal(text)') IS NULL,true,'admin helper not callable directly');
END $$;
ROLLBACK;
