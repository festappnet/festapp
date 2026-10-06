BEGIN;

DO $$
DECLARE
  v_user uuid;
  v_organization bigint;
  v_unit bigint;
  v_occasion bigint;
  v_command uuid := gen_random_uuid();
  v_hash text := repeat('a', 64);
  v_result jsonb;
  v_task jsonb;
  v_order bigint;
  v_rejected boolean := false;
BEGIN
  PERFORM create_user_for_test('client_sync_runtime', 'client_sync_runtime@test.local');
  v_user := get_user_id('client_sync_runtime');
  SELECT id INTO v_organization FROM public.organizations ORDER BY id LIMIT 1;
  SELECT id INTO v_unit FROM public.units WHERE organization=v_organization ORDER BY id LIMIT 1;
  INSERT INTO public.occasions(
    organization,unit,title,link,start_time,end_time,is_open
  ) VALUES (
    v_organization,v_unit,'Client sync runtime contract',gen_random_uuid()::text,
    now(),now()+interval '1 day',true
  ) RETURNING id INTO v_occasion;

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  v_result:=public.begin_client_mutation_v1(
    v_command,'runtime.contract',v_occasion,v_user,v_hash);
  PERFORM assert_eq(v_result->>'disposition','claimed','first command claim succeeds');

  v_result:=public.complete_client_mutation_outcome_v1(
    v_command,'unchanged',200,jsonb_build_object('value','stable'));
  PERFORM assert_eq(v_result->>'status','unchanged','terminal response is stored');

  v_result:=public.begin_client_mutation_v1(
    v_command,'runtime.contract',v_occasion,v_user,v_hash);
  PERFORM assert_eq(v_result->>'disposition','replay','completed command replays');
  PERFORM assert_eq(v_result#>>'{response,data,value}','stable','replay is exact');

  BEGIN
    PERFORM public.begin_client_mutation_v1(
      v_command,'runtime.contract',v_occasion,v_user,repeat('b',64));
  EXCEPTION WHEN invalid_parameter_value THEN
    v_rejected:=true;
  END;
  PERFORM assert_true(v_rejected,'command id cannot be reused for another request');
  PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts
    WHERE command_id=v_command),1::bigint,'one command produces one receipt');

  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion,state,data,price,currency_code) VALUES(public.next_order_sequence(v_occasion), public.generate_order_symbol(), v_occasion,'ordered','{"email":"fixture@example.invalid"}',1,'CZK') RETURNING id INTO v_order;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    v_command,v_occasion,jsonb_build_object('order',jsonb_build_object('id',v_order)),'cs');
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    v_command,v_occasion,jsonb_build_object('order',jsonb_build_object('id',v_order)),'cs');
  PERFORM assert_eq((SELECT count(*) FROM public.email_messages
    WHERE code='TICKET_ORDER_CONFIRMATION' AND data->>'command_id'=v_command::text),
    1::bigint,'confirmation enqueue is idempotent by command id');

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  UPDATE public.email_capacity SET paused=false,quota_at=now(),max_rate=1,daily_quota=100,provider_sent_24h=0,shared_account=false,worker_url=NULL;
  v_task:=public.claim_email();
  PERFORM assert_eq((v_task->>'attempt_count')::int,0,'preparation claim is not a provider attempt');
  PERFORM assert_true(v_task->>'lease_token' IS NOT NULL,'worker claim is fenced');
  PERFORM public.finish_email_attempt((v_task->>'attempt_id')::uuid,(v_task->>'lease_token')::uuid,'preparation_failed',NULL,'runtime_retry');
  UPDATE public.email_messages SET target_time=now() WHERE message_id=(v_task->>'message_id')::uuid;
  v_task:=public.claim_email();
  PERFORM assert_eq((v_task->>'attempt_count')::int,1,'known preparation failure may be reclaimed');

END $$;

ROLLBACK;
