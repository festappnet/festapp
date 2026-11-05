DO $$
DECLARE org bigint; uid bigint; source_occ bigint; target_occ bigint; fid bigint; copied bigint; actor uuid; slug text; response jsonb; m public.email_messages;
BEGIN
 PERFORM create_user_for_test('sale-copy-author','sale-copy-author@example.invalid');actor:=get_user_id('sale-copy-author');
 INSERT INTO public.organizations(title) VALUES('Kopie upozornění') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Pořadatel',org) RETURNING id INTO uid;
 INSERT INTO public.unit_users(unit,"user",is_editor,is_editor_view,is_manager) VALUES(uid,actor,true,true,true);
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Zdroj',gen_random_uuid()::text,org,uid,now(),now()+interval '2 days') RETURNING id INTO source_occ;
 INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Kopie',gen_random_uuid()::text,org,uid,now(),now()+interval '2 days') RETURNING id INTO target_occ;
 INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view) VALUES(source_occ,actor,true,true),(target_occ,actor,true,true);
 slug:=public.reserve_public_link_internal('occasion',target_occ,NULL,true);UPDATE public.occasions SET link=slug WHERE id=target_occ;
 INSERT INTO public.forms(title,occasion,is_open,data) VALUES('Přihláška',source_occ,true,jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'),'sale_opening_notifications','{"enabled":true}'::jsonb)) RETURNING id INTO fid;
 UPDATE public.forms SET link=public.reserve_public_link_internal('form',fid,NULL,true) WHERE id=fid;
 PERFORM public.sync_sale_opening_settings_internal(fid,NULL);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 copied:=public.duplicate_form_to_occasion_internal_v1(fid,slug,'cs');
 PERFORM assert_false((SELECT data ? 'sale_opening_notifications' FROM public.forms WHERE id=copied),'Form copy starts with disabled configuration');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_campaigns WHERE form_id=copied),'Form copy never clones campaign');
 -- Old full-save payloads omit the new setting; existing commitments survive.
 response:=public.update_form_internal_v1(jsonb_build_object('id',fid,'occasion',source_occ,'data',jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'))));
 PERFORM assert_eq(response->>'code','200','Released full save stays supported');
 PERFORM assert_true((SELECT (data#>>'{sale_opening_notifications,enabled}')::boolean FROM public.forms WHERE id=fid),'Old full save preserves notification settings');
 PERFORM assert_eq((SELECT phase FROM public.sale_opening_campaigns WHERE form_id=fid),'armed','Old full save does not end campaign');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.sale_opening_notification_command('subscribe',jsonb_build_object('formLink',(SELECT link FROM public.forms WHERE id=fid),'email','copy-delete@example.invalid','lang','cs',
 'unsubscribe',jsonb_build_object('hash',repeat('6',64),'envelope',jsonb_build_object('v','1','ciphertext',repeat('y',48)))));
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE occasion=source_occ),0::bigint,'Copy/source subscription creates no confirmation email');
 PERFORM public.delete_form_internal_v1(fid);
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.sale_opening_campaigns WHERE form_id=fid),'Canonical aggregate deletion removes campaign');
END $$;
