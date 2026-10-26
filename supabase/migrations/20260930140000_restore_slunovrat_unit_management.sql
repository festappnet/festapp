-- Slunovrat's tenant login can manage only the 2026 occasion, while this same
-- person's shared identity still owns Festival Slunovrat's unit permissions.
-- Restore those unit roles to the verified tenant identity, scoped to unit 999.
DO $migration$
DECLARE
  source_id constant uuid := '01f04ac5-bcc6-4067-b5c1-c52d99ba96c8';
  target_id constant uuid := '3527c7b1-fe2d-4f1d-85b8-73f67a4819a7';
  source_roles public.unit_users%ROWTYPE;
BEGIN
  SELECT * INTO source_roles
  FROM public.unit_users
  WHERE unit = 999 AND "user" = source_id
  FOR UPDATE;

  -- Other installations without this production membership need no repair.
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF source_roles.is_manager IS NOT TRUE
    OR NOT EXISTS (SELECT 1 FROM public.units WHERE id = 999 AND organization = 19)
    OR NOT EXISTS (
      SELECT 1
      FROM public.user_info source_profile
      JOIN public.user_info target_profile
        ON lower(btrim(target_profile.email_readonly)) = lower(btrim(source_profile.email_readonly))
      JOIN auth.users source_auth ON source_auth.id = source_profile.id
      JOIN auth.users target_auth ON target_auth.id = target_profile.id
      WHERE source_profile.id = source_id
        AND target_profile.id = target_id
        AND target_profile.organization = 19
        AND source_auth.email_confirmed_at IS NOT NULL
        AND target_auth.email_confirmed_at IS NOT NULL
    )
    OR NOT EXISTS (
      SELECT 1 FROM public.organization_users
      WHERE organization = 19 AND "user" = source_id AND is_admin IS TRUE
    )
    OR NOT EXISTS (
      SELECT 1 FROM public.occasion_users ou
      JOIN public.occasions o ON o.id = ou.occasion
      WHERE ou."user" = target_id AND ou.is_manager IS TRUE
        AND o.id = 1072558 AND o.unit = 999 AND o.organization = 19
    ) THEN
    RAISE EXCEPTION 'Slunovrat unit repair identity or permission precondition failed';
  END IF;

  INSERT INTO public.unit_users (unit, "user", is_manager, is_editor, is_editor_view)
  VALUES (999, target_id, source_roles.is_manager, source_roles.is_editor, source_roles.is_editor_view)
  ON CONFLICT (unit, "user") DO UPDATE
  SET is_manager = public.unit_users.is_manager OR EXCLUDED.is_manager,
      is_editor = public.unit_users.is_editor OR EXCLUDED.is_editor,
      is_editor_view = public.unit_users.is_editor_view OR EXCLUDED.is_editor_view;
END
$migration$;
