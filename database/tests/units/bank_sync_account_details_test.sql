-- Run transactionally: local details and recoverable remote intent are inseparable.
DO $$
DECLARE u uuid; a bigint; op uuid; old_title text;
BEGIN
 SELECT id INTO u FROM public.user_info LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 INSERT INTO eshop.bank_accounts(account_number,title,type) VALUES('CZ6508000000192000145399','Original','FIO') RETURNING id INTO a;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(a,u,true);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,provider,mode,state,manifest_sha256)
 VALUES('details-test','festapp','987654321',a,'CZ6508000000192000145399','FIO','api','connected',repeat('a',64));
 PERFORM public.update_bank_account(a,'CZ6508000000192000145399','Renamed','FIO',ARRAY['CZK'],NULL,NULL,'Beneficiary');
 SELECT id INTO op FROM eshop.bank_sync_operations WHERE bank_account_id=a AND operation='update_details' AND state='pending' AND request->>'operation_id'=id::text;
 IF op IS NULL OR (SELECT title FROM eshop.bank_accounts WHERE id=a)<>'Renamed' THEN RAISE EXCEPTION 'details and intent must commit together'; END IF;
 BEGIN
  PERFORM public.update_bank_account(a,'CZ6508000000192000145399','Must roll back','FIO');
  RAISE EXCEPTION 'expected operation fence';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 IF (SELECT title FROM eshop.bank_accounts WHERE id=a)<>'Renamed' THEN RAISE EXCEPTION 'busy update changed local data'; END IF;
 UPDATE eshop.bank_sync_operations SET state='completed' WHERE id=op;
 BEGIN
  PERFORM public.update_bank_account(a,'CZ5808000000192000145398','Wrong account','FIO');
  RAISE EXCEPTION 'expected immutable identity';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN
  PERFORM public.update_bank_account(a,'CZ6508000000192000145399','Unauthorized','FIO');
  RAISE EXCEPTION 'expected admin permission denial';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'Permission denied: Only bank account admins can update details.' THEN RAISE; END IF;
 END;
 RAISE NOTICE 'BankSync account details atomicity, fencing and authorization passed';
END $$;
