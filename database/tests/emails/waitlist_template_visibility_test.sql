BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE org bigint; un bigint; oc bigint; other_oc bigint; f bigint; templates jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Waitlist template visibility') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Visibility',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Active scope',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Other scope',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO public.forms(occasion,link) VALUES(oc,gen_random_uuid()::text) RETURNING id INTO f;
 INSERT INTO public.email_templates(code,subject,html,organization)
 VALUES('waitlist_confirmation','Custom confirmation','Custom body',org),('waitlist_offer','Custom offer','Custom offer body',org);
 templates:=public.get_all_email_templates(jsonb_build_object('occasion',oc));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' LIKE 'waitlist_%'),0,'unlimited form hides waitlist templates');
 UPDATE public.forms SET participant_capacity=10 WHERE id=f;
 templates:=public.get_all_email_templates(jsonb_build_object('occasion',oc));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' LIKE 'waitlist_%'),0,'capacity alone does not enable waitlist templates');
 UPDATE public.forms SET waitlist_enabled=true,waitlist_offer_duration_seconds=3600 WHERE id=f;
 templates:=public.get_all_email_templates(jsonb_build_object('occasion',oc));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' IN ('waitlist_confirmation','waitlist_offer')),2,'enabled limited form shows both templates');
 templates:=public.get_all_email_templates(jsonb_build_object('occasion',other_oc));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' LIKE 'waitlist_%'),0,'other occasion does not inherit enabled feature');
 templates:=public.get_all_email_templates(jsonb_build_object('unit',un));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' IN ('waitlist_confirmation','waitlist_offer')),2,'unit catalog includes its enabled form');
 UPDATE public.forms SET waitlist_enabled=false WHERE id=f;
 templates:=public.get_all_email_templates(jsonb_build_object('unit',un));
 PERFORM assert_eq((SELECT count(*)::int FROM jsonb_array_elements(templates) t WHERE t->>'code' LIKE 'waitlist_%'),0,'disabled feature hides templates again');
 PERFORM assert_eq((SELECT html FROM public.email_templates WHERE organization=org AND code='waitlist_confirmation'),'Custom body','visibility preserves stored custom template');
END $$;
ROLLBACK;
