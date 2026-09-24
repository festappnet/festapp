-- Canonical merges can contain the same legacy occasion link in more than one
-- organization. Resolve authenticated admin reads inside the caller's tenant
-- before checking the occasion-level permission.
DO $migration$
DECLARE
  definition text;
  patched text;
BEGIN
  SELECT pg_get_functiondef('public.get_orders(text,text,jsonb)'::regprocedure)
  INTO definition;

  IF definition NOT LIKE '%organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid())%' THEN
    patched := replace(
      definition,
      E'        FROM public.occasions\n        WHERE link = p_occasion_link;',
      E'        FROM public.occasions\n        WHERE link = p_occasion_link\n          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());'
    );
    patched := replace(
      patched,
      E'        FROM public.forms\n        WHERE link = p_form_link;',
      E'        FROM public.forms\n        WHERE link = p_form_link\n          AND occasion IN (\n              SELECT o.id\n              FROM public.occasions o\n              WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid())\n          );'
    );
    IF patched = definition THEN
      RAISE EXCEPTION 'get_orders occasion resolution shape changed';
    END IF;
    EXECUTE patched;
  END IF;

  SELECT pg_get_functiondef('public.get_all_forms_with_fields(text)'::regprocedure)
  INTO definition;

  IF definition NOT LIKE '%organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid())%' THEN
    patched := replace(
      definition,
      E'    FROM public.occasions\n    WHERE link = occasion_link;',
      E'    FROM public.occasions\n    WHERE link = occasion_link\n      AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());'
    );
    IF patched = definition THEN
      RAISE EXCEPTION 'get_all_forms_with_fields occasion resolution shape changed';
    END IF;
    EXECUTE patched;
  END IF;
END
$migration$;
