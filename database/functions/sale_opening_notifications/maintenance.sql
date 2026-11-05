CREATE OR REPLACE FUNCTION public.maintain_sale_opening_notifications(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f record; c public.sale_opening_campaigns; s record; n integer:=0; a jsonb; counts jsonb; expired_ids uuid[];
BEGIN
 PERFORM public.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='sale opening batch limit'; END IF;
 FOR f IN SELECT forms.id,forms.occasion FROM public.forms forms JOIN public.sale_opening_campaigns x ON x.form_id=forms.id
  WHERE x.phase IN ('armed','dispatching','completed','cancelled') ORDER BY x.next_maintenance_at,x.id LIMIT p_limit
 LOOP
  -- Scope lock precedes the form lock, matching save and public commands.
  IF NOT pg_try_advisory_xact_lock(hashtextextended('sale-opening-maintenance:'||f.id,0)) THEN CONTINUE; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
  PERFORM 1 FROM public.forms WHERE id=f.id FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  SELECT * INTO c FROM public.sale_opening_campaigns WHERE form_id=f.id FOR UPDATE;
  UPDATE public.sale_opening_campaigns SET next_maintenance_at=clock_timestamp()+interval '1 minute' WHERE id=c.id;
  a:=public.get_form_availability_snapshot_internal(f.id);
  IF c.phase='armed' AND public.get_form_registration_mode_internal(f.id) IN ('regular','blueprint') THEN
   UPDATE public.sale_opening_campaigns SET phase='dispatching',opened_at=clock_timestamp(),revision=revision+1
    WHERE id=c.id RETURNING * INTO c;
  END IF;
  IF c.phase='dispatching' AND public.get_form_registration_mode_internal(f.id) IN ('regular','blueprint')
   AND c.opened_at+interval '24 hours'>clock_timestamp() THEN
   FOR s IN SELECT sub.id FROM public.sale_opening_subscriptions sub WHERE sub.campaign_id=c.id AND sub.state='active'
    AND NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.message_kind='sale_opening_opened'
     AND m.dedupe_key=c.id||':'||sub.id||':opened') ORDER BY sub.created_at,sub.id LIMIT p_limit-n
   LOOP
    BEGIN
     PERFORM public.enqueue_sale_opening_internal(s.id,'sale_opening_opened'); n:=n+1;
    EXCEPTION WHEN SQLSTATE 'PT429' THEN RETURN n; END;
   END LOOP;
   IF NOT EXISTS(SELECT 1 FROM public.sale_opening_subscriptions sub WHERE sub.campaign_id=c.id AND sub.state='active'
    AND NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.message_kind='sale_opening_opened' AND m.dedupe_key=c.id||':'||sub.id||':opened')) THEN
    UPDATE public.sale_opening_campaigns SET phase='completed' WHERE id=c.id;
   END IF;
  END IF;
  -- Temporary closures preserve the original intent. Only never-started
  -- cancellations caused by the live gate may be retried; unknown is fenced.
  UPDATE public.email_messages m SET workflow_state='pending',target_time=clock_timestamp(),prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   lease_token=NULL,lease_until=NULL,last_error=NULL
   WHERE m.message_kind='sale_opening_opened' AND m.data->>'campaign_id'=c.id::text
   AND m.workflow_state='cancelled' AND m.last_error='intent_invalid' AND public.sale_opening_intent_valid_internal(m)
   AND NOT EXISTS(SELECT 1 FROM public.email_attempts at WHERE at.message_id=m.message_id AND at.state IN ('sending','accepted','unknown'));
  IF c.phase='cancelled' OR c.opened_at+interval '24 hours'<=clock_timestamp() OR (a->>'endAt')::timestamptz<clock_timestamp() THEN
   UPDATE public.sale_opening_campaigns SET phase=CASE WHEN phase='cancelled' THEN phase ELSE 'completed' END,
    closed_at=coalesce(closed_at,clock_timestamp()) WHERE id=c.id;
   UPDATE public.sale_opening_subscriptions SET state='closed',closed_at=clock_timestamp()
    WHERE campaign_id=c.id AND state='active';
  END IF;
  -- Retain anonymous totals before deleting contacts and encrypted token sources.
  SELECT array_agg(id) INTO expired_ids FROM (SELECT id FROM public.sale_opening_subscriptions WHERE campaign_id=c.id
   AND closed_at<clock_timestamp()-interval '30 days'
   ORDER BY id LIMIT 100) expired;
  SELECT coalesce(jsonb_object_agg(state,total),'{}') INTO counts FROM (
   SELECT state,count(*) total FROM public.sale_opening_subscriptions WHERE id=ANY(expired_ids) GROUP BY state) totals;
  -- Add this sweep's totals to prior anonymous aggregates, without addresses.
  UPDATE public.sale_opening_campaigns SET retained_counts=(SELECT coalesce(jsonb_object_agg(key,total),'{}') FROM (
   SELECT key,sum(value::bigint) total FROM (SELECT * FROM jsonb_each_text(retained_counts) UNION ALL SELECT * FROM jsonb_each_text(counts)) x GROUP BY key) y) WHERE id=c.id;
  DELETE FROM public.sale_opening_subscriptions WHERE id=ANY(expired_ids);
  IF n>=p_limit THEN EXIT; END IF;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.maintain_sale_opening_notifications(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_sale_opening_notifications(integer) TO service_role;
