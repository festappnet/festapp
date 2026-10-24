CREATE OR REPLACE FUNCTION public.add_user_to_occasion_internal_v1(oc bigint, usr uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    joined_at             timestamptz;
    occasion_open         BOOLEAN;
    user_data             JSONB;
    user_exists           BOOLEAN;
    user_org              BIGINT;
    occasion_org          BIGINT;
    unit_id               BIGINT;

    -- Initialize flags (though SELECT INTO will overwrite these with NULL if no row found)
    unit_is_manager       BOOLEAN := false;
    unit_is_editor        BOOLEAN := false;
    unit_is_editor_view   BOOLEAN := false;

    is_privileged         BOOLEAN := false;
BEGIN
    -- 1. Retrieve the organization, the unit, and the open status of the occasion.
    SELECT organization, unit, is_open
      INTO occasion_org, unit_id, occasion_open
      FROM occasions
     WHERE id = oc;

    -- 2. Get the organization of the user.
    SELECT organization
      INTO user_org
      FROM user_info
     WHERE id = usr;

    -- 3. Ensure the user and the occasion belong to the same organization.
    IF user_org IS DISTINCT FROM occasion_org THEN
        RETURN jsonb_build_object(
                  'code', 403,
                  'message', 'User does not belong to the same organization as the occasion'
              );
    END IF;

    PERFORM public.notification_center_active_internal(occasion_org);

    -- 4. Retrieve the unit-level role information from unit_users.
    SELECT is_manager, is_editor, is_editor_view
      INTO unit_is_manager, unit_is_editor, unit_is_editor_view
      FROM unit_users
     WHERE unit = unit_id AND "user" = usr;

    -- CRITICAL FIX: SELECT INTO sets variables to NULL if no row is found.
    -- We must ensure they are boolean FALSE to satisfy NOT NULL constraints later.
    unit_is_manager     := COALESCE(unit_is_manager, false);
    unit_is_editor      := COALESCE(unit_is_editor, false);
    unit_is_editor_view := COALESCE(unit_is_editor_view, false);

    -- 5. Define is_privileged.
    --    User is privileged if they have specific unit roles OR are an admin on the occasion.
    is_privileged := public.closed_occasion_enrolment_rule(unit_is_manager,unit_is_editor,unit_is_editor_view,
                     public.get_is_admin_on_occasion(oc));

    -- 6. Permission Check: Closed Occasions.
    --    If the occasion is not open, only privileged users can be added/modified.
    IF NOT occasion_open AND NOT is_privileged THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- 7. Retrieve the user info and build a JSON object merging any existing data.
    SELECT COALESCE(ui.data, '{}'::jsonb) || jsonb_build_object(
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'email', ui.email_readonly
           )
      INTO user_data
      FROM user_info ui
     WHERE ui.id = usr;

    -- 8. Check if the user already exists in the occasion_users table.
    SELECT EXISTS (
             SELECT 1
               FROM occasion_users
              WHERE occasion = oc AND "user" = usr
           ) INTO user_exists;

    IF user_exists THEN
        -- Update the existing row with the new data and the unit role flags.
        UPDATE occasion_users
           SET data           = user_data,
               is_manager     = unit_is_manager,
               is_editor      = unit_is_editor,
               is_editor_view = unit_is_editor_view,
               is_editor_order = unit_is_editor,
               is_editor_order_view = unit_is_editor_view
         WHERE occasion = oc AND "user" = usr;
    ELSE
        -- Insert a new row into occasion_users, using the unit-level role flags.
        INSERT INTO occasion_users (
            occasion,
            "user",
            created_at,
            is_editor,
            is_manager,
            is_editor_view,
            is_editor_order,
            is_editor_order_view,
            is_approved,
            is_approver,
            data,
            role
        )
        VALUES (
            oc,
            usr,
            now(),
            unit_is_editor,
            unit_is_manager,
            unit_is_editor_view,
            unit_is_editor,
            unit_is_editor_view,
            FALSE,
            FALSE,
            user_data,
            NULL
        ) RETURNING created_at INTO joined_at;
        PERFORM public.notification_center_publish_internal(occasion_org,oc,'occasion_joined',
            'occasion-member:'||oc||':'||usr||':'||(joined_at AT TIME ZONE (SELECT timezone FROM public.notification_center_activation WHERE organization=occasion_org))::date,
            jsonb_build_object('userId',usr),auth.uid());
    END IF;

    RETURN jsonb_build_object('code', 200);
END;
$function$
;
REVOKE ALL ON FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid) TO service_role;
