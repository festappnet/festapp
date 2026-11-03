-- Cleaning service — detailed reports for the crew (get_is_cleaning_crew_on_occasion).
-- Returns open reports (optionally including resolved history) with notes, times
-- and the reporter's name. Grouped per place so the crew sees each toilet with its
-- outstanding problems. Envelope {code, message, data}.
-- Deliberately does NOT check the "cleaning" feature flag: the crew must still be
-- able to read and resolve outstanding reports after the feature is turned off.
-- Only new reports are gated — in report_cleaning_issue.
CREATE OR REPLACE FUNCTION public.get_cleaning_reports(
  oc bigint,
  p_include_resolved boolean DEFAULT false
) RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, extensions
AS $$
DECLARE
  v_data jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required');
  END IF;

  IF NOT public.get_is_cleaning_crew_on_occasion(oc) THEN
    RETURN jsonb_build_object('code', 403, 'message', 'Cleaning crew access required');
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::jsonb)
  INTO v_data
  FROM (
    SELECT
      r.id,
      r.place,
      p.title AS place_title,
      r.problem_type,
      r.note,
      r.data,
      r.created_at,
      r.created_by,
      TRIM(BOTH ' ' FROM COALESCE(ui.name, '') || ' ' || COALESCE(ui.surname, '')) AS created_by_name,
      COALESCE(ou.is_cleaning_blocked, false) AS created_by_blocked,
      r.resolved_at,
      r.resolved_by
    FROM public.cleaning_reports r
    JOIN public.places p ON p.id = r.place
    LEFT JOIN public.user_info ui ON ui.id = r.created_by
    LEFT JOIN public.occasion_users ou ON ou."user" = r.created_by AND ou.occasion = r.occasion
    WHERE r.occasion = oc
      AND (p_include_resolved OR r.resolved_at IS NULL)
  ) t;

  RETURN jsonb_build_object('code', 200, 'data', v_data);
END;
$$;
