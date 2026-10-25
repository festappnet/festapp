-- Presentation-only sample data for genuine Wix screenshots. Local fixture only.
-- Keep existing purchases, prices, stock and shared organizer/bank data intact.
BEGIN;
DO $$
DECLARE target bigint;
BEGIN
  IF (SELECT count(*) FROM public.organizations) <> 1 OR
     (SELECT title FROM public.organizations WHERE id=1) IS DISTINCT FROM 'Test Organization' THEN
    RAISE EXCEPTION 'Disposable Wix fixture required';
  END IF;
  SELECT id INTO STRICT target FROM public.forms WHERE link='wix-qa-20261025';
  IF EXISTS (
    SELECT 1 FROM public.form_fields other
    WHERE other.form <> target AND other.product_type IN (
      SELECT product_type FROM public.form_fields WHERE form=target
    )
  ) THEN
    RAISE EXCEPTION 'Refusing to change products shared with another form';
  END IF;
  UPDATE public.forms SET title='Ukázkový ples',
    header='<h1>Ukázkový ples</h1><p>Ukázkový formulář. Žádná skutečná platba.</p>'
  WHERE id=target;
  UPDATE public.form_fields SET title=CASE type
    WHEN 'email' THEN 'E-mail' WHEN 'name' THEN 'Jméno'
    WHEN 'surname' THEN 'Příjmení' WHEN 'product_type' THEN 'Vstupenka'
    ELSE title END
  WHERE form=target;
  UPDATE public.form_fields SET is_hidden=true
  WHERE form=target AND type='birth_date' AND NOT is_required;
  UPDATE eshop.products SET title='Základní vstupenka'
  WHERE product_type IN (SELECT product_type FROM public.form_fields WHERE form=target);
END $$;
COMMIT;
