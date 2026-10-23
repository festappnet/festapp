-- Synthetic local tenant only. Never provision production from this fixture.
DO $$
DECLARE actor uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1 AND title='Test Organization')
 OR EXISTS(SELECT 1 FROM public.organizations WHERE id=900001) THEN
  RAISE EXCEPTION 'Fresh synthetic backend required'; END IF;
 INSERT INTO public.organizations(id,title,data)
 SELECT 900001,'Festapp Tickets local EN',(coalesce(data,'{}'::jsonb)-'DEFAULT_UNIT'-'DEFAULT_OCCASION'-'REPRESENTATIVE_OCCASION')||
 '{"APP_NAME":"Festapp Tickets","DEFAULT_URL":"https://127.0.0.1:57381","DEFAULT_LANGUAGE":"en","CATALOG_SOURCE_POLICY":"explicit","DEFAULT_FORM_PAYMENT_METHOD":"stripe","DEFAULT_UNIT":900001,"IS_APP_SUPPORTED":false,"IS_UNIT_CREATION_ENABLED":true,"IS_REGISTRATION_ENABLED":true}'::jsonb
 FROM public.organizations WHERE id=1;
 INSERT INTO public.units(id,title,organization,data) VALUES(900001,'Starlight Events',900001,'{"timezone":"Europe/Prague"}');
 actor:=public.create_user_in_organization_with_data_pure(900001,'en-demo@example.invalid','test','{"name":"Alex","surname":"Morgan"}'::jsonb);
 INSERT INTO public.organization_users("user",organization,is_admin) VALUES(actor,900001,true);
 INSERT INTO public.unit_users("user",unit,is_manager,is_editor,is_editor_view) VALUES(actor,900001,true,true,true);
END $$;
