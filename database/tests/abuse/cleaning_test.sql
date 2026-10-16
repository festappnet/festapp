DO $$
DECLARE actor uuid; org bigint; un bigint; occ bigint; wc bigint; result jsonb; old_data jsonb;
BEGIN
 PERFORM create_user_for_test('cleaning-abuse','cleaning-abuse@example.invalid');actor:=get_user_id('cleaning-abuse');
 INSERT INTO public.organizations(title) VALUES('Cleaning abuse fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Cleaning abuse Unit',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time,features)
 VALUES('Cleaning abuse fixture',gen_random_uuid()::text,org,un,now(),now()+interval '1 day','[{"code":"cleaning","is_enabled":true}]') RETURNING id INTO occ;
 INSERT INTO public.places(title,occasion,type) VALUES('WC',occ,'toilet') RETURNING id INTO wc;
 INSERT INTO public.occasion_users(occasion,"user",is_approved) VALUES(occ,actor,true);
 UPDATE public.abuse_policy_rules SET base_limit=2 WHERE rule_key='cleaning.report.actor';
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_eq(public.report_cleaning_issue(wc,'paper','First')->>'code','200','legitimate report succeeds');
 result:=public.report_cleaning_issue(wc,'paper','Second');
 PERFORM assert_eq(result#>>'{data,duplicate}','true','duplicate appends once to the existing report');
 PERFORM assert_eq(public.report_cleaning_issue(wc,'paper','Third')->>'code','429','duplicate notes share the work budget');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.cleaning_reports WHERE occasion=occ),1::bigint,'duplicate cannot create extra reports');
 DELETE FROM public.cleaning_reports WHERE occasion=occ;
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_eq(public.report_cleaning_issue(wc,'paper','After delete')->>'code','429','deleting the report does not reset consumed budget');
 EXECUTE 'RESET ROLE';
 UPDATE public.abuse_policy_rules SET base_limit=10 WHERE rule_key='cleaning.report.actor';
 PERFORM public.report_cleaning_issue(wc,'paper','New report');
 UPDATE public.abuse_policy_rules SET base_limit=100 WHERE rule_key='cleaning.report.bytes';
 SELECT data INTO old_data FROM public.cleaning_reports WHERE occasion=occ;
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_eq(public.report_cleaning_issue(wc,'paper',repeat(chr(1),30))->>'code','429','stored JSON encoding counts escaped bytes');
 EXECUTE 'RESET ROLE';
 PERFORM assert_true((SELECT data IS NOT DISTINCT FROM old_data FROM public.cleaning_reports WHERE occasion=occ),'oversized append leaves existing report unchanged');
END $$;
