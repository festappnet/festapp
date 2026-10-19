BEGIN;
SELECT set_config('festapp.fixture_form',:'fixture_form',true);
DO $$
DECLARE f public.forms; actor uuid; oid bigint; response jsonb; visible jsonb;
BEGIN
 IF (SELECT project FROM festapp_test_support.disposable_environment WHERE singleton) IS DISTINCT FROM 'festapp-blueprint-b-e2e-20261019' THEN RAISE EXCEPTION 'owned fixture required'; END IF;
 SELECT * INTO f FROM public.forms WHERE id=current_setting('festapp.fixture_form')::bigint;
 SELECT "user" INTO actor FROM public.occasion_users WHERE occasion=f.occasion AND is_editor ORDER BY "user" LIMIT 1;
 SELECT opt."order" INTO oid FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=opt.ticket WHERE s.blueprint=f.blueprint AND t.state='used' LIMIT 1;
 UPDATE eshop.orders SET note_hidden='Synthetic private order projection proof' WHERE id=oid;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 response:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=f.occasion));
 SELECT item INTO visible FROM jsonb_array_elements(response#>'{data,orders}') item WHERE (item->>'id')::bigint=oid;
 IF visible#>>'{data,note_hidden}' IS DISTINCT FROM 'Synthetic private order projection proof' THEN RAISE EXCEPTION 'authorized inspector missing private order note'; END IF;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 response:=public.get_blueprint(gen_random_uuid(),f.key,f.blueprint);
 IF response->>'code'<>'200' OR jsonb_path_exists(response,'$.**.note_hidden') OR (response->'data') ? 'orders' THEN RAISE EXCEPTION 'public buyer projection leaked private order metadata'; END IF;
 response:=public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=f.occasion));
 IF response->>'code'='200' OR jsonb_path_exists(response,'$.**.note_hidden') THEN RAISE EXCEPTION 'anonymous admin reader leaked private order note'; END IF;
 RAISE NOTICE 'authorized private order note projection and anonymous public/admin privacy PASS';
END $$;
ROLLBACK;
