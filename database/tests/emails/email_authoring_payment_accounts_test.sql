-- Disposable local database only. No orders, customers or messages are created.
BEGIN;
DO $$
DECLARE
  v_org bigint;
  v_unit bigint;
  v_other_unit bigint;
  v_occasion bigint;
  v_other_occasion bigint;
  v_bank bigint;
  v_default bigint;
  v_cash bigint;
  v_foreign bigint;
  v_result jsonb;
  v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_function_privilege(v_role, 'public.get_email_authoring_payment_accounts(bigint,bigint)', 'EXECUTE') THEN
      RAISE EXCEPTION 'Unexpected RPC permission for %', v_role;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('service_role', 'public.get_email_authoring_payment_accounts(bigint,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Service role cannot execute metadata RPC';
  END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  BEGIN
    PERFORM public.get_email_authoring_payment_accounts(NULL, NULL);
    RAISE EXCEPTION 'Non-service caller bypassed explicit role guard';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);

  INSERT INTO public.organizations(title) VALUES ('Authoring accounts fixture') RETURNING id INTO v_org;
  INSERT INTO public.units(title, organization) VALUES ('Scope', v_org) RETURNING id INTO v_unit;
  INSERT INTO public.units(title, organization) VALUES ('Other scope', v_org) RETURNING id INTO v_other_unit;
  INSERT INTO public.occasions(title, organization, unit, link, start_time, end_time)
  VALUES ('Scope', v_org, v_unit, gen_random_uuid()::text, now(), now() + interval '1 day') RETURNING id INTO v_occasion;
  INSERT INTO public.occasions(title, organization, unit, link, start_time, end_time)
  VALUES ('Other scope', v_org, v_other_unit, gen_random_uuid()::text, now(), now() + interval '1 day') RETURNING id INTO v_other_occasion;
  INSERT INTO eshop.bank_accounts(account_number_human_readable, type, supported_currencies)
  VALUES ('fixture EUR', 'FIO', ARRAY['EUR']) RETURNING id INTO v_bank;
  INSERT INTO eshop.bank_accounts(account_number_human_readable, type)
  VALUES ('fixture CZK', 'FIO') RETURNING id INTO v_default;
  INSERT INTO eshop.bank_accounts(type) VALUES ('CASH') RETURNING id INTO v_cash;
  INSERT INTO eshop.bank_accounts(account_number_human_readable, type)
  VALUES ('unlinked fixture', 'FIO') RETURNING id INTO v_foreign;
  INSERT INTO eshop.unit_bank_accounts(unit, bank_account, priority) VALUES
    (v_unit, v_bank, 2), (v_unit, v_default, 1), (v_unit, v_cash, 0), (v_other_unit, v_foreign, 0);
  INSERT INTO public.forms(title, occasion, bank_account) VALUES
    ('Configured', v_occasion, v_bank), ('Duplicate', v_occasion, v_bank),
    ('Cash', v_occasion, v_cash), ('Wrong unit legacy form', v_occasion, v_foreign),
    ('Other occasion', v_other_occasion, v_foreign);

  v_result := public.get_email_authoring_payment_accounts(v_unit, v_occasion);
  IF jsonb_array_length(v_result->'linkedAccounts') <> 2
    OR (v_result#>>'{linkedAccounts,0,bank_accounts,id}')::bigint <> v_default
    OR (v_result#>>'{linkedAccounts,1,bank_accounts,id}')::bigint <> v_bank
    OR v_result->'formAccountIds' <> jsonb_build_array(v_bank) THEN
    RAISE EXCEPTION 'Scope, ordering, CASH exclusion or form deduplication failed';
  END IF;
  IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(v_result#>'{linkedAccounts,0,bank_accounts}') key)
      <> ARRAY['account_number', 'account_number_human_readable', 'id', 'supported_currencies', 'type'] THEN
    RAISE EXCEPTION 'Account result exposes unexpected fields';
  END IF;
  IF public.get_email_authoring_payment_accounts(v_unit, NULL)->'formAccountIds' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'Unit-only context leaked occasion configuration';
  END IF;
  v_result := public.get_email_authoring_payment_accounts(v_other_unit, v_other_occasion);
  IF jsonb_array_length(v_result->'linkedAccounts') <> 1
    OR v_result->'formAccountIds' <> jsonb_build_array(v_foreign) THEN
    RAISE EXCEPTION 'Other unit returned accounts outside its scope';
  END IF;
  BEGIN
    PERFORM public.get_email_authoring_payment_accounts(v_unit, v_other_occasion);
    RAISE EXCEPTION 'Mismatched occasion unit accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.get_email_authoring_payment_accounts(-1, NULL);
    RAISE EXCEPTION 'Missing unit accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END;
$$;
ROLLBACK;
