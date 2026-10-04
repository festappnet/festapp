BEGIN;
DO $$
DECLARE org bigint; context jsonb; first_msg jsonb; second_msg jsonb; light_msg jsonb; claimed jsonb; begun jsonb; token uuid; attempt uuid; second_attempt uuid; second_token uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Preparation/outage contract') RETURNING id INTO org;
 context:=jsonb_build_object('organization',org);
 UPDATE public.email_messages SET workflow_state='cancelled';
 UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=1,daily_quota=100,provider_sent_24h=0,worker_url=NULL,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL;
 first_msg:=public.enqueue_email('custom',context,'first@example.invalid','{}','heavy-one');
 claimed:=public.claim_email();token:=(claimed->>'lease_token')::uuid;attempt:=(claimed->>'attempt_id')::uuid;
 PERFORM public.renew_email_preparation((first_msg->>'message_id')::uuid,token);
 BEGIN PERFORM public.renew_email_preparation((first_msg->>'message_id')::uuid,extensions.gen_random_uuid()); RAISE EXCEPTION 'stale renewal allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'stale_email_preparation' THEN RAISE; END IF; END;
 second_msg:=public.enqueue_email('custom',context,'second@example.invalid','{}','heavy-two');
 PERFORM assert_true(public.claim_email() IS NULL,'heavy work leaves one preparation slot reserved');
 light_msg:=public.enqueue_prepared_email('sign_in',context,'auth@example.invalid','{"sealed":"fixture"}','light-auth','content-auth','',now()+interval '1 minute');
 claimed:=public.claim_email();
 PERFORM assert_eq(claimed->>'message_id',light_msg->>'message_id','auth can use reserved lightweight slot');
 UPDATE public.email_messages SET workflow_state='cancelled' WHERE message_id<>(first_msg->>'message_id')::uuid;
 PERFORM public.prepare_email((first_msg->>'message_id')::uuid,token,'{"sealed":"fixture"}');
 begun:=public.begin_email_send(attempt,token);
 PERFORM assert_eq(begun->>'disposition','send','first attempt begins');
 PERFORM public.finish_email_attempt(attempt,token,'unknown',NULL,'provider_ambiguous');
 PERFORM assert_true((SELECT circuit_until>now() AND provider_outage_streak=1 FROM public.email_capacity),'uncertain provider transport opens global outage circuit');
 PERFORM assert_eq(public.get_internal_email_state((first_msg->>'message_id')::uuid),'unknown','outage never retries uncertain original');
 -- One new intent may probe after cooldown; its own fenced attempt is never the unknown original.
 UPDATE public.email_capacity SET circuit_until=now()-interval '1 second',next_send_at=now();
 light_msg:=public.enqueue_prepared_email('sign_in',context,'probe@example.invalid','{"sealed":"fixture"}','outage-probe','probe-content','',now()+interval '1 minute');
 claimed:=public.claim_email();token:=(claimed->>'lease_token')::uuid;attempt:=(claimed->>'attempt_id')::uuid;
 begun:=public.begin_email_send(attempt,token);
 PERFORM assert_eq(begun->>'disposition','send','one bounded new-message probe begins');
 PERFORM assert_true((SELECT probe_until>now() FROM public.email_capacity),'probe fences other provider starts');
 PERFORM public.finish_email_attempt(attempt,token,'accepted','probe-provider-id');
 PERFORM assert_true((SELECT provider_outage_streak=0 AND probe_until IS NULL FROM public.email_capacity),'successful API probe clears outage');
 -- A success already in flight cannot clear another attempt's newer throttle circuit.
 UPDATE public.email_capacity SET next_send_at=now(),circuit_until=NULL;
 light_msg:=public.enqueue_prepared_email('sign_in',context,'concurrent-a@example.invalid','{"sealed":"fixture"}','concurrent-a','content-a','',now()+interval '1 minute');
 claimed:=public.claim_email();attempt:=(claimed->>'attempt_id')::uuid;token:=(claimed->>'lease_token')::uuid;
 PERFORM public.begin_email_send(attempt,token);
 UPDATE public.email_capacity SET next_send_at=now();
 light_msg:=public.enqueue_prepared_email('sign_in',context,'concurrent-b@example.invalid','{"sealed":"fixture"}','concurrent-b','content-b','',now()+interval '1 minute');
 claimed:=public.claim_email();second_attempt:=(claimed->>'attempt_id')::uuid;second_token:=(claimed->>'lease_token')::uuid;
 PERFORM public.begin_email_send(second_attempt,second_token);
 PERFORM public.finish_email_attempt(attempt,token,'retry',NULL,'throttled');
 PERFORM public.finish_email_attempt(second_attempt,second_token,'accepted','concurrent-provider-id');
 PERFORM assert_true((SELECT circuit_until>now() FROM public.email_capacity),'older concurrent success preserves newer throttle backoff');

END $$;
ROLLBACK;
