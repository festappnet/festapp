DO $$ BEGIN
 IF (SELECT count(*) FROM public.email_messages WHERE id BETWEEN 98001 AND 98005)<>5 THEN RAISE EXCEPTION 'legacy IDs lost';END IF;
 IF (SELECT workflow_state FROM public.email_messages WHERE id=98001)<>'pending' THEN RAISE EXCEPTION 'pending lost';END IF;
 IF (SELECT workflow_state FROM public.email_messages WHERE id=98002)<>'blocked' THEN RAISE EXCEPTION 'invoice gate lost';END IF;
 IF (SELECT count(*) FROM public.email_messages WHERE id BETWEEN 98003 AND 98005 AND workflow_state='unknown')<>3 THEN RAISE EXCEPTION 'ambiguous SMTP automatically retryable';END IF;
 IF (SELECT count(*) FROM public.email_messages WHERE order_id=98002 AND message_kind='order_tickets' AND workflow_state='unknown')<>1 THEN RAISE EXCEPTION 'paid candidate missing or duplicated';END IF;
 IF EXISTS(SELECT 1 FROM public.email_messages WHERE delivered_at IS NOT NULL OR accepted_at IS NOT NULL) THEN RAISE EXCEPTION 'invented legacy delivery';END IF;
 IF (SELECT count(*) FROM public.log_emails WHERE occasion=98001)<>1 THEN RAISE EXCEPTION 'legacy audit changed';END IF;
 IF NOT (SELECT paused FROM public.email_capacity) THEN RAISE EXCEPTION 'cutover unexpectedly sends';END IF;
 IF to_regclass('public.queue_emails') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND position('queue_emails' in prosrc)>0) THEN RAISE EXCEPTION 'legacy queue remains';END IF;
END $$;
