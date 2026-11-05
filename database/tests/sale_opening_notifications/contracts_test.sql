DO $$
DECLARE org bigint; uid bigint; occ bigint; fid bigint; metadata jsonb; result jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Upozornění - test') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Ples','sale-test-'||gen_random_uuid(),org,uid,now()+interval '2 days',now()+interval '3 days') RETURNING id INTO occ;
 metadata:=jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'), 'sale_opening_notifications',jsonb_build_object('enabled',true));
 INSERT INTO public.forms(occasion,is_open,data) VALUES(occ,true,metadata) RETURNING id INTO fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 PERFORM assert_true((public.get_sale_opening_projection_internal(fid)->>'canSubscribe')::boolean,'Future open form permits collection');
 PERFORM assert_false(has_table_privilege('anon','public.sale_opening_subscriptions','SELECT'),'No anonymous contacts');
 PERFORM assert_false(has_table_privilege('authenticated','public.sale_opening_subscriptions','SELECT'),'No direct authenticated contacts');
 PERFORM assert_false(has_function_privilege('anon','public.sale_opening_notification_command(text,jsonb)','EXECUTE'),'Public cannot bypass Edge');
 PERFORM assert_false(has_function_privilege('authenticated','public.maintain_sale_opening_notifications(integer)','EXECUTE'),'Maintenance is service-only');
 PERFORM assert_eq(public.can_read_sale_opening_subscribers(occ),public.can_read_participant_contacts(occ),'Typed contact policy matches existing contacts');
 PERFORM assert_eq(public.apply_form_settings_internal(jsonb_build_array(NULL,metadata),'{"sale_opening_notifications":{"collection_paused":true}}'),
   public.apply_form_settings_internal(metadata,'{"sale_opening_notifications":{"collection_paused":true}}'),'Legacy null/object metadata shares the settings owner');
 result:=public.apply_form_settings_internal(metadata,'{"sale_opening_notifications":{"collection_paused":true}}');
 PERFORM assert_true((result#>>'{sale_opening_notifications,enabled}')::boolean,'Partial pause preserves enable');
 UPDATE public.forms SET data=result WHERE id=fid;
 PERFORM assert_false((public.get_sale_opening_projection_internal(fid)->>'canSubscribe')::boolean,'Pause stops collection');
 UPDATE public.forms SET data=forms.data #- '{schedule,start_time}' WHERE id=fid;
 BEGIN PERFORM public.sync_sale_opening_settings_internal(fid,NULL); RAISE EXCEPTION 'Missing date accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 UPDATE public.forms SET data=jsonb_set(forms.data,'{sale_opening_notifications,enabled}','false') WHERE id=fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE form_id=fid),'cancelled','Explicit disable ends campaign');
 DELETE FROM public.forms WHERE id=fid;
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_campaigns WHERE form_id=fid),'Aggregate delete removes campaign');
END $$;
