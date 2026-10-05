-- Retired endpoints must stay absent after the canonical BankSync cutover.
DO $$
DECLARE signature text;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.get_fetchable_bank_accounts()',
        'public.get_fetchable_bank_accounts_for_unit(bigint)',
        'public.get_fetchable_bank_accounts_with_t_count()',
        'public.insert_transactions(jsonb,bigint)',
        'public.process_email_transaction(jsonb)',
        'public.get_bank_account_secret(bigint)',
        'public.update_bank_account_token(bigint,text,timestamp with time zone)',
        'public.regenerate_bank_account_pairing_code(bigint)',
        'public.get_bank_account_by_pairing_code(text)',
        'public.log_transactions_parser_log(bigint,text,text,text)',
        'public.set_last_fetch_time(bigint)',
        'public.require_legacy_bank_authority(bigint)'
    ] LOOP
        PERFORM assert_true(to_regprocedure(signature) IS NULL,
            'retired bank ingress RPC must remain absent: ' || signature);
    END LOOP;
    PERFORM assert_true(to_regprocedure('public.ingest_bank_sync_transaction(text,text,text,jsonb)') IS NOT NULL,
        'canonical BankSync ingest remains available');
END;
$$;
