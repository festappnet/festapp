-- Restore the externally published registration URL for the same 2025 edition.
-- Evidence: https://akhcr.cz/akce/adventni-obnova-2025 links the old slug
-- and identifies AKH, Dub nad Moravou, 5-7 December 2025. Search Console's
-- only 404 example on 2026-10-25 is this URL and names that referring page.
-- Live identity: organization 3, occasion 94, form 66, adventniobnova2025.
-- Uses the existing resolver and permanent canonical redirect; no route override.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15s';
DO $$
BEGIN
  IF current_database() <> 'festapp_rehearsal_20260909220601' THEN
    RAISE EXCEPTION 'Unexpected database';
  END IF;
  PERFORM 1 FROM public.forms f JOIN public.occasions o ON o.id = f.occasion
    WHERE f.id = 66 AND f.link = 'adventniobnova2025'
      AND o.id = 94 AND o.organization = 3
      AND o.title = 'Adventní duchovní obnova AKH 2025'
      AND o.start_time = '2025-12-05 17:00:00+00'::timestamptz
      AND o.end_time = '2025-12-07 14:00:00+00'::timestamptz
    FOR UPDATE OF f, o;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target edition identity mismatch'; END IF;
  IF EXISTS (SELECT 1 FROM public.forms
      WHERE link = 'rijnova_pout-copy-4b889244' AND id <> 66) THEN
    RAISE EXCEPTION 'Old slug belongs to a different current form';
  END IF;
  INSERT INTO public.form_link_reservations (slug, form)
    VALUES ('rijnova_pout-copy-4b889244', 66) ON CONFLICT DO NOTHING;
  IF public.resolve_form_link_internal('rijnova_pout-copy-4b889244') IS DISTINCT FROM 66 THEN
    RAISE EXCEPTION 'Old slug reservation conflict';
  END IF;
END $$;
SELECT slug, form FROM public.form_link_reservations
  WHERE slug = 'rijnova_pout-copy-4b889244';
COMMIT;
