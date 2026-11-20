-- Source: database/functions/units/unit_picker_favorites.sql

CREATE TABLE IF NOT EXISTS public.unit_picker_favorites (
  user_id uuid NOT NULL REFERENCES public.user_info(id) ON DELETE CASCADE,
  unit_id bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, unit_id)
);

CREATE INDEX IF NOT EXISTS unit_picker_favorites_unit_id_idx
  ON public.unit_picker_favorites (unit_id);

ALTER TABLE public.unit_picker_favorites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.unit_picker_favorites FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_unit_picker_favorites(p_user_id uuid)
RETURNS bigint[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE insufficient_privilege USING MESSAGE = 'Favorite access denied';
  END IF;

  RETURN ARRAY(
    SELECT unit_id
    FROM public.unit_picker_favorites
    WHERE user_id = p_user_id AND public.can_read_unit_occasion_catalog(unit_id)
    ORDER BY unit_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_unit_picker_favorite(
  p_user_id uuid, p_unit_id bigint, p_favorite boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id THEN
    RAISE insufficient_privilege USING MESSAGE = 'Favorite access denied';
  END IF;
  IF p_unit_id IS NULL OR p_favorite IS NULL THEN
    RAISE null_value_not_allowed USING MESSAGE = 'Unit and favorite state required';
  END IF;

  IF p_favorite THEN
    IF NOT public.can_read_unit_occasion_catalog(p_unit_id) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Favorite access denied';
    END IF;
    INSERT INTO public.unit_picker_favorites(user_id, unit_id)
    VALUES (p_user_id, p_unit_id)
    ON CONFLICT (user_id, unit_id) DO NOTHING;
  ELSE
    DELETE FROM public.unit_picker_favorites
    WHERE user_id = p_user_id AND unit_id = p_unit_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_unit_picker_favorites(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.set_unit_picker_favorite(uuid, bigint, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_picker_favorites(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_unit_picker_favorite(uuid, bigint, boolean) TO authenticated;
