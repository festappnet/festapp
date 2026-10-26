BEGIN;

DO $$
DECLARE
  v_login text := 'saved_program_' || gen_random_uuid();
  v_user uuid;
  v_occasion_a bigint;
  v_occasion_b bigint;
  v_event_a bigint;
  v_event_b bigint;
  v_saved bigint[];
  v_cross_scope_rejected boolean := false;
BEGIN
  PERFORM create_user_for_test(v_login, gen_random_uuid() || '@test.local');
  v_user := get_user_id(v_login);

  INSERT INTO public.occasions(title,link,start_time,end_time,is_open)
  VALUES ('Saved program A',gen_random_uuid()::text,now(),now()+interval '1 day',true)
  RETURNING id INTO v_occasion_a;
  INSERT INTO public.occasions(title,link,start_time,end_time,is_open)
  VALUES ('Saved program B',gen_random_uuid()::text,now(),now()+interval '1 day',true)
  RETURNING id INTO v_occasion_b;
  INSERT INTO public.events(occasion,title,start_time,end_time)
  VALUES (v_occasion_a,'Event A',now(),now()+interval '1 hour')
  RETURNING id INTO v_event_a;
  INSERT INTO public.events(occasion,title,start_time,end_time)
  VALUES (v_occasion_b,'Event B',now(),now()+interval '1 hour')
  RETURNING id INTO v_event_b;
  INSERT INTO public.occasion_users(occasion,"user",is_approved)
  VALUES (v_occasion_a,v_user,true),(v_occasion_b,v_user,true);

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);

  v_saved := public.set_saved_program(v_occasion_a,ARRAY[v_event_a],'join');
  PERFORM assert_true(v_saved = ARRAY[v_event_a],
    'join returns the authoritative occasion-scoped program');
  PERFORM public.set_saved_program(v_occasion_b,ARRAY[v_event_b],'join');
  v_saved := public.set_saved_program(v_occasion_a,'{}','replace');
  PERFORM assert_true(cardinality(v_saved) = 0,
    'replace can clear the selected occasion');
  PERFORM assert_true(EXISTS(
    SELECT 1 FROM public.event_users_saved
    WHERE "user"=v_user AND event=v_event_b
  ), 'replace never deletes another occasion program');

  BEGIN
    PERFORM public.set_saved_program(v_occasion_a,ARRAY[v_event_b],'join');
  EXCEPTION WHEN invalid_parameter_value THEN
    v_cross_scope_rejected := true;
  END;
  PERFORM assert_true(v_cross_scope_rejected,
    'cross-occasion event IDs are rejected atomically');

  PERFORM assert_true(has_function_privilege('authenticated',
    'public.set_saved_program(bigint,bigint[],text)','EXECUTE'),
    'authenticated users can mutate their own program');
  PERFORM assert_true(NOT has_function_privilege('anon',
    'public.set_saved_program(bigint,bigint[],text)','EXECUTE'),
    'anonymous users cannot invoke the server mutation');
END $$;

ROLLBACK;
