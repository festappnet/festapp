-- Owned disposable WordPress integration backend only. Never run on production.
-- Add a separate form and copied products without resetting existing test orders.
DO $$
DECLARE form_id bigint;
BEGIN
  IF (SELECT count(*) FROM public.organizations) <> 1 OR
     (SELECT title FROM public.organizations WHERE id = 1) IS DISTINCT FROM 'Test Organization' OR
     NOT EXISTS (SELECT 1 FROM public.forms WHERE link = 'embedded-synthetic') THEN
    RAISE EXCEPTION 'Existing synthetic embed backend required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.forms WHERE link = 'wix-qa-20261025') THEN
    RETURN; -- Never reset stock or erase previous purchases to obtain a passing run.
  END IF;
  PERFORM set_config('request.jwt.claim.sub',
    (SELECT id::text FROM auth.users WHERE email = '1+t@t.com'), true);
  form_id := public.duplicate_form_to_occasion_internal_v1(
    (SELECT id FROM public.forms WHERE link = 'embedded-synthetic'),
    'embedded-event', 'cs');
  UPDATE public.forms SET
    link = public.reserve_public_link_internal('form', form_id, 'wix-qa-20261025', true),
    title = 'Wix - synthetic checkout',
    header = '<h1>Wix - synthetic checkout</h1><p>Isolated integration test. No real payment.</p>',
    participant_capacity = 100
  WHERE id = form_id;
END $$;
NOTIFY pgrst, 'reload schema';
