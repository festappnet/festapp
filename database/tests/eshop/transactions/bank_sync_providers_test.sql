DO $$
DECLARE v_code text; v_provider text; v_account bigint; v_user uuid; v_operation uuid; v_context jsonb; v_connection bigint;
BEGIN
  SELECT id INTO STRICT v_user FROM public.user_info LIMIT 1;
  FOR v_code,v_provider IN SELECT * FROM (VALUES
    ('2010','FIO'),('3030','AIRBANK'),('0300','CSOB'),('0600','MONETA'),
    ('2250','CREDITAS'),('5500','RAIFFEISENBANK'),('2700','UNICREDIT'),('0800','CSAS')
  ) AS providers(code,provider) LOOP
    PERFORM assert_eq(public.bank_sync_provider_for_account('123456/'||v_code),v_provider,'domestic provider');
    PERFORM assert_eq(public.bank_sync_provider_for_account('CZ12'||v_code||'0000000000000000'),v_provider,'IBAN provider');
    INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
      VALUES('Notification capability fixture','OTHER','123456/'||v_code,ARRAY['CZK']) RETURNING id INTO v_account;
    INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(v_account,v_user,true);
    PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
    v_operation:=gen_random_uuid();
    INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state)
      VALUES(v_operation,v_account,v_user,'create',repeat('a',64),'pending');
    PERFORM set_config('request.jwt.claim.role','service_role',true);
    v_context:=public.claim_bank_sync_operation(v_operation);
    PERFORM assert_eq(v_context->>'provider',v_provider,'operation resolves historical OTHER account');
    v_connection:=public.save_bank_sync_connection(v_operation,'capability-fixture',v_account::text,'123456'||v_code,'email');
    PERFORM assert_eq((SELECT provider FROM eshop.bank_sync_connections WHERE id=v_connection),v_provider,'connection accepts provider');
    PERFORM public.complete_bank_sync_operation(v_operation,'completed','{}',(v_context->>'lease_token')::uuid);
  END LOOP;
  PERFORM assert_true(public.bank_sync_provider_for_account('123456/0100') IS NULL,'unsupported bank stays unsupported');
END;
$$;
