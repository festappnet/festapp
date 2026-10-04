BEGIN;
DO $$ DECLARE before_count bigint; BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 PERFORM set_config('festapp.email_wake','',true);
 UPDATE public.email_messages SET target_time=now()+interval '1 day'
 WHERE workflow_state IN ('pending','retry_wait');
 UPDATE public.email_capacity SET paused=false,worker_url='http://127.0.0.1:9/idle-quota-test',quota_at=now() WHERE singleton;
 SELECT count(*) INTO before_count FROM net.http_request_queue;
 PERFORM public.wake_email_worker();
 IF (SELECT count(*) FROM net.http_request_queue)<>before_count THEN RAISE EXCEPTION 'fresh idle queue should not wake'; END IF;
 UPDATE public.email_capacity SET quota_at=now()-interval '6 minutes' WHERE singleton;
 PERFORM public.wake_email_worker();
 IF (SELECT count(*) FROM net.http_request_queue)<>before_count+1 THEN RAISE EXCEPTION 'stale idle quota requires one worker wake'; END IF;
 PERFORM public.wake_email_worker();
 IF (SELECT count(*) FROM net.http_request_queue)<>before_count+1 THEN RAISE EXCEPTION 'idle quota wake must coalesce in transaction'; END IF;
END $$;
ROLLBACK;
