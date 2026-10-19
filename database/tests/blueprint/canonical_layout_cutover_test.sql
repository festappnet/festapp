BEGIN;
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; actor uuid; response jsonb; source jsonb; before_count bigint; source_unit bigint;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=f.occasion AND is_editor ORDER BY "user" LIMIT 1;
 SELECT unit INTO source_unit FROM public.occasions WHERE id=f.occasion;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- Poisoned archival fields cannot influence either canonical reader.
 UPDATE eshop.blueprints SET objects='[{"type":"spot","id":-999}]',groups='[{"legacy":true}]',background_svg='archival-only' WHERE id=f.blueprint;
 response:=public.get_blueprint(gen_random_uuid(),f.key,f.blueprint);
 IF response#>'{data,layout}' IS NULL OR (response->'data') ?| ARRAY['objects','groups','configuration','background_svg'] THEN RAISE EXCEPTION 'public reader retained legacy geometry'; END IF;
 IF jsonb_array_length(response#>'{data,spots}')<>(SELECT count(*) FROM eshop.blueprint_seat_bindings WHERE blueprint=f.blueprint) THEN RAISE EXCEPTION 'public spots not binding-owned'; END IF;
 response:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=f.occasion));
 IF response#>'{data,layout}' IS NULL OR (response->'data') ?| ARRAY['objects','groups','configuration','background_svg'] THEN RAISE EXCEPTION 'admin reader retained legacy geometry'; END IF;
 SELECT item INTO source FROM jsonb_array_elements(public.get_occasion_setup_sources(source_unit)) item WHERE (item#>>'{occasion,id}')::bigint=f.occasion;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(source->'blueprints') item WHERE item ?| ARRAY['objects','groups','configuration','background_svg']) THEN RAISE EXCEPTION 'setup source retained legacy geometry'; END IF;
 response:=public.update_blueprint_client_sync_v1(jsonb_build_object('id',f.blueprint,'occasion',f.occasion,'objects','[]'::jsonb),gen_random_uuid());
 IF response#>>'{data,reason}'<>'BLUEPRINT_LAYOUT_REQUIRED' THEN RAISE EXCEPTION 'legacy save route accepted %',response; END IF;
 IF to_regprocedure('public.update_blueprint(jsonb)') IS NOT NULL OR to_regprocedure('public.update_blueprint_internal_v1(jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'old write RPC remains registered'; END IF;
 -- Unconverted data may only enter the explicit offline migration boundary.
 UPDATE eshop.blueprints SET layout=NULL WHERE id=f.blueprint;
 response:=public.get_blueprint(gen_random_uuid(),f.key,f.blueprint);
 IF response->>'reason'<>'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED' THEN RAISE EXCEPTION 'unconverted public reader accepted'; END IF;
 SELECT count(*) INTO before_count FROM public.occasions;
 BEGIN PERFORM public.duplicate_occasion_internal_v1(f.occasion,source_unit,'cs');RAISE EXCEPTION 'unconverted copy accepted';
 EXCEPTION WHEN check_violation THEN IF SQLERRM<>'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED' THEN RAISE; END IF; END;
 IF (SELECT count(*) FROM public.occasions)<>before_count THEN RAISE EXCEPTION 'unconverted copy left new event'; END IF;
 RAISE NOTICE 'canonical read/save/setup-source/copy registry cutover and archival poison/migration gate PASS';
END $$;
ROLLBACK;
