BEGIN;

DO $$
DECLARE
  v_login text := 'image_delete_' || gen_random_uuid();
  v_user uuid;
  v_occasion_allowed bigint;
  v_occasion_denied bigint;
  v_allowed text := 'https://img.festapp.net/images/101/allowed.jpg';
  v_denied text := 'https://img.festapp.net/images/102/denied.jpg';
  v_rejected boolean := false;
BEGIN
  PERFORM create_user_for_test(v_login, gen_random_uuid() || '@test.local');
  v_user := get_user_id(v_login);
  INSERT INTO public.occasions(title,link,start_time,end_time,is_open)
  VALUES ('Allowed images',gen_random_uuid()::text,now(),now()+interval '1 day',true)
  RETURNING id INTO v_occasion_allowed;
  INSERT INTO public.occasions(title,link,start_time,end_time,is_open)
  VALUES ('Denied images',gen_random_uuid()::text,now(),now()+interval '1 day',true)
  RETURNING id INTO v_occasion_denied;
  INSERT INTO public.occasion_users(occasion,"user",is_editor,is_approved)
  VALUES (v_occasion_allowed,v_user,true,true);
  INSERT INTO public.images(link,occasion) VALUES
    (v_allowed,v_occasion_allowed),(v_denied,v_occasion_denied);

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);

  PERFORM assert_eq(
    (SELECT link FROM public.authorize_image_deletion(ARRAY[v_allowed])),
    v_allowed,
    'an editor can authorize the exact stored link');

  BEGIN
    PERFORM public.authorize_image_deletion(ARRAY[v_allowed,v_denied]);
  EXCEPTION WHEN insufficient_privilege THEN
    v_rejected := true;
  END;
  PERFORM assert_true(v_rejected, 'a mixed-owner batch is rejected all-or-nothing');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.images WHERE link=v_allowed),
    'authorization never mutates an allowed image record');
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.images WHERE link=v_denied),
    'authorization never mutates a denied image record');
  PERFORM assert_true(has_function_privilege('authenticated',
    'public.authorize_image_deletion(text[])','EXECUTE'),
    'authenticated can invoke deletion authorization');
  PERFORM assert_true(NOT has_function_privilege('anon',
    'public.authorize_image_deletion(text[])','EXECUTE'),
    'anonymous cannot invoke deletion authorization');
END $$;

ROLLBACK;
