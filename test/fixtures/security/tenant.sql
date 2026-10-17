-- Persistent synthetic UI/HTTP fixture, exclusively for the owned disposable DB.
DO $$
DECLARE actor uuid; member uuid; outsider uuid; o bigint; hidden_o bigint; g bigint; p bigint; form_id bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment
   WHERE project='festapp-data-security-e2e-20261018') THEN RAISE EXCEPTION 'Disposable security target required'; END IF;
 SELECT id INTO actor FROM public.user_info WHERE email_readonly='t@t.com';
 member:=public.create_user_in_organization_with_data_pure(1,'member@security.test','test','{"name":"Local","surname":"Member"}');
 outsider:=public.create_user_in_organization_with_data_pure(1,'outsider@security.test','test','{"name":"Local","surname":"Outsider"}');
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden,data,features)
 VALUES(1,1,'Security E2E','security-e2e',now(),now()+interval '1 day',true,false,'{"timezone":"Europe/Prague"}',
 '[{"code":"user_groups","is_enabled":true},{"code":"map","is_enabled":true},{"code":"timetable","is_enabled":true}]') RETURNING id INTO o;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,is_hidden,data)
 VALUES(1,1,'Security hidden E2E','security-hidden-e2e',now(),now()+interval '1 day',true,true,'{"private":"retained"}') RETURNING id INTO hidden_o;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_approved)
 VALUES(o,actor,true,true,true,true),(o,member,false,false,false,true),
 (hidden_o,actor,true,true,true,true),(hidden_o,member,false,false,false,true);
 INSERT INTO public.places(occasion,title,type,is_hidden,coordinates)
 VALUES(o,'Private group location','group',true,'{"latLng":{"lat":50,"lng":14}}') RETURNING id INTO p;
 INSERT INTO public.user_group_info(occasion,title,place) VALUES(o,'Local member group',p) RETURNING id INTO g;
 INSERT INTO public.user_groups("group","user",is_admin) VALUES(g,member,true),(g,actor,false);
 INSERT INTO public.news(occasion,message) VALUES(o,'<p>Security local news</p>'),(hidden_o,'<p>Hidden local news</p>');
 INSERT INTO public.forms(occasion,title,link,is_open) VALUES(hidden_o,'Hidden public form','security-public-form',true) RETURNING id INTO form_id;
 PERFORM public.reserve_public_link_internal('form',form_id,'security-public-form',true);
 PERFORM public.reserve_public_link_internal('occasion',o,'security-e2e',true);
 PERFORM public.reserve_public_link_internal('occasion',hidden_o,'security-hidden-e2e',true);
END $$;
NOTIFY pgrst,'reload schema';
