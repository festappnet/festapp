-- Source: database/functions/units/unit_picker_favorites.sql

CREATE TABLE IF NOT EXISTS public.unit_picker_favorites (
  user_id uuid NOT NULL REFERENCES public.user_info(id) ON DELETE CASCADE,
  unit_id bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, unit_id)
);

CREATE INDEX IF NOT EXISTS unit_picker_favorites_unit_id_idx
  ON public.unit_picker_favorites (unit_id);

ALTER TABLE public.unit_picker_favorites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.unit_picker_favorites FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.unit_picker_favorites TO authenticated;

CREATE POLICY unit_picker_favorites_select ON public.unit_picker_favorites
  FOR SELECT TO authenticated USING (
    user_id = (SELECT auth.uid())
    AND public.can_read_unit_occasion_catalog(unit_id)
  );

CREATE POLICY unit_picker_favorites_insert ON public.unit_picker_favorites
  FOR INSERT TO authenticated WITH CHECK (
    user_id = (SELECT auth.uid())
    AND public.can_read_unit_occasion_catalog(unit_id)
  );

CREATE POLICY unit_picker_favorites_delete ON public.unit_picker_favorites
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));
