-- Reconcile invitation delivery status across the default cloud, source a,
-- and the self-hosted canonical target. Historical migration ledgers differ,
-- so this migration is deliberately idempotent and owns the final contract.

ALTER TABLE public.log_emails
  ADD COLUMN IF NOT EXISTS recipient_user uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'log_emails_recipient_user_fkey'
      AND conrelid = 'public.log_emails'::regclass
  ) THEN
    ALTER TABLE public.log_emails
      ADD CONSTRAINT log_emails_recipient_user_fkey
      FOREIGN KEY (recipient_user) REFERENCES public.user_info(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS log_emails_occasion_recipient_created_idx
  ON public.log_emails (occasion, recipient_user, created_at DESC)
  WHERE recipient_user IS NOT NULL;

-- `email_delivery` is canonical on newer schemas. Reading it through to_jsonb
-- keeps the same matching rule on the older default cloud schema where that
-- column has not yet been introduced.
WITH deterministic_matches AS (
  SELECT
    le.id,
    (array_agg(DISTINCT ou."user"))[1] AS recipient_user,
    (array_agg(DISTINCT ou.occasion))[1] AS occasion
  FROM public.log_emails le
  JOIN public.email_templates et
    ON et.id::text = le.template
   AND et.code = 'SIGN_IN_CODE'
  JOIN public.user_info ui
    ON ui.organization = le.organization
   AND lower(btrim(COALESCE(
         NULLIF(to_jsonb(ui)->>'email_delivery', ''),
         ui.email_readonly
       ))) = lower(btrim(le."to"))
  JOIN public.occasion_users ou ON ou."user" = ui.id
  JOIN public.occasions o
    ON o.id = ou.occasion
   AND o.organization = le.organization
  WHERE le.recipient_user IS NULL
    AND (le.occasion IS NULL OR le.occasion = ou.occasion)
  GROUP BY le.id
  HAVING count(DISTINCT ou."user") = 1
     AND count(DISTINCT ou.occasion) = 1
)
UPDATE public.log_emails le
SET recipient_user = matches.recipient_user,
    occasion = COALESCE(le.occasion, matches.occasion)
FROM deterministic_matches matches
WHERE matches.id = le.id;

COMMENT ON COLUMN public.log_emails.recipient_user IS
  'Concrete account recipient for auditable account email; NULL only for legacy or non-account mail.';

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

  WITH accepted AS (
    SELECT
      le.recipient_user AS "user",
      count(*)::integer AS send_count,
      min(le.created_at) AS first_sent_at,
      max(le.created_at) AS last_sent_at
    FROM public.log_emails le
    JOIN public.email_templates et ON et.id::text = le.template
    WHERE le.occasion = p_occasion
      AND le.recipient_user IS NOT NULL
      AND et.code = 'SIGN_IN_CODE'
    GROUP BY le.recipient_user
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

-- The delivery log is the only persisted truth. Older clients still read an
-- `is_invited` projection from the editor bundle, so retain one thin response
-- adapter until those released clients are outside the supported version set.
UPDATE public.occasion_users
SET data = data - 'is_invited'
WHERE data ? 'is_invited';

DO $$
BEGIN
  IF to_regprocedure(
       'public.get_occasion_users_for_edit_invitation_base_v1(bigint)'
     ) IS NULL THEN
    ALTER FUNCTION public.get_occasion_users_for_edit(bigint)
      RENAME TO get_occasion_users_for_edit_invitation_base_v1;
  END IF;
END $$;

REVOKE ALL ON FUNCTION
  public.get_occasion_users_for_edit_invitation_base_v1(bigint)
  FROM PUBLIC, anon, authenticated;

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
    SELECT DISTINCT le.recipient_user AS "user"
    FROM public.log_emails le
    JOIN public.email_templates et ON et.id::text = le.template
    WHERE le.occasion = p_occasion_id
      AND le.recipient_user IS NOT NULL
      AND et.code = 'SIGN_IN_CODE'
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
