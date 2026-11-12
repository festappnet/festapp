BEGIN;

DO $$
DECLARE
  v_user uuid;
  v_login text := 'account_deletion_' || gen_random_uuid();
  v_email text := gen_random_uuid() || '@test.local';
  v_hash text := encode(digest(gen_random_uuid()::text, 'sha256'), 'hex');
  v_request uuid;
  v_occasion bigint;
  v_event bigint;
  v_result jsonb; v_collecting uuid; v_queued uuid; v_digest uuid;
BEGIN
  -- This is a real disposable identity in auth.users plus public.user_info.
  PERFORM create_user_for_test(v_login, v_email);
  v_user := get_user_id(v_login);
  UPDATE public.user_info SET organization=1, email_readonly=v_email WHERE id=v_user;

  INSERT INTO public.occasions(title,link,start_time,end_time,is_open)
  VALUES ('Deletion fixture',gen_random_uuid()::text,now(),now()+interval '1 day',true)
  RETURNING id INTO v_occasion;
  INSERT INTO public.events(occasion,title,start_time,end_time)
  VALUES (v_occasion,'Seeded registration',now(),now()+interval '1 hour')
  RETURNING id INTO v_event;
  INSERT INTO public.organization_users("user",organization) VALUES(v_user,1);
  INSERT INTO public.occasion_users(occasion,"user",is_approved) VALUES(v_occasion,v_user,true);
  INSERT INTO public.event_users(event,"user") VALUES(v_event,v_user);
  INSERT INTO public.event_users_saved(event,"user") VALUES(v_event,v_user);
  INSERT INTO public.event_feedback(event,occasion,"user",rating,note)
  VALUES(v_event,v_occasion,v_user,'happy','Disposable seeded feedback');
  INSERT INTO public.news(occasion,message,created_by)
  VALUES(v_occasion,'Authored content retained without author',v_user);
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id)
  VALUES('private_profile',v_occasion,v_user);


  INSERT INTO public.notification_center_email_profiles(recipient,stopped) VALUES(v_user,false);
  INSERT INTO public.notification_center_email_subscriptions(recipient,organization) VALUES(v_user,1);
  INSERT INTO public.notification_center_email_dispatches(recipient,opened_at,due_at) VALUES(v_user,now(),now()+interval '300 seconds') RETURNING id INTO v_queued;
  v_result:=public.enqueue_email('admin_notification_digest',jsonb_build_object('recipient_user',v_user),lower(v_email),
    jsonb_build_object('dispatchId',v_queued,'templateVersion',1),'notification:'||v_queued,'ADMIN_NOTIFICATION_DIGEST');
  v_digest:=(v_result->>'message_id')::uuid;
  UPDATE public.notification_center_email_dispatches SET state='queued',message_id=v_digest WHERE id=v_queued;
  UPDATE public.email_messages SET workflow_state='unknown',prepared='{"historical":"retain-audit"}' WHERE message_id=v_digest;
  INSERT INTO public.notification_center_email_dispatches(recipient,opened_at,due_at) VALUES(v_user,now(),now()+interval '300 seconds') RETURNING id INTO v_collecting;
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.create_account_deletion_request(uuid,bigint,text,timestamptz,text)','EXECUTE'),
    'client cannot create deletion jobs directly');
  PERFORM assert_true(NOT has_function_privilege('authenticated',
    'public.get_account_deletion_asset_batch(uuid,integer)','EXECUTE'),
    'client cannot inventory another account assets');
  PERFORM assert_true(has_function_privilege('anon',
    'public.inspect_account_deletion_token(text)','EXECUTE'),
    'public confirmation page can inspect opaque tokens');

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  v_result := public.create_account_deletion_request(
    v_user,1,v_hash,clock_timestamp()+interval '24 hours','a***@test.local');
  v_request := (v_result->>'requestId')::uuid;
  PERFORM public.set_account_deletion_email_state(v_request,true);

  v_result := public.inspect_account_deletion_token(v_hash);
  PERFORM assert_eq(v_result->>'status','valid','GET inspection is valid');
  PERFORM assert_true(EXISTS(SELECT 1 FROM auth.users WHERE id=v_user),
    'GET inspection has no deletion side effect');

  v_result := public.claim_account_deletion(v_hash);
  PERFORM assert_eq(v_result->>'status','processing','explicit POST claim starts deletion');
  PERFORM assert_eq(v_result->>'userId',v_user::text,'claim derives seeded user from token');
  PERFORM assert_eq(v_result->>'completionEmail',lower(v_email),
    'claim preserves the delivery address before transactional profile cleanup');
  v_result := public.claim_account_deletion(v_hash);
  PERFORM assert_eq(v_result->>'status','processing','concurrent/replayed claim resumes one job');

  PERFORM public.cleanup_account_deletion_domain(v_request);

  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles WHERE recipient=v_user),'account deletion removes recipient scheduling');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches WHERE id=v_collecting),'empty collecting envelope is removed');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages WHERE message_id=v_digest AND workflow_state='unknown' AND prepared->>'historical'='retain-audit'),'unknown queue audit is retained without an account-deletion FK cycle');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=v_user),
    'public profile is deleted');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_users WHERE "user"=v_user),
    'seeded event registration is deleted');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_users_saved WHERE "user"=v_user),
    'seeded saved schedule is deleted');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.event_feedback WHERE "user"=v_user),
    'seeded event feedback is deleted');
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM public.client_sync_private_scopes WHERE user_id=v_user),
    'seeded private sync state is deleted');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.news WHERE occasion=v_occasion AND created_by IS NULL),
    'retained authored content is de-identified');

  -- Supabase Admin owns this step in production. The transactional test removes
  -- the actual disposable auth row to prove the complete terminal lifecycle.
  DELETE FROM auth.users WHERE id=v_user;
  UPDATE public.canonical_asset_cutover SET active=true,inventory_sha256=repeat('0',64);
  PERFORM public.get_account_deletion_asset_batch(v_request);
  PERFORM public.update_account_deletion_job(v_request,true,true,NULL);
  PERFORM assert_true(NOT EXISTS(SELECT 1 FROM auth.users WHERE id=v_user),
    'disposable auth identity is hard-deleted');
  PERFORM assert_true((SELECT user_id IS NULL FROM public.account_deletion_requests WHERE id=v_request),
    'terminal workflow retains no user identifier');
  v_result := public.claim_account_deletion(v_hash);
  PERFORM assert_eq(v_result->>'status','already_completed','token replay is harmless');
END $$;

ROLLBACK;
