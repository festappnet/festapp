DO $$
DECLARE v_bank bigint; v_connection bigint; v_user uuid; v_result jsonb;
BEGIN
  PERFORM assert_false(has_function_privilege('anon','public.ingest_bank_sync_transaction(text,text,text,jsonb)','EXECUTE'),'anonymous cannot ingest signed bank facts');
  PERFORM assert_false(has_function_privilege('authenticated','public.ingest_bank_sync_transaction(text,text,text,jsonb)','EXECUTE'),'user JWT cannot forge bank ingest');
  PERFORM assert_false(has_function_privilege('authenticated','public.activate_bank_sync_connection(bigint,text)','EXECUTE'),'bank admin does not bypass rollout authority');
  PERFORM assert_false(has_table_privilege('authenticated','eshop.bank_sync_inbox','SELECT'),'inbox inaccessible to users');
  PERFORM assert_false(has_function_privilege('authenticated','public.claim_bank_sync_operation(uuid)','EXECUTE'),'only server claims remote operations');
  SELECT id INTO v_user FROM public.user_info LIMIT 1;
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync permission fixture','FIO','9876/2010',ARRAY['CZK']) RETURNING id INTO v_bank;
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  BEGIN
    PERFORM public.get_bank_sync_connection(v_bank);
    RAISE EXCEPTION 'foreign account metadata exposed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'User is not an admin%' THEN RAISE; END IF;
  END;
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(v_bank,v_user,true);
  INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256) VALUES('test-permissions','festapp','43',v_bank,'9876/2010','FIO','api','shadow','abcdef0123',repeat('a',64)) RETURNING id INTO v_connection;
  v_result:=public.get_bank_sync_connection(v_bank);
  PERFORM assert_eq(v_result->>'receiving_address','abcdef0123@banksync.festapp.net','server owns receiving address');
  PERFORM public.activate_bank_sync_connection(v_connection,repeat('a',64));
  BEGIN
    PERFORM public.update_bank_account_token(v_bank,'synthetic-token',NULL);
    RAISE EXCEPTION 'old client restored token writer';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.regenerate_bank_account_pairing_code(v_bank);
    RAISE EXCEPTION 'old client restored email recipient';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.get_bank_account_secret(v_bank);
    RAISE EXCEPTION 'old client read migrated token';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_CANONICAL_CONNECTION_REQUIRED' THEN RAISE; END IF;
  END;
END;
$$;
