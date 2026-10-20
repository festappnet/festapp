-- Companion administration follows the canonical occasion-editor capability.
-- Manager/admin/unit inheritance is resolved when the user enters the occasion;
-- this command must not maintain a second role hierarchy of its own.
CREATE OR REPLACE FUNCTION public.get_can_assign_companions_on_occasion(
  p_occasion bigint
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT auth.uid() IS NOT NULL
     AND public.get_is_editor_on_occasion(p_occasion) IS TRUE
$$;

REVOKE ALL ON FUNCTION public.get_can_assign_companions_on_occasion(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_can_assign_companions_on_occasion(bigint)
  TO authenticated;
