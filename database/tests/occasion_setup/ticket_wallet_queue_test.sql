DO $$
DECLARE other_org bigint; org bigint; tid bigint:=-987654321; q jsonb; before_version bigint; caught boolean:=false;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Queue fixture') RETURNING id INTO org;
 INSERT INTO eshop.ticket_wallet_integrations(organization,issuer,environment,web_origin) VALUES(org,'1234','queue','https://queue.invalid');
 INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
 VALUES(tid,org,-1,'1234','queue','1234.queue-object','1234.queue-class');
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[tid,tid]);
 PERFORM assert_eq((SELECT count(*)::int FROM eshop.ticket_wallet_work WHERE ticket_id=tid),1,'deduplicated work row');
 SELECT requested INTO before_version FROM eshop.ticket_wallet_work WHERE ticket_id=tid;
 BEGIN
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[tid]);
  RAISE EXCEPTION 'rollback fixture';
 EXCEPTION WHEN raise_exception THEN NULL; END;
 PERFORM assert_eq((SELECT requested FROM eshop.ticket_wallet_work WHERE ticket_id=tid),before_version,'enqueue rolls back with producer');
 q:=public.claim_ticket_wallet(tid);
 PERFORM assert_eq(q#>>'{projection,state}','INACTIVE','deleted identity remains invalidatable');
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[tid]);
 PERFORM assert_true(public.finish_ticket_wallet(tid,(q->>'lease')::uuid,true),'first version ack');
 PERFORM assert_true((SELECT requested>applied FROM eshop.ticket_wallet_work WHERE ticket_id=tid),'newer request survives ack');
 q:=public.claim_ticket_wallet(tid);
 UPDATE eshop.ticket_wallet_work SET lease_until=clock_timestamp()-interval '1 second' WHERE ticket_id=tid;
 PERFORM assert_true(NOT public.finish_ticket_wallet(tid,(q->>'lease')::uuid,true),'expired ack rejected');
 q:=public.claim_ticket_wallet(tid);
 PERFORM assert_true(q IS NOT NULL,'expired work reclaimed');
 PERFORM public.finish_ticket_wallet(tid,(q->>'lease')::uuid,false);
 PERFORM assert_true(public.claim_ticket_wallet(tid) IS NULL,'retry obeys backoff');
 UPDATE eshop.ticket_wallet_work SET due_at=now() WHERE ticket_id=tid;
 PERFORM public.pause_ticket_wallet(org,true);
 PERFORM assert_true(public.claim_ticket_wallet(tid) IS NULL,'paused background cannot claim');
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[tid]);
 PERFORM public.pause_ticket_wallet(org,false);
 q:=public.claim_ticket_wallet(tid);
 PERFORM public.finish_ticket_wallet(tid,(q->>'lease')::uuid,true);
 PERFORM assert_true(public.claim_ticket_wallet(tid) IS NULL,'idle work does not poll');
 UPDATE eshop.ticket_wallet_work SET boundary_at=now()-interval '1 second' WHERE ticket_id=tid;
 PERFORM public.maintain_ticket_wallet(100);
 PERFORM assert_true((SELECT requested>applied FROM eshop.ticket_wallet_work WHERE kind='object' AND ticket_id=tid),'time boundary schedules without edit');
 PERFORM assert_true(NOT has_table_privilege('authenticated','eshop.ticket_wallet_work','SELECT'),'work RLS private');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.enqueue_ticket_wallet_internal(bigint[])','EXECUTE'),'clients cannot enqueue');
 PERFORM assert_true(NOT has_function_privilege('anon','public.pause_ticket_wallet(bigint,boolean)','EXECUTE'),'pause service only');
 -- A new tenant receives a turn even when an older tenant has dirty scope work.
 INSERT INTO public.organizations(title) VALUES('Other queue tenant') RETURNING id INTO other_org;
 INSERT INTO eshop.ticket_wallet_integrations(organization,issuer,environment,web_origin) VALUES(other_org,'1234','queue','https://other.invalid');
 INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
 VALUES(tid-1,other_org,-2,'1234','queue','1234.other-queue','1234.other-class');
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[tid-1]);
 q:=public.claim_ticket_wallet();
 PERFORM assert_eq((q->>'organization')::bigint,other_org,'new tenant gets a fair claim turn');
END $$;
