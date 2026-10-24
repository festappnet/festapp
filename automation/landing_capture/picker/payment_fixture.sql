-- Disposable local capture database ONLY. Never apply to production.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.occasions WHERE id=6 AND title IN ('Ples pod hvězdami','Ball under the stars') AND unit=1)
    OR NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts WHERE unit=1 AND bank_account=1)
  THEN RAISE EXCEPTION 'Expected synthetic fixture missing'; END IF;
END $$;
UPDATE public.forms SET bank_account=1, deadline_duration_seconds=259200 WHERE id=7 AND occasion=6;
UPDATE eshop.bank_accounts SET title='Ukázkový účet pořadatele',creditor_name='Ukázkový pořadatel',
 account_number='CZ0000000000000000000000',account_number_human_readable='0000000000/0000'
 WHERE id=1;
COMMIT;
