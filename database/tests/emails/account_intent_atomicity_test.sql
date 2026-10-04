DO $$ DECLARE u uuid;old_token uuid:=gen_random_uuid();new_token uuid:=gen_random_uuid();r jsonb;r2 jsonb;BEGIN
 PERFORM create_user_for_test('email_atomic','atomic@example.invalid');u:=get_user_id('email_atomic');
 INSERT INTO public.user_reset_token("user",token,created_at) VALUES(u,old_token,now());
 BEGIN
  PERFORM public.enqueue_account_email('reset_token',jsonb_build_object('user_id',u,'token',new_token),'{"organization":1}','invalid-recipient','{"v":"1"}',repeat('a',64),'atomic-rollback','RESET_PASSWORD',now()+interval '1 hour');
  RAISE EXCEPTION 'invalid enqueue succeeded';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'invalid_email_intent' THEN RAISE;END IF;END;
 PERFORM assert_eq((SELECT token::text FROM public.user_reset_token WHERE "user"=u),old_token::text,'failed enqueue rolls back proof rotation');
 r:=public.enqueue_account_email('reset_token',jsonb_build_object('user_id',u,'token',new_token),'{"organization":1}','atomic@example.invalid','{"v":"1"}',repeat('a',64),'atomic-first','RESET_PASSWORD',now()+interval '1 hour');
 UPDATE public.email_messages SET workflow_state='unknown' WHERE message_id=(r->>'message_id')::uuid;
 r2:=public.enqueue_account_email('reset_token',jsonb_build_object('user_id',u,'token',gen_random_uuid()),'{"organization":1}','atomic@example.invalid','{"v":"1"}',repeat('b',64),'old-client-timeout-next-window','RESET_PASSWORD',now()+interval '1 hour');
 PERFORM assert_eq(r->>'message_id',r2->>'message_id','old client retry joins unresolved message across request windows');
 PERFORM assert_eq((SELECT token::text FROM public.user_reset_token WHERE "user"=u),new_token::text,'unknown send does not invalidate original proof');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz)','EXECUTE'),'account atomic producer remains internal');
END $$;
