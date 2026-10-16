-- Counts and the caller's own attendance remain available via the existing RPC.
DROP POLICY IF EXISTS "Enable read for all" ON public.event_users;
DROP POLICY IF EXISTS "Editors read occasion participants" ON public.event_users;
CREATE POLICY "Editors read occasion participants" ON public.event_users
AS PERMISSIVE FOR SELECT TO authenticated
USING (public.get_is_editor_view_on_occasion((SELECT occasion FROM public.events WHERE id=event)));
