DO $$
DECLARE org bigint:=-971520; unit_id bigint:=-971520; bank bigint:=-971520; conn bigint;
BEGIN
 INSERT INTO public.organizations(id,title) VALUES(org,'Warning grace fixture');
 INSERT INTO public.units(id,title,organization) VALUES(unit_id,'Warning grace unit',org);
 INSERT INTO eshop.bank_accounts(id,title,type,account_number) VALUES(bank,'Grace bank','FIO','971520/2010');
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit_id,bank);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
  provider,mode,state,manifest_sha256,legacy_blocked_at,bank_pull_at)
 VALUES('warning-grace','festapp','971520',bank,'971520/2010','FIO','api','connected',repeat('c',64),now(),now()-interval '1 minute') RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'one failed request must not show a warning triangle');
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '4 minutes' WHERE id=conn;
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'four minutes of failure must remain quiet');
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '9 minutes 59 seconds' WHERE id=conn;
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'warning does not appear before the full ten minutes');
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '10 minutes',failure_observed_at=now()-interval '6 minutes' WHERE id=conn;
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'aging a single observation does not confirm continuous failure');
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_eq(public.bank_sync_warning(bank)->>'code','token_invalid','confirmed ten minute failure shows warning');
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_temporarily_unavailable',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_eq(public.bank_sync_warning(bank)->>'code','temporary_failure','changing failure symptoms preserves the outage clock');
 PERFORM public.record_bank_sync_pull(conn,now(),NULL,public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'success immediately clears the warning');
 PERFORM assert_true((SELECT failure_since IS NULL AND failure_observed_at IS NULL FROM eshop.bank_sync_connections WHERE id=conn),'success resets durable failure evidence');
 PERFORM public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'new outage gets its own ten minute grace period');
 -- A success can occur in BankSync between two consumer observations, even if
 -- the most recent request failed again by the next status read.
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '20 minutes',failure_observed_at=now() WHERE id=conn;
 PERFORM public.record_bank_sync_pull(conn,now()+interval '1 second','fio_token_invalid_or_inactive',public.begin_bank_sync_observation(conn)::bigint);
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'new upstream success interrupts an apparently continuous outage');
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '20 minutes',failure_observed_at=now()-interval '11 minutes' WHERE id=conn;
 PERFORM assert_true(public.bank_sync_warning(bank) IS NULL,'expired failure observation does not create a warning');
 UPDATE eshop.bank_sync_connections SET state='suspended' WHERE id=conn;
 PERFORM assert_eq(public.bank_sync_warning(bank)->>'code','suspended','explicit pause remains visible');
END $$;
