-- test-setup: database/tests/blueprint/fixtures.sql


BEGIN;
DO $$
DECLARE f jsonb; selected jsonb; r jsonb; sid bigint; admin_r jsonb;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 INSERT INTO eshop.spots(occasion,blueprint,title,product) VALUES((f->>'occasion')::bigint,(f->>'blueprint')::bigint,'Legacy chair',(f->>'product')::bigint) RETURNING id INTO sid;
 UPDATE eshop.blueprints SET objects=jsonb_build_array(jsonb_build_object('type','spot','id',sid,'x',0,'y',0)) WHERE id=(f->>'blueprint')::bigint;
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,409,'legacy layout requires explicit canonical migration');
 PERFORM public.assert_eq(r->>'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED','public reader never falls back to archival geometry');
 r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((r->>'code')::int,409,'admin reader requires canonical migration too');
 DELETE FROM eshop.spots WHERE id=sid;
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq((r->>'code')::int,200,'canonical aggregate saved');
 UPDATE eshop.blueprints SET objects='[{"type":"spot","id":-999}]' WHERE id=(f->>'blueprint')::bigint;
 r:=public.get_blueprint(gen_random_uuid(),(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq((r->>'code')::int,200,'converted public reader works');
 PERFORM public.assert_eq((r->'data') ? 'objects',false,'converted reader omits legacy geometry');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,spots}'),4,'converted reader uses bindings');
 admin_r:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=(f->>'occasion')::bigint));
 PERFORM public.assert_eq((admin_r->'data') ? 'objects',false,'converted admin omits legacy geometry');
 INSERT INTO public.organizations(id,title) VALUES(3,'Selected rollout tenant') ON CONFLICT(id) DO NOTHING;
 selected:=public.blueprint_test_fixture_internal(3);
 r:=public.get_blueprint(gen_random_uuid(),(selected->>'formKey')::uuid,(selected->>'blueprint')::bigint);
 PERFORM public.assert_eq(r->>'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED','selected tenant cannot fall back');
 PERFORM public.assert_eq(to_regprocedure('public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint)') IS NULL,true,'legacy helper not callable publicly');
 PERFORM public.assert_eq(to_regprocedure('public.get_blueprint_for_edit_legacy_rollout_internal(text)') IS NULL,true,'admin helper not callable directly');
END $$;
ROLLBACK;
