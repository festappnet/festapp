-- test-setup: database/tests/blueprint/fixtures.sql
-- B fixture and assertion helpers must be installed by the isolated harness.
BEGIN;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE singleton) THEN RAISE EXCEPTION 'disposable blueprint fixture database required'; END IF; END $$;
DO $$
DECLARE f jsonb; r jsonb; payload jsonb; hold uuid; sid bigint; foreign_bp bigint; scenario text; before_state jsonb; after_state jsonb; cmd uuid; replay jsonb; bank bigint; client uuid; foreign_occ bigint; foreign_form uuid; required_field bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','applied','fixture layout saved');
 INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies) VALUES('Integrity fixture','123/0100','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 UPDATE public.forms SET bank_account=bank WHERE id=(f->>'form')::bigint;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) SELECT unit,bank,1 FROM public.occasions WHERE id=(f->>'occasion')::bigint;
 INSERT INTO eshop.blueprints(occasion,organization,title) SELECT occasion,organization,'Foreign blueprint' FROM eshop.blueprints WHERE id=(f->>'blueprint')::bigint RETURNING id INTO foreign_bp;
 INSERT INTO public.forms(occasion,blueprint,title,is_open,type) VALUES((f->>'occasion')::bigint,foreign_bp,'Newer unrelated blueprint form',true,'ticket') RETURNING key INTO foreign_form;
 SELECT spot INTO sid FROM eshop.blueprint_seat_bindings WHERE blueprint=(f->>'blueprint')::bigint ORDER BY spot LIMIT 1;
 hold:=gen_random_uuid();
 UPDATE eshop.blueprints SET data='{"note_hidden":"private","email":"private@example.invalid","secret":"private"}' WHERE id=(f->>'blueprint')::bigint;
 UPDATE eshop.spots SET secret=hold,secret_expiration_time=clock_timestamp()+interval '10 minutes' WHERE id=sid;
 r:=public.get_blueprint(hold,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(r#>'{data,data}','{}'::jsonb,'public metadata allowlist');
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,products}'),1,'shared product returned exactly once');
 PERFORM public.assert_true(r#>>'{data,expiresAt}' IS NOT NULL,'own authoritative expiry restored');
 r:=public.confirm_blueprint_order_change_internal_v1(ARRAY[sid],jsonb_build_object('email','editor@example.invalid'));
 PERFORM public.assert_true((r->>'success')::boolean IS FALSE,'editor cannot silently erase active foreign hold');
 PERFORM public.assert_eq((SELECT secret FROM eshop.spots WHERE id=sid),hold,'foreign active hold preserved');
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) SELECT organization,unit,'Foreign occasion',gen_random_uuid()::text,now(),now()+interval '1 day' FROM public.occasions WHERE id=(f->>'occasion')::bigint RETURNING id INTO foreign_occ;
 FOREACH scenario IN ARRAY ARRAY['absent','null','wrong','expired','foreign_blueprint','foreign_occasion','closed','scheduled','duplicate','valid'] LOOP
  hold:=gen_random_uuid();cmd:=gen_random_uuid();client:=gen_random_uuid();
  UPDATE public.forms SET is_open=true,data='{}' WHERE id=(f->>'form')::bigint;
  UPDATE eshop.spots SET occasion=(f->>'occasion')::bigint,blueprint=(f->>'blueprint')::bigint,secret=hold,secret_expiration_time=clock_timestamp()+interval '10 minutes' WHERE id=sid;
  payload:=jsonb_build_object('form',f->'formKey','email','blueprint-integrity-'||(f->>'occasion')||'@example.invalid','secret',hold,'ticket',jsonb_build_array(jsonb_build_object('spot',sid)));
  CASE scenario
   WHEN 'absent' THEN payload:=payload-'secret'; UPDATE eshop.spots SET secret=NULL WHERE id=sid;
   WHEN 'null' THEN payload:=jsonb_set(payload,'{secret}','null'); UPDATE eshop.spots SET secret=NULL WHERE id=sid;
   WHEN 'wrong' THEN payload:=jsonb_set(payload,'{secret}',to_jsonb(gen_random_uuid()));
   WHEN 'expired' THEN UPDATE eshop.spots SET secret_expiration_time=clock_timestamp()-interval '1 second' WHERE id=sid;
   WHEN 'foreign_occasion' THEN UPDATE eshop.spots SET occasion=foreign_occ WHERE id=sid;
   WHEN 'foreign_blueprint' THEN UPDATE eshop.spots SET blueprint=foreign_bp WHERE id=sid;
   WHEN 'closed' THEN UPDATE public.forms SET is_open=false WHERE id=(f->>'form')::bigint;
   WHEN 'scheduled' THEN UPDATE public.forms SET data=jsonb_build_object('start_time',clock_timestamp()+interval '1 day') WHERE id=(f->>'form')::bigint;
   WHEN 'duplicate' THEN payload:=jsonb_set(payload,'{ticket}',(payload->'ticket')||(payload->'ticket'));
   ELSE NULL;
  END CASE;
  SELECT jsonb_build_array((SELECT count(*) FROM eshop.orders),(SELECT count(*) FROM eshop.tickets),(SELECT count(*) FROM eshop.payment_info),(SELECT count(*) FROM eshop.order_product_ticket),(SELECT count(*) FROM public.email_messages)) INTO before_state;
  PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
  EXECUTE 'SET LOCAL ROLE anon';
  r:=public.create_ticket_order_client_sync_v1(payload,cmd,client);
  EXECUTE 'RESET ROLE';
  SELECT jsonb_build_array((SELECT count(*) FROM eshop.orders),(SELECT count(*) FROM eshop.tickets),(SELECT count(*) FROM eshop.payment_info),(SELECT count(*) FROM eshop.order_product_ticket),(SELECT count(*) FROM public.email_messages)) INTO after_state;
  IF scenario='valid' THEN
   PERFORM public.assert_eq((r->>'code')::int,200,'valid anonymous held order');
   EXECUTE 'SET LOCAL ROLE anon';
   replay:=public.create_ticket_order_client_sync_v1(payload,cmd,client);
   PERFORM public.assert_eq(replay#>>'{data,order,id}',r#>>'{data,order,id}','same command replay identity');
   replay:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),client);
   EXECUTE 'RESET ROLE';
   PERFORM public.assert_true(coalesce((replay->>'code')::int,500)<>200,'new command sold seat rejected');
  ELSE
   PERFORM public.assert_true(coalesce((r->>'code')::int,500)<>200,'rejected '||scenario||': '||r);
   PERFORM public.assert_eq(after_state,before_state,'no side effects '||scenario);
  END IF;
 END LOOP;
 INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,title) VALUES((f->>'form')::bigint,'name',true,true,false,'Required ticket name') RETURNING id INTO required_field;
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 r:=public.replace_blueprint_order_client_sync_v1(ARRAY[sid],jsonb_build_object('email','editor-'||(f->>'occasion')||'@example.invalid','form_key',foreign_form),gen_random_uuid());
 PERFORM public.assert_eq(r->>'status','rejected','stale or foreign admin form key rejected');
 r:=public.replace_blueprint_order_client_sync_v1(ARRAY[sid],jsonb_build_object('email','editor-'||(f->>'occasion')||'@example.invalid','form',foreign_form,'ticket','[]'::jsonb,'ticket_fields',jsonb_build_object(sid::text,jsonb_build_array(jsonb_build_object(required_field::text,'Guest')))),gen_random_uuid());
 EXECUTE 'RESET ROLE';
 PERFORM public.assert_eq(r->>'status','applied','authenticated admin replace without public hold and required ticket fields');
 PERFORM public.assert_eq((r#>>'{data,order,form,id}')::bigint,(f->>'form')::bigint,'admin payload cannot override selected blueprint form');
END $$;
ROLLBACK;
