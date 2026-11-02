DO $$
DECLARE org bigint:=-971530; unit_id bigint:=-971530; bank bigint:=-971530; conn bigint;
 older bigint; newer bigint; before_state jsonb; before_health jsonb;
BEGIN
 INSERT INTO public.organizations(id,title) VALUES(org,'Observation order fixture');
 INSERT INTO public.units(id,title,organization) VALUES(unit_id,'Observation order unit',org);
 INSERT INTO eshop.bank_accounts(id,title,type,account_number) VALUES(bank,'Observation order bank','FIO','971530/2010');
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit_id,bank);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
  provider,mode,state,manifest_sha256,legacy_blocked_at,bank_pull_at)
 VALUES('observation-order','festapp','971530',bank,'971530/2010','FIO','api','connected',repeat('d',64),now(),now()-interval '1 hour') RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 older:=public.begin_bank_sync_observation(conn)::bigint;
 newer:=public.begin_bank_sync_observation(conn)::bigint;
 PERFORM assert_true(newer>older,'request start order is issued by database');
 PERFORM public.record_bank_sync_health(org,conn,now(),'fio_token_invalid_or_inactive',true,true,true,newer);
 UPDATE eshop.bank_sync_connections SET failure_since=now()-interval '12 minutes' WHERE id=conn;
 SELECT to_jsonb(c) INTO before_state FROM eshop.bank_sync_connections c WHERE id=conn;
 SELECT to_jsonb(h) INTO before_health FROM eshop.bank_sync_health h WHERE connection_id=conn;
 PERFORM assert_false(public.record_bank_sync_pull(conn,now()-interval '30 minutes',NULL,older),'late success is rejected');
 PERFORM public.record_bank_sync_health(org,conn,now()-interval '30 minutes',NULL,false,false,false,older);
 PERFORM assert_true((SELECT to_jsonb(c)=before_state FROM eshop.bank_sync_connections c WHERE id=conn),'late success preserves failure and its ten-minute clock');
 PERFORM assert_true((SELECT to_jsonb(h)=before_health FROM eshop.bank_sync_health h WHERE connection_id=conn),'late health response preserves configuration and notification incident');
 PERFORM assert_false(public.record_bank_sync_pull(conn,now(),NULL,newer),'one observation cannot be applied twice');
 -- Control completion must not overwrite a newer bank observation either.
 PERFORM public.update_bank_sync_connection_metadata(conn,NULL,NULL,'connected',older);
 PERFORM assert_true((SELECT state='degraded' FROM eshop.bank_sync_connections WHERE id=conn),'late control completion cannot erase newer degraded state');
 older:=public.begin_bank_sync_observation(conn)::bigint;
 newer:=public.begin_bank_sync_observation(conn)::bigint;
 PERFORM assert_true(public.record_bank_sync_pull(conn,now(),NULL,newer),'new success applies');
 SELECT to_jsonb(c) INTO before_state FROM eshop.bank_sync_connections c WHERE id=conn;
 PERFORM assert_false(public.record_bank_sync_pull(conn,NULL,'fio_token_invalid_or_inactive',older),'late failure is rejected after recovery');
 PERFORM assert_true((SELECT to_jsonb(c)=before_state FROM eshop.bank_sync_connections c WHERE id=conn),'late failure cannot recreate warning or outage clock');
 -- A newer observation containing an old success may not move bank history backwards.
 newer:=public.begin_bank_sync_observation(conn)::bigint;
 PERFORM public.record_bank_sync_pull(conn,now()-interval '30 minutes',NULL,newer);
 PERFORM assert_true((SELECT bank_pull_at=now() FROM eshop.bank_sync_connections WHERE id=conn),'last bank success never regresses');
 PERFORM assert_false(has_function_privilege('authenticated','public.begin_bank_sync_observation(bigint)','EXECUTE'),'clients cannot mint ordering tokens');
END $$;
