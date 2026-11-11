-- Synthetic reference identity needed by guarded forward migrations.
-- The production schema baseline contains no tenant rows. This file is loaded
-- only by the destructive, isolated local-test database bootstrap.
-- Keep the migration's identity/security guards enabled; never skip them.
INSERT INTO public.organizations(id,title) VALUES(19,'Slunovrat')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.organizations(id,title) VALUES(3,'vstupenky.online')
ON CONFLICT (id) DO NOTHING;

-- A compacted baseline has no tenant rows or tenant projections. Initialize only
-- these disposable identities, after their rows exist. Older baselines still
-- run their original initialization migration later in the upgrade chain.
DO $$ BEGIN
 IF to_regprocedure('public.initialize_notification_center_internal(bigint,text)') IS NOT NULL THEN
  PERFORM public.initialize_notification_center_internal(3,'Europe/Prague');
  PERFORM public.initialize_notification_center_internal(19,'Europe/Prague');
 END IF;
END $$;
