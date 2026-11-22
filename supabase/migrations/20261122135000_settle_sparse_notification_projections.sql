-- Settle notification projections when deleted deliveries leave gaps below the allocator high-water mark.

-- SOURCE: notification_center/prepared_worker.sql
CREATE OR REPLACE FUNCTION public.prepare_notification_center(p_limit integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE s public.notification_center_projection_scopes; personal public.notification_center_user_state;
 e public.notification_center_events; d public.notification_center_deliveries; item record; job record;
 privacy jsonb; keys text[]; maximum uuid; processed integer:=0; n integer; budget integer:=greatest(1,least(coalesce(p_limit,500),100));
 error_code text;deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; current_at timestamptz; previous_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 FOR s IN SELECT * FROM public.notification_center_projection_scopes WHERE next_check_at<=clock_timestamp() AND NOT quarantined
  ORDER BY work_requested DESC,next_check_at,organization,recipient LIMIT 8 FOR UPDATE SKIP LOCKED LOOP
  BEGIN
   e:=NULL;
   budget:=greatest(1,least(coalesce(p_limit,500),100)-processed);
   SELECT * INTO personal FROM public.notification_center_user_state WHERE organization=s.organization AND recipient=s.recipient FOR UPDATE SKIP LOCKED;
   IF NOT FOUND THEN
    UPDATE public.notification_center_projection_scopes SET next_check_at=clock_timestamp()+interval '100 milliseconds' WHERE organization=s.organization AND recipient=s.recipient;
    CONTINUE;
   END IF;
   current_at:=clock_timestamp();privacy:=public.notification_center_prepared_privacy(s.organization);
   IF NOT s.delivery_initialized THEN
    SELECT count(*) INTO n FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
     WHERE r.recipient=s.recipient AND ev.organization=s.organization AND r.processed_revision<r.eligible_revision;
    UPDATE public.notification_center_projection_scopes SET pending_delivery=n,delivery_initialized=true WHERE organization=s.organization AND recipient=s.recipient;
   END IF;
   IF s.phase IN ('backfill','ready') AND s.phase='backfill' AND s.build_revision<>s.revision THEN
    UPDATE public.notification_center_projection_scopes SET phase='clear_members',build_revision=s.revision WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+1;CONTINUE;
   END IF;
   IF s.phase='clear_members' THEN
    DELETE FROM public.notification_center_view_members WHERE (organization,recipient,event_id) IN(
     SELECT organization,recipient,event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient ORDER BY event_id LIMIT budget);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<budget THEN UPDATE public.notification_center_projection_scopes SET phase='clear_summaries' WHERE organization=s.organization AND recipient=s.recipient; END IF;
    processed:=processed+greatest(n,1);
   ELSIF s.phase='clear_summaries' THEN
    DELETE FROM public.notification_center_batch_summaries WHERE (organization,recipient,id) IN(
     SELECT organization,recipient,id FROM public.notification_center_batch_summaries WHERE organization=s.organization AND recipient=s.recipient ORDER BY id LIMIT budget);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<budget THEN
     UPDATE public.notification_center_projection_scopes SET phase='backfill',cursor_sequence=0,prepared_sequence=0,
      build_revision=s.revision,privacy=privacy,pending_events=0,privacy_pending=false,privacy_keys='{}',privacy_cursor=NULL
      WHERE organization=s.organization AND recipient=s.recipient;
    END IF;
    processed:=processed+greatest(n,1);
   ELSIF s.phase='backfill' THEN
    n:=0;
    FOR d IN SELECT * FROM public.notification_center_deliveries WHERE organization=s.organization AND recipient=s.recipient
     AND sequence>s.cursor_sequence ORDER BY sequence LIMIT budget LOOP
     SELECT * INTO e FROM public.notification_center_events WHERE id=d.event_id;
     PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);
     UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
     s.cursor_sequence:=d.sequence;n:=n+1;
    END LOOP;
    -- Deletions leave gaps below the locked allocator high-water mark.
    IF n<budget THEN s.cursor_sequence:=personal.last_delivery_sequence; END IF;
    UPDATE public.notification_center_projection_scopes SET cursor_sequence=s.cursor_sequence,prepared_sequence=s.cursor_sequence,
     phase=CASE WHEN s.cursor_sequence>=personal.last_delivery_sequence THEN 'ready' ELSE 'backfill' END,
     applied_read_revision=CASE WHEN pending_groups=0 THEN personal.view_read_revision ELSE applied_read_revision END,
     last_ready_at=CASE WHEN s.cursor_sequence>=personal.last_delivery_sequence THEN clock_timestamp() ELSE last_ready_at END
     WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+greatest(n,1);
   ELSE
    -- Hidden identity/email changes are detected from a bounded live subject
    -- snapshot. Every contribution is evaluated against an explicit snapshot,
    -- so a transient hide/unhide cannot contaminate a different generation.
    IF s.privacy<>privacy OR s.privacy_pending THEN
     WITH before_keys AS(SELECT key FROM public.notification_center_prepared_privacy_keys(s.privacy) key),
     after_keys AS(SELECT key FROM public.notification_center_prepared_privacy_keys(privacy) key),
     delta AS(SELECT coalesce(b.key,a.key) key FROM before_keys b FULL JOIN after_keys a USING(key) WHERE b.key IS NULL OR a.key IS NULL)
     SELECT array_agg(DISTINCT key) FILTER(WHERE key IS NOT NULL) INTO keys FROM(
      SELECT unnest(s.privacy_keys) key UNION SELECT key FROM delta) q;
     IF NOT s.privacy_pending OR s.repair_privacy<>privacy THEN s.privacy_cursor:=NULL; END IF;
     n:=0;maximum:=s.privacy_cursor;
     FOR item IN SELECT DISTINCT v.event_id FROM unnest(coalesce(keys,'{}')) key
      CROSS JOIN LATERAL(SELECT event_id FROM public.notification_center_member_subjects m
       WHERE m.organization=s.organization AND m.recipient=s.recipient AND m.subject=key
        AND (s.privacy_cursor IS NULL OR m.event_id>s.privacy_cursor) ORDER BY event_id LIMIT budget) v ORDER BY v.event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=item.event_id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      IF e.id IS NOT NULL AND d.event_id IS NOT NULL THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,privacy); END IF;
      maximum:=item.event_id;n:=n+1;
     END LOOP;
     UPDATE public.notification_center_projection_scopes SET privacy_pending=n>=budget,
      privacy=CASE WHEN n<budget THEN privacy ELSE notification_center_projection_scopes.privacy END,
      repair_privacy=privacy,privacy_cursor=CASE WHEN n>=budget THEN maximum END,
      privacy_keys=CASE WHEN n>=budget THEN coalesce(keys,'{}') ELSE '{}'::text[] END,
      revision=revision+CASE WHEN NOT s.privacy_pending THEN 1 ELSE 0 END
      WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+greatest(n,1);
    ELSIF s.pending_events>0 THEN
     n:=0;
     FOR item IN SELECT r.event_id FROM public.notification_center_recipients r JOIN public.notification_center_events ev ON ev.id=r.event_id
      WHERE r.recipient=s.recipient AND ev.organization=s.organization AND r.view_required_revision>r.view_applied_revision
      ORDER BY r.event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id FOR UPDATE SKIP LOCKED;
      IF NOT FOUND THEN CONTINUE; END IF;
      PERFORM 1 FROM public.notification_center_recipients WHERE event_id=e.id AND recipient=s.recipient FOR UPDATE SKIP LOCKED;
      IF NOT FOUND THEN CONTINUE; END IF;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      IF FOUND THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy); END IF;
      UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
      n:=n+1;
     END LOOP;
     UPDATE public.notification_center_projection_scopes SET pending_events=greatest(0,pending_events-n) WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+n;
    ELSIF s.pending_groups>0 THEN
     SELECT * INTO job FROM public.notification_center_group_repairs WHERE organization=s.organization AND recipient=s.recipient ORDER BY group_key LIMIT 1 FOR UPDATE SKIP LOCKED;
     IF FOUND THEN
      n:=0;maximum:=job.cursor;
      FOR item IN SELECT event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key
       AND (job.cursor IS NULL OR event_id>job.cursor) ORDER BY event_id LIMIT budget LOOP
       SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
       SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=item.event_id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
       IF e.id IS NOT NULL AND d.event_id IS NOT NULL THEN PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy); END IF;
       maximum:=item.event_id;n:=n+1;
      END LOOP;
      IF n<budget THEN
       DELETE FROM public.notification_center_group_repairs WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key;
       UPDATE public.notification_center_projection_scopes SET pending_groups=greatest(0,pending_groups-1),
        applied_read_revision=CASE WHEN pending_groups<=1 THEN personal.view_read_revision ELSE applied_read_revision END WHERE organization=s.organization AND recipient=s.recipient;
      ELSE UPDATE public.notification_center_group_repairs SET cursor=maximum WHERE organization=s.organization AND recipient=s.recipient AND group_key=job.group_key; END IF;
      processed:=processed+greatest(n,1);
     END IF;
    ELSIF s.prepared_sequence<personal.last_delivery_sequence THEN
     n:=0;
     FOR d IN SELECT * FROM public.notification_center_deliveries WHERE organization=s.organization AND recipient=s.recipient AND sequence>s.prepared_sequence ORDER BY sequence LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=d.event_id;
      PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);
      UPDATE public.notification_center_recipients SET view_applied_revision=e.view_revision,view_required_revision=e.view_revision WHERE event_id=e.id AND recipient=s.recipient;
      s.prepared_sequence:=d.sequence;n:=n+1;
     END LOOP;
     IF n<budget THEN s.prepared_sequence:=personal.last_delivery_sequence; END IF;
     UPDATE public.notification_center_projection_scopes SET prepared_sequence=s.prepared_sequence WHERE organization=s.organization AND recipient=s.recipient;
     processed:=processed+greatest(n,1);
    ELSE
     n:=0;
     FOR item IN SELECT event_id FROM public.notification_center_view_members WHERE organization=s.organization AND recipient=s.recipient AND eligible AND expires_at<current_at ORDER BY expires_at,event_id LIMIT budget LOOP
      SELECT * INTO e FROM public.notification_center_events WHERE id=item.event_id;
      SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=e.id AND recipient=s.recipient ORDER BY sequence DESC LIMIT 1;
      PERFORM public.notification_center_prepared_apply(e,d,current_at,s.privacy);n:=n+1;
     END LOOP;
     processed:=processed+n;
    END IF;
   END IF;
   SELECT expires_at INTO s.next_expiry FROM public.notification_center_view_members
    WHERE organization=s.organization AND recipient=s.recipient AND eligible AND expires_at IS NOT NULL ORDER BY expires_at,event_id LIMIT 1;
   UPDATE public.notification_center_projection_scopes SET retry_count=0,last_error_code=NULL,failed_event=NULL,
    work_requested=phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false),
    next_expiry=s.next_expiry,
    requested_at=CASE WHEN phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false)
     THEN coalesce(requested_at,current_at) END,
    next_check_at=CASE WHEN phase<>'ready' OR pending_delivery>0 OR pending_events>0 OR pending_groups>0 OR privacy_pending OR prepared_sequence<personal.last_delivery_sequence OR coalesce(s.next_expiry<current_at,false)
     THEN clock_timestamp() ELSE coalesce(s.next_expiry,'infinity'::timestamptz) END
    WHERE organization=s.organization AND recipient=s.recipient;
  EXCEPTION WHEN lock_not_available THEN NULL;
   WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
    UPDATE public.notification_center_projection_scopes SET retry_count=retry_count+1,last_error_code=error_code,failed_event=e.id,
     quarantined=retry_count>=4,next_check_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(retry_count,8))*(0.9+random()*0.2)))
     WHERE organization=s.organization AND recipient=s.recipient;
    processed:=processed+1;
  END;
  EXIT WHEN processed>=budget OR clock_timestamp()>=deadline;
 END LOOP;
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN processed;
EXCEPTION WHEN lock_not_available THEN
 -- Relation locks (for example concurrent maintenance) can precede row-level
 -- SKIP LOCKED. This entire call rolls back; recovery retries durable work.
 PERFORM set_config('lock_timeout',previous_timeout,true);
 RETURN 0;
END $$;
