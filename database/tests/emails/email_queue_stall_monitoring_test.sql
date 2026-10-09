-- Disposable local database only; the enclosing harness always rolls back.
DO $$
DECLARE token text:=repeat('stall-test-capability-',3); org bigint; v jsonb; state text;
BEGIN
 SELECT id INTO org FROM public.organizations ORDER BY id LIMIT 1;
 IF org IS NULL THEN RAISE EXCEPTION 'local organization fixture required'; END IF;
 INSERT INTO public.festapp_monitoring_credentials(token_hash,expires_at)
 VALUES(encode(extensions.digest(token,'sha256'),'hex'),now()+interval '1 day');
 -- Isolate health observations from unrelated local queue fixtures.
 UPDATE public.email_messages SET workflow_state='cancelled';
 INSERT INTO public.email_messages(id,created_at,target_time,code,organization,message_kind,dedupe_key,input_hash,recipient)
 VALUES(-96534,now()-interval '2 days',now()-interval '1 minute','TEST',org,'custom','stall-fixture',repeat('a',64),'test@example.invalid');
 v:=public.get_festapp_monitoring_health_v1(token);
 IF v->'alerts' ? 'email_backlog' THEN RAISE EXCEPTION 'newly due scheduled mail falsely overdue'; END IF;
 UPDATE public.email_messages SET target_time=now()-interval '6 minutes' WHERE id=-96534;
 FOREACH state IN ARRAY ARRAY['pending','retry_wait','preparing','sending'] LOOP
  UPDATE public.email_messages SET workflow_state=state WHERE id=-96534;
  v:=public.get_festapp_monitoring_health_v1(token);
  IF NOT(v->'alerts' ? 'email_backlog') THEN RAISE EXCEPTION 'stalled % message not detected',state; END IF;
 END LOOP;
 UPDATE public.email_messages SET workflow_state='accepted' WHERE id=-96534;
 v:=public.get_festapp_monitoring_health_v1(token);
 IF v->'alerts' ? 'email_backlog' THEN RAISE EXCEPTION 'accepted mail still reported stalled'; END IF;
 IF has_function_privilege('authenticated','public.get_festapp_monitoring_health_v1(text)','EXECUTE') THEN RAISE EXCEPTION 'authenticated gained capability RPC access'; END IF;
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN
  PERFORM public.get_festapp_monitoring_health_v1(repeat('invalid-',8));
  RAISE EXCEPTION 'invalid monitoring capability accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF public.get_festapp_monitoring_health_v1(repeat('stall-test-capability-',3))->'alerts' IS NULL THEN RAISE EXCEPTION 'valid capability unavailable'; END IF;
END $$;
RESET ROLE;
