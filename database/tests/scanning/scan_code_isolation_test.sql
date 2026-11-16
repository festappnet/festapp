BEGIN;
DO $$
DECLARE fx jsonb; other_fx jsonb; oc bigint; other_oc bigint; hidden bigint;
 usr uuid:=gen_random_uuid(); session jsonb; response jsonb; link text; blocked boolean:=false;
 rotated text:='ROTATED_'||gen_random_uuid(); symbol text;
BEGIN
 fx:=public.scanner_test_fixture();other_fx:=public.scanner_test_fixture();
 oc:=(fx->>'occasion')::bigint;other_oc:=(other_fx->>'occasion')::bigint;
 SELECT occasion_hidden INTO hidden FROM public.occasions WHERE id=oc;
 BEGIN UPDATE public.occasions SET occasion_hidden=hidden WHERE id=other_oc;
 EXCEPTION WHEN unique_violation THEN blocked:=true; END;
 PERFORM assert_true(blocked,'database must reject attaching one scanner credential to two occasions');
 session:=public.open_scanner_session(fx->>'scan_code');
 PERFORM assert_eq(session->>'code','200','unique scan code opens a session');
 PERFORM assert_eq(session#>>'{data,occasion_link}',(SELECT o.link FROM public.occasions o WHERE id=oc),'navigation uses its own canonical occasion');
 SELECT ticket_symbol INTO symbol FROM eshop.tickets WHERE id=(fx#>>'{tickets,0}')::bigint;
 PERFORM assert_eq(public.scan_ticket_v2(symbol,other_fx->>'scan_code')->>'code','401','another event cannot read this ticket');
 INSERT INTO auth.users(id,email) VALUES(usr,usr||'@scanner.invalid');
 INSERT INTO public.user_info(id,name,organization) SELECT usr,'Scanner editor',organization FROM public.occasions WHERE id=other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(other_oc,usr,true,true);
 PERFORM set_config('request.jwt.claim.sub',usr::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',usr,'role','authenticated')::text,true);
 SELECT o.link INTO link FROM public.occasions o WHERE id=other_oc;
 response:=public.update_scan_code(link,fx->>'scan_code');
 PERFORM assert_eq(response->>'reason','scan_code_collision','another event code cannot be claimed');
 response:=public.update_scan_code(link,rotated);
 PERFORM assert_eq(response->>'code','200','independent rotation succeeds');
 PERFORM assert_eq((SELECT secret FROM public.occasions_hidden WHERE id=hidden),fx->>'scan_code','rotation preserves the other event');
 response:=public.get_or_create_scan_code(link);
 PERFORM assert_eq(response->>'scan_code',rotated,'initialization reuses its own credential');
 response:=public.get_or_create_scan_code(link,true);
 PERFORM assert_eq(response->>'code','200','server rotation succeeds');
 PERFORM assert_true((response->>'scan_code') ~ '^[A-Z0-9]{5}$','server keeps the established five-character format');
 PERFORM assert_eq((SELECT reason FROM public.scanner_revoked_credentials
  WHERE secret_hash=encode(extensions.digest(rotated,'sha256'),'hex')),'rotated'::text,'rotation retires its old credential');
 response:=public.update_scan_code(link,rotated);
 PERFORM assert_eq(response->>'reason','scan_code_collision','a retired credential cannot be reused');
 response:=public.update_scan_code(link,NULL);
 PERFORM assert_eq(response->>'code','400','NULL cannot create a public proof');
 blocked:=false;
 BEGIN INSERT INTO public.occasions_hidden(secret) VALUES(fx->>'scan_code');
 EXCEPTION WHEN unique_violation THEN blocked:=true; END;
 PERFORM assert_true(blocked,'database rejects duplicate secret text');
END $$;
-- Deterministically force a collision, then a fresh code, through the real RPC.
CREATE TEMP SEQUENCE forced_scan_entropy;
CREATE FUNCTION public.gen_random_bytes(integer) RETURNS bytea LANGUAGE plpgsql AS $$
BEGIN
 IF $1=16 THEN
   RETURN decode(repeat(CASE WHEN nextval('forced_scan_entropy')=1 THEN '00' ELSE '01' END,16),'hex');
 END IF;
 RETURN extensions.gen_random_bytes($1);
END $$;
DISCARD PLANS;
DO $$
DECLARE fx jsonb; usr uuid:=gen_random_uuid(); link text; response jsonb;
BEGIN
 fx:=public.scanner_test_fixture();
 INSERT INTO public.occasions_hidden(secret) VALUES('AAAAA');
 INSERT INTO auth.users(id,email) VALUES(usr,usr||'@scanner.invalid');
 INSERT INTO public.user_info(id,name,organization) SELECT usr,'Scanner editor',organization FROM public.occasions WHERE id=(fx->>'occasion')::bigint;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES((fx->>'occasion')::bigint,usr,true);
 PERFORM set_config('request.jwt.claim.sub',usr::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',usr,'role','authenticated')::text,true);
 SELECT o.link INTO link FROM public.occasions o WHERE id=(fx->>'occasion')::bigint;
 response:=public.get_or_create_scan_code(link,true);
 PERFORM assert_eq(response->>'scan_code','BBBBB','a colliding candidate is retried before returning a fresh code');
 PERFORM assert_eq(currval('forced_scan_entropy'),2::bigint,'collision retry consumed two candidates');
 INSERT INTO public.scanner_revoked_credentials(secret_hash,reason)
 VALUES(encode(extensions.digest('ZZZZZ','sha256'),'hex'),'historical_shared');
 response:=public.update_scan_code(link,'ZZZZZ');
 PERFORM assert_eq(response->>'reason','scan_code_collision','a retired value cannot be recycled even without a hidden row');
 PERFORM assert_false(has_function_privilege('anon','public.generate_scanner_access_code_internal()','EXECUTE'),'sampler is not an anonymous RPC');
 PERFORM assert_false(has_function_privilege('authenticated','public.generate_scanner_access_code_internal()','EXECUTE'),'clients use the authorized allocation boundary');
 PERFORM assert_false(has_table_privilege('anon','public.scanner_revoked_credentials','SELECT'),'anonymous callers cannot enumerate revoked credentials');
 PERFORM assert_false(has_table_privilege('authenticated','public.scanner_revoked_credentials','SELECT'),'editors cannot enumerate revoked credentials');
END $$;
ROLLBACK;
