-- Synthetic reference identity needed by guarded forward migrations.
-- The production schema baseline contains no tenant rows. This file is loaded
-- only by the destructive, isolated local-test database bootstrap.
-- Keep the migration's identity/security guards enabled; never skip them.
INSERT INTO public.organizations(id,title) VALUES(19,'Slunovrat')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.organizations(id,title) VALUES(3,'vstupenky.online')
ON CONFLICT (id) DO NOTHING;
