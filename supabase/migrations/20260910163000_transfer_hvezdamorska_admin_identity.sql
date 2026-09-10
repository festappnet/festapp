-- The Hvezda Morska source kept the active administrator's capabilities on a
-- retired, hidden identity. Move only active authorization and derived private
-- scope rows to the canonical login; historical created_by attribution stays
-- on the retired identity.
DO $migration$
DECLARE
  active_id constant uuid := '95b8fa18-a7b7-443a-93f8-28dc63d674bb';
  retired_id constant uuid := '2d4832f0-19b1-4803-8816-ee7803f0db70';
  source_capabilities bigint;
  target_capabilities bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_info WHERE id = retired_id) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_info
    WHERE id = active_id AND organization = 7
  ) THEN
    RAISE EXCEPTION 'canonical Hvezda Morska administrator identity is missing';
  END IF;

  SELECT
    (SELECT count(*) FROM public.occasion_users WHERE "user" = retired_id) +
    (SELECT count(*) FROM public.unit_users WHERE "user" = retired_id) +
    (SELECT count(*) FROM public.organization_users WHERE "user" = retired_id) +
    (SELECT count(*) FROM eshop.bank_account_users WHERE "user" = retired_id) +
    (SELECT count(*) FROM public.client_sync_private_scopes WHERE user_id = retired_id)
  INTO source_capabilities;

  IF source_capabilities = 0 THEN
    RETURN;
  END IF;

  SELECT
    (SELECT count(*) FROM public.occasion_users WHERE "user" = active_id) +
    (SELECT count(*) FROM public.unit_users WHERE "user" = active_id) +
    (SELECT count(*) FROM public.organization_users WHERE "user" = active_id) +
    (SELECT count(*) FROM eshop.bank_account_users WHERE "user" = active_id) +
    (SELECT count(*) FROM public.client_sync_private_scopes WHERE user_id = active_id)
  INTO target_capabilities;

  IF target_capabilities <> 0 THEN
    RAISE EXCEPTION 'canonical Hvezda Morska administrator already has capability rows';
  END IF;

  UPDATE public.occasion_users SET "user" = active_id WHERE "user" = retired_id;
  UPDATE public.unit_users SET "user" = active_id WHERE "user" = retired_id;
  UPDATE public.organization_users
  SET "user" = active_id, is_hidden = false, updated_at = now()
  WHERE "user" = retired_id;
  UPDATE eshop.bank_account_users SET "user" = active_id WHERE "user" = retired_id;
  UPDATE public.client_sync_private_scopes SET user_id = active_id WHERE user_id = retired_id;

  IF EXISTS (SELECT 1 FROM public.occasion_users WHERE "user" = retired_id)
    OR EXISTS (SELECT 1 FROM public.unit_users WHERE "user" = retired_id)
    OR EXISTS (SELECT 1 FROM public.organization_users WHERE "user" = retired_id)
    OR EXISTS (SELECT 1 FROM eshop.bank_account_users WHERE "user" = retired_id)
    OR EXISTS (SELECT 1 FROM public.client_sync_private_scopes WHERE user_id = retired_id)
  THEN
    RAISE EXCEPTION 'retired Hvezda Morska administrator still owns active capabilities';
  END IF;
END
$migration$;
