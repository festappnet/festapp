DO $$
DECLARE org bigint; uid bigint; occ bigint; fid bigint; cid uuid; n integer;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Obnovitelné dávky') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Ples',gen_random_uuid()::text,org,uid,now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,is_open,data) VALUES(occ,true,jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'),'sale_opening_notifications','{"enabled":true}'::jsonb)) RETURNING id INTO fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 SELECT id INTO cid FROM public.sale_opening_campaigns WHERE form_id=fid;
 -- Frozen verified contacts isolate bounded fanout from double-opt-in, which
 -- is exercised separately through the real subscription command.
 INSERT INTO public.sale_opening_subscriptions(campaign_id,email_normalized,lang,state)
 SELECT cid,'batch-'||i||'@example.invalid','cs','active' FROM generate_series(1,101) i;
 UPDATE public.forms SET data=jsonb_set(data,'{schedule,start_time}',to_jsonb(now()-interval '1 minute')) WHERE id=fid;
 UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('email.ordinary','email.backlog');
 n:=public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq(n,100,'First tick cannot produce more than 100 intents');
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'dispatching','Remaining subscriber prevents premature completion');
 n:=public.maintain_sale_opening_notifications(100);
 PERFORM assert_eq(n,1,'Resumption finds the remaining subscriber without an offset cursor');
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE occasion=occ AND message_kind='sale_opening_opened'),101::bigint,'No contact lost between bounded ticks');
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE id=cid),'completed','Production completes after every eligible intent exists');
 PERFORM assert_eq(public.maintain_sale_opening_notifications(100),0,'Completed fanout never rearms itself');
END $$;
