-- Explicitly authorized on 2026-10-07: bujnmi@gmail.com is administrator of
-- the whole Slunovrat tenant. Never use the unprefixed legacy Auth account.
-- Pre-change roles must be captured privately before execution.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $repair$
DECLARE
    target_user uuid;
BEGIN
    IF current_database() <> 'festapp_rehearsal_20260909220601' THEN
        RAISE EXCEPTION 'Unexpected runtime database';
    END IF;
    SELECT ui.id INTO STRICT target_user
    FROM public.user_info ui JOIN auth.users au ON au.id = ui.id
    WHERE ui.organization = 19
      AND lower(ui.email_readonly) = 'bujnmi@gmail.com'
      AND au.email = public.format_auth_email(19, 'bujnmi@gmail.com');

    INSERT INTO public.organization_users (organization, "user", is_admin)
    VALUES (19, target_user, true)
    ON CONFLICT (organization, "user") DO UPDATE SET is_admin = true;

    INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
    SELECT id, target_user, true, true, true FROM public.units WHERE organization = 19
    ON CONFLICT (unit, "user") DO UPDATE
    SET is_manager = true, is_editor = true, is_editor_view = true;

    INSERT INTO public.occasion_users
        (occasion, "user", is_manager, is_editor, is_editor_view,
         is_editor_order, is_editor_order_view, is_approver, is_receptionist)
    SELECT id, target_user, true, true, true, true, true, true, true
    FROM public.occasions WHERE organization = 19
    ON CONFLICT (occasion, "user") DO UPDATE
    SET is_manager = true, is_editor = true, is_editor_view = true,
        is_editor_order = true, is_editor_order_view = true,
        is_approver = true, is_receptionist = true;

    IF NOT EXISTS (SELECT 1 FROM public.organization_users
        WHERE organization = 19 AND "user" = target_user AND is_admin)
       OR EXISTS (SELECT 1 FROM public.units u
           LEFT JOIN public.unit_users uu ON uu.unit = u.id AND uu."user" = target_user
           WHERE u.organization = 19 AND NOT coalesce(
               uu.is_manager AND uu.is_editor AND uu.is_editor_view, false))
       OR EXISTS (SELECT 1 FROM public.occasions o
           LEFT JOIN public.occasion_users ou ON ou.occasion = o.id AND ou."user" = target_user
           WHERE o.organization = 19 AND NOT coalesce(
               ou.is_manager AND ou.is_editor AND ou.is_editor_view
               AND ou.is_editor_order AND ou.is_editor_order_view
               AND ou.is_approver AND ou.is_receptionist, false)) THEN
        RAISE EXCEPTION 'Incomplete tenant administrator assignment';
    END IF;
END;
$repair$;
COMMIT;
