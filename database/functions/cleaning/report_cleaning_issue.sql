-- Cleaning service — participant reports a problem on a toilet.
-- SECURITY DEFINER: participants have no direct write access to cleaning_reports
-- or log_notifications, so all validation, insert and crew notification happen
-- here. Envelope {code, message, data} like submit_event_feedback.
--
-- Behaviour:
--   * only approved occasion participants; place must exist, belong to the
--     occasion and be of place_type "toilet"; feature "cleaning" must be
--     enabled on the occasion.
--   * dedup: an already-open report of the same (place, problem_type) is NOT
--     duplicated and sends NO extra notification — returns 200 data.duplicate=true
--     and appends the reporter's note to the existing row so it is not lost.
--   * rate limit: max 5 reports per user per 15 minutes -> 429.
--   * on a fresh report, inserts a log_notifications row addressed to the crew
--     (data.path = 'cleaning' so the push deep-links to the Cleaning page).
CREATE OR REPLACE FUNCTION public.report_cleaning_issue(
  place_id bigint,
  problem_type text,
  note text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, extensions
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_note text := NULLIF(btrim(COALESCE(note, '')), '');
  v_place public.places%ROWTYPE;
  v_occasion bigint;
  v_organization bigint;
  v_type_label text;
  v_existing public.cleaning_reports%ROWTYPE;
  v_report public.cleaning_reports%ROWTYPE;
  v_crew jsonb;
  v_notification_deferred boolean:=false;
  v_notification uuid;
  v_policy jsonb; v_new_data jsonb;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required to report a cleaning issue');
  END IF;

  -- Problem types — keep in sync with: cleaning_reports.problem_type CHECK
  -- (database/tables/tables.sql), CleaningStatusHelper (cleaning_status.dart)
  -- and the report dialog (cleaning_report_dialog.dart).
  IF problem_type NOT IN ('paper', 'hygiene', 'contamination') THEN
    RETURN jsonb_build_object('code', 400, 'message', 'Invalid problem type');
  END IF;

  IF char_length(COALESCE(v_note, '')) > 2000 THEN
    RETURN jsonb_build_object('code', 413, 'message', 'Note is too long');
  END IF;

  SELECT * INTO v_place FROM public.places WHERE id = place_id;
  IF NOT FOUND OR v_place.occasion IS NULL THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Toilet not found');
  END IF;

  v_occasion := v_place.occasion;

  IF NOT EXISTS (
    SELECT 1
    FROM public.occasion_users
    WHERE occasion = v_occasion
      AND "user" = v_user
      AND is_approved = true
  ) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'Approved occasion participation is required');
  END IF;

  -- Blocked reporters (anti-spam hard ban) cannot file reports on this occasion.
  -- This is the source of truth; the UI also greys the report action out via the
  -- is_blocked flag returned by get_cleaning_status.
  IF EXISTS (
    SELECT 1 FROM public.occasion_users
    WHERE occasion = v_occasion
      AND "user" = v_user
      AND is_cleaning_blocked = true
  ) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'Reporting has been disabled for your account');
  END IF;

  -- Place must be flagged as a toilet (places.type = 'toilet'). This is set by
  -- the "WC / Úklid" checkbox in the admin Places grid — no place_types catalog
  -- row is required.
  IF v_place.type IS DISTINCT FROM 'toilet' THEN
    RETURN jsonb_build_object('code', 400, 'message', 'Place is not a toilet');
  END IF;

  -- Feature "cleaning" must be enabled on the occasion (occasions.features).
  IF NOT EXISTS (
    SELECT 1
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(o.features, '[]'::jsonb)) feature
    WHERE o.id = v_occasion
      AND feature->>'code' = 'cleaning'
      AND LOWER(COALESCE(feature->>'is_enabled', 'false')) = 'true'
  ) THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Cleaning feature is not enabled for this occasion');
  END IF;

  -- Committed accepted work, including appended duplicate notes, shares one
  -- actor identity. Removing a report cannot replenish its rolling budget.
  BEGIN
    v_policy:=public.abuse_effective_rules_v1('cleaning.report',NULL,NULL);
    PERFORM public.abuse_charge_v1(v_policy,
      jsonb_build_object('actor',v_user),jsonb_build_object('cleaning.note.bytes',octet_length(coalesce(v_note,'')), 'cleaning.report.bytes',0));
  EXCEPTION WHEN SQLSTATE 'PT429' THEN RETURN jsonb_build_object('code',429,'message','Too many reports, please wait a moment'); END;
  PERFORM pg_advisory_xact_lock(hashtextextended('cleaning-report:'||place_id::text||':'||problem_type,0));

  -- Push-notification labels are deliberately Czech-only (the crew is Czech;
  -- localizing push messages is out of scope). Keep the type list in sync — see
  -- the problem_type check above.
  v_type_label := CASE problem_type
    WHEN 'paper'         THEN 'Nedostatek toaletního papíru'
    WHEN 'hygiene'       THEN 'Nedostatek hygienických potřeb'
    WHEN 'contamination' THEN 'Totální znečištění ☣️'
  END;

  -- Dedup: reuse an open report of the same place + type.
  SELECT cr.* INTO v_existing
  FROM public.cleaning_reports cr
  WHERE cr.place = place_id
    AND cr.problem_type = report_cleaning_issue.problem_type
    AND cr.resolved_at IS NULL
  ORDER BY cr.created_at ASC
  LIMIT 1;

  IF FOUND THEN
    IF v_note IS NOT NULL THEN
      v_new_data:=COALESCE(v_existing.data,'{}'::jsonb)||jsonb_build_object('extra_notes',coalesce(v_existing.data->'extra_notes','[]'::jsonb)||to_jsonb(v_note));
      IF octet_length(v_new_data::text)>(SELECT (r->>'base_limit')::bigint FROM jsonb_array_elements(v_policy->'rules') r WHERE r->>'rule_key'='cleaning.report.bytes') THEN
        RETURN jsonb_build_object('code',429,'message','Report note capacity is limited'); END IF;
      UPDATE public.cleaning_reports SET data=v_new_data WHERE id=v_existing.id;
    END IF;
    RETURN jsonb_build_object('code',200,'data',jsonb_build_object('duplicate',true,'id',v_existing.id));
  END IF;

  INSERT INTO public.cleaning_reports (occasion, place, problem_type, note, created_by)
  VALUES (v_occasion, place_id, problem_type, v_note, v_user)
  RETURNING * INTO v_report;

  -- Notify the crew (uuid array of is_cleaning_crew users on this occasion),
  -- excluding anyone who muted cleaning notifications for themselves
  -- (occasion_users.data.cleaning_notifications_off).
  SELECT jsonb_agg("user"::text) INTO v_crew
  FROM public.occasion_users
  WHERE occasion = v_occasion
    AND is_cleaning_crew = true
    AND COALESCE((data->>'cleaning_notifications_off')::boolean, false) = false;

  IF v_crew IS NOT NULL AND jsonb_array_length(v_crew) > 0 THEN
    -- organization comes straight from the occasion row (occasions.organization
    -- is NOT NULL) — no magic fallback needed.
    SELECT organization INTO v_organization FROM public.occasions WHERE id = v_occasion;

    BEGIN
      PERFORM public.charge_notification_intent_v1(v_occasion,v_user,v_crew,v_place.title || ' - ' || v_type_label,COALESCE(v_note,v_type_label));
    INSERT INTO public.log_notifications (occasion, organization, user_id, "to", heading, content, data, abuse_admitted_at)
    VALUES (
      v_occasion,
      v_organization,
      v_user,
      v_crew,
      v_place.title || ' — ' || v_type_label,
      COALESCE(v_note, v_type_label),
      jsonb_build_object('path', 'cleaning'), statement_timestamp()
    ) RETURNING id INTO v_notification;
    PERFORM public.dispatch_log_notification_v1(v_notification);
    EXCEPTION WHEN SQLSTATE 'PT429' THEN v_notification_deferred:=true; END;
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object('duplicate', false, 'id', v_report.id, 'notificationDeferred',v_notification_deferred)
  );
END;
$$;
