-- Cleaning service — public toilet status for an occasion (any signed-in user).
-- Powers the participant tile grid and the coloured map pins. Returns one row
-- per toilet with the derived status (highest open-report severity:
-- paper < hygiene < contamination; none open -> green) and the last report time.
-- Hidden toilets (places.is_hidden = true) are INCLUDED here on purpose: marking a
-- toilet hidden only removes its pin from the map (the map filters is_hidden), but
-- it must still be reportable/serviceable in the cleaning list.
-- No notes or reporter names here — those are crew-only (get_cleaning_reports).
-- Also returns is_blocked for the caller (anti-spam ban) so the participant UI
-- can grey the report action out without an extra round-trip.
-- Deliberately does NOT check the "cleaning" feature flag: reading toilet
-- statuses must keep working even after the feature is turned off (so the crew
-- can still resolve what is open). Only new reports are gated — in
-- report_cleaning_issue.
CREATE OR REPLACE FUNCTION public.get_cleaning_status(oc bigint) RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, extensions
AS $$
DECLARE
  v_data jsonb;
  v_blocked boolean;
  v_muted boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required');
  END IF;

  SELECT
    COALESCE(bool_or(is_cleaning_blocked), false),
    COALESCE(bool_or((data->>'cleaning_notifications_off')::boolean), false)
  INTO v_blocked, v_muted
  FROM public.occasion_users
  WHERE occasion = oc AND "user" = auth.uid();

  SELECT COALESCE(jsonb_agg(t ORDER BY t.title), '[]'::jsonb)
  INTO v_data
  FROM (
    SELECT
      p.id AS place,
      p.title AS title,
      -- Severity ranking — keep in sync with the CleaningStatus enum order in
      -- cleaning_status.dart (green < paper < hygiene < contamination).
      CASE COALESCE(MAX(
        CASE r.problem_type
          WHEN 'contamination' THEN 3
          WHEN 'hygiene'       THEN 2
          WHEN 'paper'         THEN 1
          ELSE 0
        END), 0)
        WHEN 3 THEN 'contamination'
        WHEN 2 THEN 'hygiene'
        WHEN 1 THEN 'paper'
        ELSE 'green'
      END AS status,
      MAX(r.created_at) AS last_reported_at
    FROM public.places p
    LEFT JOIN public.cleaning_reports r
      ON r.place = p.id AND r.resolved_at IS NULL
    WHERE p.occasion = oc
      AND p.type = 'toilet'
    GROUP BY p.id, p.title
  ) t;

  RETURN jsonb_build_object(
    'code', 200,
    'data', v_data,
    'is_blocked', v_blocked,
    'notifications_muted', v_muted
  );
END;
$$;
