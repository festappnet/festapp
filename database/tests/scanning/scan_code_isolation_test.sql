BEGIN;
DO $$
DECLARE
 fx jsonb; other_fx jsonb; oc bigint; other_oc bigint; shared_hidden bigint; other_initial_hidden bigint;
 usr uuid:=gen_random_uuid(); session jsonb; response jsonb; symbol text;
 rotated text:='ROTATED_'||gen_random_uuid(); original_other_code text;
BEGIN
 fx:=public.scanner_test_fixture(); other_fx:=public.scanner_test_fixture();
 oc:=(fx->>'occasion')::bigint;other_oc:=(other_fx->>'occasion')::bigint;
 SELECT occasion_hidden INTO other_initial_hidden FROM public.occasions WHERE id=other_oc;
 SELECT occasion_hidden INTO shared_hidden FROM public.occasions WHERE id=oc;
 SELECT ticket_symbol INTO symbol FROM eshop.tickets WHERE id=(fx#>>'{tickets,0}')::bigint;
 session:=public.open_scanner_session(fx->>'scan_code');
 PERFORM assert_eq(session#>>'{data,occasion_link}',(SELECT link FROM public.occasions WHERE id=oc),'session navigation uses its own stored occasion link');
 PERFORM assert_eq(session->>'code','200','unique scan code opens a session');
 UPDATE public.occasions SET occasion_hidden=shared_hidden WHERE id=other_oc;
 PERFORM assert_eq((SELECT count(*) FROM public.get_scanner_occasion_for_scan_code_internal(fx->>'scan_code')),0::bigint,'shared hidden row must never identify an occasion');
 PERFORM assert_eq(public.open_scanner_session(fx->>'scan_code')->>'code','401','modern scanner rejects ambiguous code');
 PERFORM assert_eq(public.get_occasion_by_scan_code(fx->>'scan_code')->>'code','401','legacy entry rejects ambiguous code');
 PERFORM assert_eq(public.get_all_tickets_for_scan(fx->>'scan_code')->>'code','401','legacy export rejects ambiguous code');
 PERFORM assert_eq(public.scan_ticket_v2(symbol,fx->>'scan_code')->>'code','401','legacy scan rejects ambiguous code');
 PERFORM assert_eq(public.scan_ticket(symbol,fx->>'scan_code')->>'code','401','original ticket scanner rejects ambiguous code');
 PERFORM assert_eq(public.update_ticket_to_used((fx#>>'{tickets,0}')::bigint,fx->>'scan_code')->>'code','401','admission rejects ambiguous code');
 BEGIN
  PERFORM public.scanner_session_internal((session#>>'{data,session_id}')::uuid,session#>>'{data,token}');
  PERFORM assert_fail('a session created before ambiguity must stop accepting the shared proof');
 EXCEPTION WHEN SQLSTATE 'PT401' THEN NULL; END;
 INSERT INTO auth.users(id,email) VALUES(usr,usr||'@scanner.invalid');
 INSERT INTO public.user_info(id,name,organization) SELECT usr,'Scanner editor',organization FROM public.occasions WHERE id=other_oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES(other_oc,usr,true,true);
 PERFORM set_config('request.jwt.claim.sub',usr::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',usr,'role','authenticated')::text,true);
 SELECT link INTO original_other_code FROM public.occasions WHERE id=other_oc;
 response:=public.update_scan_code(original_other_code,rotated);
 PERFORM assert_eq(response->>'reason','shared_scan_credential','partial split must not revive a previously shared credential');
 response:=public.get_or_create_scan_code(original_other_code,true);
 PERFORM assert_eq(response->>'reason','shared_scan_credential','server generation returns the group repair requirement without retrying candidates');
 PERFORM assert_eq((SELECT occasion_hidden FROM public.occasions WHERE id=other_oc),shared_hidden,'failed split preserves the ambiguous group');
 PERFORM assert_eq((SELECT count(*) FROM public.get_scanner_occasion_for_scan_code_internal(fx->>'scan_code')),0::bigint,'old shared credential remains unusable');
 -- Restore the independent fixture relationship to exercise normal rotation.
 UPDATE public.occasions SET occasion_hidden=other_initial_hidden WHERE id=other_oc;
 response:=public.update_scan_code(original_other_code,fx->>'scan_code');
 PERFORM assert_eq(response->>'reason','scan_code_collision','rotation cannot claim another occasion code');
 response:=public.update_scan_code(original_other_code,rotated);
 PERFORM assert_eq(response->>'code','200','independent rotation succeeds');
 PERFORM assert_eq((SELECT secret FROM public.occasions_hidden WHERE id=shared_hidden),fx->>'scan_code','rotation never changes original event secret');
 PERFORM assert_eq((SELECT id FROM public.get_scanner_occasion_for_scan_code_internal(rotated)),other_oc,'rotated code resolves only the selected event');
 response:=public.update_scan_code(original_other_code,NULL);
 PERFORM assert_eq(response->>'code','400','NULL cannot create a public proof');
 -- A unique index rejects duplicate secrets even outside the RPC boundary.
 BEGIN
  UPDATE public.occasions_hidden SET secret=fx->>'scan_code' WHERE id=(SELECT occasion_hidden FROM public.occasions WHERE id=other_oc);
  PERFORM assert_fail('database must reject duplicate secret text');
 EXCEPTION WHEN unique_violation THEN NULL; END;
 response:=public.get_or_create_scan_code(original_other_code);
 PERFORM assert_eq(response->>'scan_code',rotated,'initialization reuses the current credential');
 response:=public.get_or_create_scan_code(original_other_code,true);
 PERFORM assert_eq(response->>'code','200','server rotation succeeds');
 PERFORM assert_true((response->>'scan_code') ~ '^[A-Z0-9]{5}$','server generates the established five character format');
 PERFORM assert_true(response->>'scan_code'<>rotated,'rotation changes the credential');
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
END $$;
ROLLBACK;
