-- Disposable local transaction only. Never replays or discards real deliveries.
DO $$
DECLARE token text:=repeat('due-queue-fixture-',4); org bigint; result jsonb;
BEGIN
 SELECT id INTO org FROM public.organizations ORDER BY id LIMIT 1;
 IF org IS NULL THEN RAISE EXCEPTION 'local organization fixture required'; END IF;
 UPDATE public.email_messages SET workflow_state='cancelled';
 INSERT INTO public.festapp_monitoring_credentials(token_hash,expires_at)
 VALUES(encode(extensions.digest(token,'sha256'),'hex'),now()+interval '1 day');
 INSERT INTO public.email_messages(id,created_at,target_time,code,organization,message_kind,dedupe_key,input_hash,recipient,workflow_state)
 VALUES(-96535,now()-interval '2 days',now()+interval '1 day','TEST',org,'custom','due-queue-fixture',repeat('a',64),'test@example.invalid','pending');
 result:=public.get_festapp_monitoring_health_v1(token);
 IF result->'alerts' ? 'abuse_ordinary_backlog' THEN RAISE EXCEPTION 'future scheduled mail reported as overdue'; END IF;
 UPDATE public.email_messages SET target_time=now()-interval '1 minute' WHERE id=-96535;
 result:=public.get_festapp_monitoring_health_v1(token);
 IF result->'alerts' ? 'abuse_ordinary_backlog' THEN RAISE EXCEPTION 'newly due scheduled mail reported as overdue'; END IF;
 UPDATE public.email_messages SET workflow_state='unknown',target_time=created_at WHERE id=-96535;
 result:=public.get_festapp_monitoring_health_v1(token);
 IF result->'alerts' ? 'abuse_ordinary_backlog' THEN RAISE EXCEPTION 'historical uncertain send reported as runnable backlog'; END IF;
 UPDATE public.email_messages SET workflow_state='pending',target_time=now()-interval '2 hours' WHERE id=-96535;
 result:=public.get_festapp_monitoring_health_v1(token);
 IF NOT(result->'alerts' ? 'abuse_ordinary_backlog') THEN RAISE EXCEPTION 'real overdue queue was hidden'; END IF;
 result:=public.abuse_health_internal_v1();
 IF (result#>>'{queue,ordinary,pendingCount}')::integer<>1 THEN RAISE EXCEPTION 'operator pending count changed'; END IF;
 IF result#>>'{queue,ordinary,oldestDueAt}' IS NULL THEN RAISE EXCEPTION 'due evidence missing'; END IF;
END $$;
