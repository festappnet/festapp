-- Transaction-local public metadata fixtures; no email or external dispatch.
BEGIN;
DO $$
DECLARE org bigint; un bigint; occ bigint; fid bigint; sample record;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Timezone regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Timezone regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Timezone regression',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,link) VALUES(occ,gen_random_uuid()::text) RETURNING id INTO fid;
 FOR sample IN SELECT * FROM (VALUES
  (NULL::text,NULL::text,NULL::text,'Europe/Prague'),
  ('Europe/Prague','Europe/London','America/New_York','Europe/Prague'),
  (NULL,'Europe/London','America/New_York','Europe/London'),
  (NULL,NULL,'America/New_York','America/New_York'),
  ('invalid/zone','Europe/London','America/New_York','Europe/London'),
  ('','Europe/London','America/New_York','Europe/London'),
  ('invalid/zone','invalid/unit','America/New_York','America/New_York'),
  ('invalid/zone','invalid/unit','invalid/organization','Europe/Prague'),
  ('europe/prague','Europe/London','America/New_York','Europe/London'),
  (' Europe/Prague','Europe/London','America/New_York','Europe/London'),
  ('GMT+1','Europe/London','America/New_York','Europe/London'),
  ('US/Eastern','Europe/London','America/New_York','US/Eastern'),
  ('CET','Europe/London','America/New_York','CET'),
  ('Europe/London','Europe/London','Europe/London','Europe/London')
 ) AS cases(occasion_zone,unit_zone,organization_zone,expected) LOOP
  UPDATE public.occasions SET data=jsonb_build_object('timezone',sample.occasion_zone) WHERE id=occ;
  UPDATE public.units SET data=jsonb_build_object('timezone',sample.unit_zone) WHERE id=un;
  UPDATE public.organizations SET data=jsonb_build_object('timezone',sample.organization_zone) WHERE id=org;
  PERFORM assert_eq(public.get_waitlist_form_timezone_internal(fid),sample.expected,
   'timezone priority and exact catalog validation: '||row_to_json(sample)::text);
 END LOOP;
 PERFORM assert_true(public.get_waitlist_form_timezone_internal(-1) IS NULL,'unknown form does not manufacture a timezone');
 PERFORM assert_true(NOT has_function_privilege('anon','public.get_waitlist_form_timezone_internal(bigint)','EXECUTE'),'timezone helper remains private');
 PERFORM assert_true(NOT has_function_privilege('authenticated','public.get_waitlist_form_timezone_internal(bigint)','EXECUTE'),'authenticated clients cannot bypass the public projection');
END $$;
ROLLBACK;
