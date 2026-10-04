-- Run only after the reviewed account rollout. Fail closed if a working API
-- account still depends on the old worker; cash/manual accounts are unaffected.
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM eshop.bank_accounts b JOIN eshop.secrets s ON s.id=b.secret
    WHERE b.type='FIO' AND b.is_fetch_enabled AND (s.expiry_date IS NULL OR s.expiry_date>now())
      AND NOT EXISTS(SELECT 1 FROM eshop.bank_sync_connections c WHERE c.bank_account_id=b.id AND c.legacy_blocked_at IS NOT NULL))
  THEN RAISE EXCEPTION 'BANK_SYNC_ACTIVE_ACCOUNT_CUTOVER_INCOMPLETE'; END IF;
END $$;
DROP FUNCTION IF EXISTS public.get_fetchable_bank_accounts();
DROP FUNCTION IF EXISTS public.get_fetchable_bank_accounts_for_unit(bigint);
DROP FUNCTION IF EXISTS public.get_fetchable_bank_accounts_with_t_count();
DROP FUNCTION IF EXISTS public.insert_transactions(jsonb,bigint);
DROP FUNCTION IF EXISTS public.process_email_transaction(jsonb);
DROP FUNCTION IF EXISTS public.get_bank_account_secret(bigint);
DROP FUNCTION IF EXISTS public.update_bank_account_token(bigint,text,timestamptz);
DROP FUNCTION IF EXISTS public.regenerate_bank_account_pairing_code(bigint);
DROP FUNCTION IF EXISTS public.get_bank_account_by_pairing_code(text);
DROP FUNCTION IF EXISTS public.log_transactions_parser_log(bigint,text,text,text);
DROP FUNCTION IF EXISTS public.set_last_fetch_time(bigint);
DROP FUNCTION IF EXISTS public.require_legacy_bank_authority(bigint);

ALTER TABLE eshop.bank_accounts ALTER COLUMN is_fetch_enabled SET DEFAULT false;
ALTER TABLE eshop.bank_accounts ALTER COLUMN pairing_code DROP DEFAULT;
