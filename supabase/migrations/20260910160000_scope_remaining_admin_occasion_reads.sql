-- Canonical merges can contain the same legacy occasion link in more than one
-- organization. Resolve the remaining authenticated admin reads inside the
-- caller's tenant before checking occasion-level permissions.
DO $migration$
DECLARE
  definition text;
  patched text;
BEGIN
  SELECT pg_get_functiondef('public.get_forms_by_link(text)'::regprocedure)
  INTO definition;

  IF definition NOT LIKE '%organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid())%' THEN
    patched := replace(
      definition,
      E'    FROM public.occasions\n    WHERE link = occasion_link;',
      E'    FROM public.occasions\n    WHERE link = occasion_link\n      AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());'
    );
    IF patched = definition THEN
      RAISE EXCEPTION 'get_forms_by_link occasion resolution shape changed';
    END IF;
    EXECUTE patched;
  END IF;

  SELECT pg_get_functiondef('public.get_products_and_types_for_edit(text)'::regprocedure)
  INTO definition;

  IF definition NOT LIKE '%organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid())%' THEN
    patched := replace(
      definition,
      E'  FROM public.occasions\n  WHERE link = occasion_link;',
      E'  FROM public.occasions\n  WHERE link = occasion_link\n    AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());'
    );
    IF patched = definition THEN
      RAISE EXCEPTION 'get_products_and_types_for_edit occasion resolution shape changed';
    END IF;
    EXECUTE patched;
  END IF;
END
$migration$;
