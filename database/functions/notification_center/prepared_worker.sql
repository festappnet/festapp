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
REVOKE ALL ON FUNCTION public.prepare_notification_center(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_notification_center(integer) TO service_role;
CREATE OR REPLACE FUNCTION public.prepare_notification_center_views(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
#variable_conflict use_variable
DECLARE work record; s public.notification_center_projection_scopes; v public.notification_center_views;
 r public.notification_center_view_rows; e public.notification_center_events; d public.notification_center_deliveries; m public.notification_center_view_members;
 privacy jsonb; privacy_key text; read_rev bigint; last_id uuid; ids uuid[]; b record;
 n integer; processed integer:=0; budget integer:=greatest(1,least(coalesce(p_limit,100),100));
 error_code text;deadline timestamptz:=clock_timestamp()+interval '250 milliseconds'; previous_timeout text:=current_setting('lock_timeout');
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 PERFORM set_config('lock_timeout','5ms',true);
 DELETE FROM public.notification_center_views WHERE token IN(SELECT token FROM public.notification_center_views WHERE expires_at<=clock_timestamp() ORDER BY expires_at LIMIT 100);
 FOR work IN SELECT vr.token,vr.position FROM public.notification_center_view_rows vr JOIN public.notification_center_views vw ON vw.token=vr.token
  JOIN public.notification_center_projection_scopes ps ON ps.organization=vw.organization AND ps.recipient=vw.recipient
  JOIN public.notification_center_user_state us ON us.organization=vw.organization AND us.recipient=vw.recipient
  WHERE vw.expires_at>clock_timestamp() AND (vr.next_attempt_at<=clock_timestamp() OR vr.repair_revision IS DISTINCT FROM ps.revision)
   AND (NOT vr.quarantined OR vr.repair_revision IS DISTINCT FROM ps.revision) AND ps.phase='ready' AND ps.pending_events=0 AND ps.pending_groups=0 AND NOT ps.privacy_pending
   AND (vr.state='preparing' OR vr.revision<>ps.revision OR vr.read_revision<>us.view_read_revision
    OR vr.privacy_key<>md5(public.notification_center_prepared_privacy(vw.organization)::text))
  ORDER BY vw.created_at,vr.position LIMIT 8 FOR UPDATE OF vr SKIP LOCKED LOOP
  BEGIN
   budget:=greatest(1,least(coalesce(p_limit,100),100)-processed);
   SELECT * INTO v FROM public.notification_center_views WHERE token=work.token;
   SELECT * INTO s FROM public.notification_center_projection_scopes WHERE organization=v.organization AND recipient=v.recipient FOR SHARE NOWAIT;
   SELECT * INTO r FROM public.notification_center_view_rows WHERE token=work.token AND position=work.position;
   SELECT view_read_revision INTO read_rev FROM public.notification_center_user_state WHERE organization=v.organization AND recipient=v.recipient;
   privacy:=public.notification_center_prepared_privacy(v.organization);privacy_key:=md5(privacy::text);
   IF r.repair_revision IS DISTINCT FROM s.revision OR r.repair_read_revision IS DISTINCT FROM read_rev OR r.repair_privacy_key IS DISTINCT FROM privacy_key THEN
    r.repair_cursor:=NULL;r.repair_count:=0;r.repair_known:=0;r.repair_places:=0;r.repair_multiple:=0;r.repair_unread:=0;r.repair_previews:='{}';
   END IF;
   n:=0;last_id:=r.repair_cursor;ids:=r.repair_previews;
   FOR m IN SELECT * FROM public.notification_center_view_members WHERE organization=v.organization AND recipient=v.recipient AND group_key=r.group_key
    AND (r.repair_cursor IS NULL OR event_id>r.repair_cursor) ORDER BY event_id LIMIT budget LOOP
    last_id:=m.event_id;n:=n+1;
    SELECT * INTO e FROM public.notification_center_events WHERE id=m.event_id;
    SELECT * INTO d FROM public.notification_center_deliveries WHERE event_id=m.event_id AND recipient=v.recipient AND sequence<=v.snapshot ORDER BY sequence DESC LIMIT 1;
    IF e.id IS NULL OR d.event_id IS NULL OR NOT public.notification_center_prepared_scope_member(e,d,r.group_key,r.id,r.after_sequence,r.through_sequence,v.anchor,r.capture_is_read)
     OR NOT public.notification_center_prepared_policy(e,v.anchor,privacy) THEN CONTINUE; END IF;
    SELECT * INTO b FROM public.notification_center_batch_internal(e,d);
    r.repair_count:=r.repair_count+1;r.repair_known:=r.repair_known+(m.places IS NOT NULL)::int;
    r.repair_places:=r.repair_places+coalesce(m.places,0);r.repair_multiple:=r.repair_multiple+m.multiple::int;r.repair_unread:=r.repair_unread+(NOT b.is_read)::int;
    ids:=array_append(ids,e.id);
   END LOOP;
   SELECT coalesce(array_agg(id ORDER BY occurred_at DESC,id DESC),'{}') INTO ids FROM(SELECT DISTINCT ev.id,ev.occurred_at FROM unnest(ids) p(event_id) JOIN public.notification_center_events ev ON ev.id=p.event_id ORDER BY ev.occurred_at DESC,ev.id DESC LIMIT 3) q;
   UPDATE public.notification_center_view_rows SET state=CASE WHEN n>=budget THEN 'preparing' WHEN r.repair_count=0 THEN 'removed' ELSE 'ready' END,
    repair_cursor=CASE WHEN n>=budget THEN last_id END,repair_revision=s.revision,repair_read_revision=read_rev,repair_privacy_key=privacy_key,
    repair_count=r.repair_count,repair_known=r.repair_known,repair_places=r.repair_places,repair_multiple=r.repair_multiple,repair_unread=r.repair_unread,repair_previews=ids,
    revision=CASE WHEN n<budget THEN s.revision ELSE revision END,read_revision=CASE WHEN n<budget THEN read_rev ELSE read_revision END,
    privacy_key=CASE WHEN n<budget THEN privacy_key ELSE notification_center_view_rows.privacy_key END,
    activity_count=CASE WHEN n<budget THEN r.repair_count ELSE activity_count END,known_count=CASE WHEN n<budget THEN r.repair_known ELSE known_count END,
    places=CASE WHEN n<budget THEN r.repair_places ELSE places END,multiple_count=CASE WHEN n<budget THEN r.repair_multiple ELSE multiple_count END,
    is_read=CASE WHEN n<budget THEN r.repair_unread=0 ELSE is_read END,
    latest_event=CASE WHEN n<budget THEN ids[1] ELSE latest_event END,preview_events=CASE WHEN n<budget THEN ids ELSE preview_events END
    WHERE token=r.token AND position=r.position;
   processed:=processed+greatest(n,1);
  EXCEPTION WHEN lock_not_available THEN NULL;
   WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code=RETURNED_SQLSTATE;
    UPDATE public.notification_center_view_rows SET state='preparing',retry_count=retry_count+1,last_error_code=error_code,
     repair_revision=s.revision,repair_read_revision=read_rev,repair_privacy_key=privacy_key,repair_cursor=NULL,
     repair_count=0,repair_known=0,repair_places=0,repair_multiple=0,repair_unread=0,repair_previews='{}',
     quarantined=retry_count>=4,next_attempt_at=clock_timestamp()+make_interval(secs=>least(300,power(2,least(retry_count,8))*(0.9+random()*0.2)))
     WHERE token=work.token AND position=work.position;
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
REVOKE ALL ON FUNCTION public.prepare_notification_center_views(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_notification_center_views(integer) TO service_role;
