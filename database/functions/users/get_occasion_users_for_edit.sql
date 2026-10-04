-- Historical SMTP invitation hints are a readonly compatibility projection, never canonical delivery evidence.
CREATE OR REPLACE FUNCTION public.get_occasion_sign_in_email_statuses(
  p_occasion bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT COALESCE(public.get_is_editor_view_on_occasion(p_occasion), false)
     AND NOT COALESCE(public.get_is_editor_order_view_on_occasion(p_occasion), false) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  WITH evidence AS (
    SELECT le.recipient_user AS "user",le.created_at AS sent_at
    FROM public.log_emails le
    JOIN public.email_templates et ON et.id::text = le.template
    WHERE le.occasion = p_occasion
      AND le.recipient_user IS NOT NULL
      AND et.code = 'SIGN_IN_CODE'
    UNION ALL
    SELECT m.recipient_user,m.accepted_at FROM public.email_messages m
    WHERE m.occasion=p_occasion AND m.message_kind='sign_in' AND m.recipient_user IS NOT NULL AND m.accepted_at IS NOT NULL
  ), accepted AS (
    SELECT "user",count(*)::integer send_count,min(sent_at) first_sent_at,max(sent_at) last_sent_at FROM evidence GROUP BY "user"
  )
  SELECT COALESCE(
    jsonb_agg(to_jsonb(accepted) ORDER BY accepted."user"),
    '[]'::jsonb
  )
  INTO v_result
  FROM accepted;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_sign_in_email_statuses(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_sign_in_email_statuses(bigint)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit(
  p_occasion_id bigint
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_users jsonb;
BEGIN
  v_result := public.get_occasion_users_for_edit_invitation_base_v1(
    p_occasion_id
  )::jsonb;
  IF COALESCE((v_result->>'code')::integer, 500) <> 200 THEN
    RETURN v_result::json;
  END IF;

  WITH accepted AS (
    SELECT (entry->>'user')::uuid AS "user" FROM jsonb_array_elements(public.get_occasion_sign_in_email_statuses(p_occasion_id)) entry
  )
  SELECT COALESCE(jsonb_agg(
    row.value || jsonb_build_object(
      'data',
      (CASE WHEN jsonb_typeof(row.value->'data') = 'object'
        THEN row.value->'data' ELSE '{}'::jsonb END - 'is_invited'::text)
      || jsonb_build_object('is_invited', accepted."user" IS NOT NULL)
    )
  ), '[]'::jsonb)
  INTO v_users
  FROM jsonb_array_elements(v_result #> '{data,occasion_users}') row
  LEFT JOIN accepted ON accepted."user" = (row.value->>'user')::uuid;

  RETURN jsonb_set(v_result, '{data,occasion_users}', v_users)::json;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit(bigint)
  TO authenticated;
