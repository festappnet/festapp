DO $$
DECLARE v_bank bigint; v_user uuid; v_id uuid:=gen_random_uuid(); v_new uuid:=gen_random_uuid(); v_context jsonb; v_intent jsonb;
BEGIN
  SELECT id INTO v_user FROM public.user_info LIMIT 1;
  INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
    VALUES('BankSync recovery fixture','FIO','8888/2010',ARRAY['CZK']) RETURNING id INTO v_bank;
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(v_bank,v_user,true);
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  v_intent:=public.begin_bank_sync_operation(v_id,v_bank,'set_token',repeat('a',64));
  v_intent:=public.begin_bank_sync_operation(v_new,v_bank,'set_token',repeat('a',64));
  PERFORM assert_eq(v_intent->>'id',v_id::text,'new browser session resumes same durable intent');
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM public.stage_bank_sync_operation(v_id,repeat('a',64),
    jsonb_build_object('operation_id',v_id,'account_id',v_bank,'operation','set_token'),'{"version":"1","ciphertext":"synthetic-cipher"}'::jsonb);
  BEGIN
    PERFORM public.stage_bank_sync_operation(v_id,repeat('a',64),jsonb_build_object('operation_id',v_id,'token','plaintext'),NULL);
    RAISE EXCEPTION 'plaintext request accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_REQUEST_INVALID' THEN RAISE; END IF;
  END;
  v_context:=public.claim_bank_sync_operation(v_id);
  PERFORM assert_eq(v_context->'token_cipher'->>'ciphertext','synthetic-cipher','credential survives browser loss');
  BEGIN
    PERFORM public.complete_bank_sync_operation(v_id,'completed','{}',gen_random_uuid());
    RAISE EXCEPTION 'stale fence accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'BANK_SYNC_OPERATION_NOT_CLAIMED' THEN RAISE; END IF;
  END;
  PERFORM public.complete_bank_sync_operation(v_id,'uncertain',NULL,(v_context->>'lease_token')::uuid);
  UPDATE eshop.bank_sync_operations SET updated_at=now()-interval '6 minutes' WHERE id=v_id;
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.get_recoverable_bank_sync_operations() WHERE id=v_id),'background worker can discover interrupted intent');
  v_context:=public.claim_bank_sync_operation(v_id);
  PERFORM public.complete_bank_sync_operation(v_id,'completed','{}',(v_context->>'lease_token')::uuid);
  PERFORM assert_true((SELECT token_cipher IS NULL FROM eshop.bank_sync_operations WHERE id=v_id),'credential removed after completion');
  PERFORM assert_false(has_function_privilege('authenticated','public.stage_bank_sync_operation(uuid,text,jsonb,jsonb)','EXECUTE'),'user cannot persist privileged remote request');
  PERFORM assert_false(has_function_privilege('authenticated','public.get_recoverable_bank_sync_operations()','EXECUTE'),'user cannot read recovery ciphertext');
END;
$$;
