CREATE OR REPLACE FUNCTION public.validate_occasion_user_csv_import_v1(
    p_occasion_id bigint,
    p_rows jsonb,
    p_delete_user_ids jsonb
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_id bigint;
BEGIN
    SELECT o.unit INTO v_unit_id
      FROM public.occasions o
     WHERE o.id = p_occasion_id;
    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;
    IF NOT (
        public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
    IF COALESCE(jsonb_typeof(p_rows), 'null') <> 'array'
       OR COALESCE(jsonb_typeof(p_delete_user_ids), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_IMPORT_PAYLOAD';
    END IF;
    IF jsonb_array_length(p_rows) > 10000
       OR jsonb_array_length(p_delete_user_ids) > 10000 THEN
        RAISE EXCEPTION 'IMPORT_PAYLOAD_TOO_LARGE';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) item
         WHERE jsonb_typeof(item) <> 'object'
            OR jsonb_typeof(item->'data') <> 'object'
    ) THEN
        RAISE EXCEPTION 'INVALID_IMPORT_ROW';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) item
         WHERE NULLIF(btrim(item->'data'->>'email'), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'EMAIL_REQUIRED';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) item
         WHERE length(btrim(item->'data'->>'email')) > 254
            OR lower(btrim(item->'data'->>'email'))
               !~ '^[^[:space:]@]+@[^[:space:]@]+$'
            OR (
                item ? 'email_delivery'
                AND (
                    NULLIF(btrim(item->>'email_delivery'), '') IS NULL
                    OR length(btrim(item->>'email_delivery')) > 254
                    OR lower(btrim(item->>'email_delivery'))
                       !~ '^[^[:space:]@]+@[^[:space:]@]+$'
                )
            )
    ) THEN
        RAISE EXCEPTION 'INVALID_EMAIL';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) item
         GROUP BY lower(btrim(item->'data'->>'email'))
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_ACCOUNT_EMAIL';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) item
         WHERE NULLIF(item->>'user_id', '') IS NOT NULL
         GROUP BY item->>'user_id'
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_USER_ID';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM jsonb_array_elements(p_rows) item
          JOIN jsonb_array_elements_text(p_delete_user_ids) deleted(id)
            ON deleted.id = item->>'user_id'
    ) THEN
        RAISE EXCEPTION 'CONFLICTING_IMPORT_OPERATION';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_occasion_user_csv_import_v1(bigint, jsonb, jsonb)
FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.import_occasion_users_from_csv_internal_v1(bigint, jsonb, jsonb)
RENAME TO import_occasion_users_from_csv_apply_v1;

REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_apply_v1(bigint, jsonb, jsonb)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_internal_v1(
    p_occasion_id bigint,
    p_rows jsonb,
    p_delete_user_ids jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.validate_occasion_user_csv_import_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
    RETURN public.import_occasion_users_from_csv_apply_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_internal_v1(bigint, jsonb, jsonb)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(
    p_occasion_id bigint,
    p_rows jsonb,
    p_delete_user_ids jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT public.import_occasion_users_from_csv_internal_v1(
    p_occasion_id, p_rows, p_delete_user_ids);
$$;

GRANT EXECUTE ON FUNCTION public.import_occasion_users_from_csv(bigint, jsonb, jsonb)
TO authenticated;
