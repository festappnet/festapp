CREATE OR REPLACE FUNCTION public.import_user_group_assignments_internal_v1(
    p_occasion_id bigint,
    p_assignments jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_assignment record;
    v_group_id bigint;
    v_group_title text;
    v_keep_admin boolean;
    v_unit_id bigint;
BEGIN
    SELECT o.unit INTO v_unit_id
    FROM public.occasions o
    WHERE o.id = p_occasion_id;

    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;

    IF NOT (
        public.get_is_editor_on_occasion(p_occasion_id)
        OR public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    IF COALESCE(jsonb_typeof(p_assignments), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_ASSIGNMENTS';
    END IF;

    -- Serialize imports for one occasion so normalized group titles cannot be
    -- created twice by concurrent CSV imports.
    PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion_id);

    FOR v_assignment IN
        SELECT assignment.user_id, assignment.group_title
        FROM jsonb_to_recordset(p_assignments)
            AS assignment(user_id uuid, group_title text)
    LOOP
        IF v_assignment.user_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM public.occasion_users ou
            WHERE ou.occasion = p_occasion_id
              AND ou."user" = v_assignment.user_id
        ) THEN
            RAISE EXCEPTION 'USER_NOT_ON_OCCASION';
        END IF;

        v_group_title := NULLIF(btrim(v_assignment.group_title), '');
        v_group_id := NULL;
        v_keep_admin := false;

        IF v_group_title IS NOT NULL THEN
            SELECT ugi.id
            INTO v_group_id
            FROM public.user_group_info ugi
            WHERE ugi.occasion = p_occasion_id
              AND ugi.type IS NULL
              AND lower(btrim(ugi.title)) = lower(v_group_title)
            ORDER BY ugi.id
            LIMIT 1;

            IF v_group_id IS NULL THEN
                INSERT INTO public.user_group_info (occasion, title)
                VALUES (p_occasion_id, v_group_title)
                RETURNING id INTO v_group_id;
            ELSE
                SELECT COALESCE(ug.is_admin, false)
                INTO v_keep_admin
                FROM public.user_groups ug
                WHERE ug."user" = v_assignment.user_id
                  AND ug."group" = v_group_id;

                v_keep_admin := COALESCE(v_keep_admin, false);
            END IF;
        END IF;

        DELETE FROM public.user_groups ug
        USING public.user_group_info ugi
        WHERE ug."group" = ugi.id
          AND ug."user" = v_assignment.user_id
          AND ugi.occasion = p_occasion_id
          AND ugi.type IS NULL;

        IF v_group_id IS NOT NULL THEN
            INSERT INTO public.user_groups ("user", "group", is_admin)
            VALUES (v_assignment.user_id, v_group_id, v_keep_admin);
        END IF;
    END LOOP;
END;
$$;



REVOKE ALL ON FUNCTION public.import_user_group_assignments_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated;
