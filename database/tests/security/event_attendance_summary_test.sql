BEGIN;
DO $$
DECLARE
  org bigint; unit_id bigint; occ bigint; ev bigint; empty_ev bigint; private_ev bigint; role_id bigint;
  owner_id uuid := gen_random_uuid(); other_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Attendance privacy') RETURNING id INTO org;
  INSERT INTO public.units(title, organization) VALUES ('Attendance privacy', org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(title, link, organization, unit, start_time, end_time)
    VALUES ('Attendance privacy', gen_random_uuid()::text, org, unit_id, now(), now()+interval '1 day') RETURNING id INTO occ;
  INSERT INTO auth.users(id,email) VALUES (owner_id,owner_id||'@test.invalid'),(other_id,other_id||'@test.invalid');
  INSERT INTO public.user_info(id,organization) VALUES(owner_id,org),(other_id,org);
  INSERT INTO public.events(title,occasion,start_time,end_time)
    VALUES ('Populated',occ,now(),now()+interval '1 hour') RETURNING id INTO ev;
  INSERT INTO public.events(title,occasion,start_time,end_time)
    VALUES ('Empty',occ,now(),now()+interval '1 hour') RETURNING id INTO empty_ev;
  INSERT INTO public.events(title,occasion,start_time,end_time)
    VALUES ('Restricted',occ,now(),now()+interval '1 hour') RETURNING id INTO private_ev;
  INSERT INTO public.role_info(title,occasion) VALUES('Restricted role',occ) RETURNING id INTO role_id;
  INSERT INTO public.event_roles(event,role) VALUES(private_ev,role_id);
  INSERT INTO public.event_users(event,"user") VALUES(ev,owner_id),(ev,other_id);
  PERFORM set_config('test.attendance_summary',jsonb_build_object('event',ev,'empty',empty_ev,'private',private_ev,'owner',owner_id)::text,true);
END $$;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true);
DO $$
DECLARE x jsonb := current_setting('test.attendance_summary')::jsonb; rows jsonb;
BEGIN
  SELECT jsonb_agg(to_jsonb(s)) INTO rows
    FROM public.get_event_attendance_summary(ARRAY[(x->>'event')::bigint,(x->>'empty')::bigint,(x->>'private')::bigint]) s;
  IF jsonb_array_length(rows) <> 2 THEN RAISE EXCEPTION 'Visibility filter failed'; END IF;
  IF NOT rows @> jsonb_build_array(jsonb_build_object('event',(x->>'event')::bigint,'participant_count',2,'is_signed_in',false))
    THEN RAISE EXCEPTION 'Anonymous aggregate incorrect'; END IF;
  IF NOT rows @> jsonb_build_array(jsonb_build_object('event',(x->>'empty')::bigint,'participant_count',0,'is_signed_in',false))
    THEN RAISE EXCEPTION 'Empty event missing'; END IF;
  IF rows::text LIKE '%'||(x->>'owner')||'%' THEN RAISE EXCEPTION 'Participant UUID leaked'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_event_attendance_summary('{}'::bigint[])) THEN RAISE EXCEPTION 'Empty request not empty'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',current_setting('test.attendance_summary')::jsonb->>'owner',true),set_config('request.jwt.claim.role','authenticated',true);
DO $$
DECLARE x jsonb := current_setting('test.attendance_summary')::jsonb; s record;
BEGIN
  SELECT * INTO s FROM public.get_event_attendance_summary(ARRAY[(x->>'event')::bigint]);
  IF s.participant_count <> 2 OR s.is_signed_in IS DISTINCT FROM true THEN RAISE EXCEPTION 'Owner state incorrect'; END IF;
END $$;
RESET ROLE;
-- Exercise the eventual privacy cutover in rollback only. Aggregate counts
-- must stay correct after table rows are limited to the authenticated owner.
DROP POLICY IF EXISTS "Enable read for all" ON public.event_users;
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true);
DO $$
DECLARE x jsonb := current_setting('test.attendance_summary')::jsonb; n bigint;
BEGIN
  IF EXISTS(SELECT 1 FROM public.event_users WHERE event=(x->>'event')::bigint) THEN RAISE EXCEPTION 'Public UUID rows still visible'; END IF;
  SELECT participant_count INTO n FROM public.get_event_attendance_summary(ARRAY[(x->>'event')::bigint]);
  IF n IS DISTINCT FROM 2::bigint THEN RAISE EXCEPTION 'Aggregate broke after cutover'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
