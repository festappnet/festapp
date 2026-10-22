DO $$
DECLARE org bigint; u bigint; other_unit bigint; oc bigint; actor uuid:=extensions.gen_random_uuid(); conn uuid; value jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Card editor fixture') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Editor organizer',org) RETURNING id INTO u;
 INSERT INTO public.units(title,organization) VALUES('Foreign organizer',org) RETURNING id INTO other_unit;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Editor event',org,u,'stripe-editor-'||extensions.gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id,email) VALUES(actor,actor||'@stripe.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,actor,true);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,model_verified,business_name)
 VALUES(org,u,'acct_editorFixture',false,'connected',true,'Verified organizer') RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 value:=public.get_form_stripe_recipient(u,oc,false);
 PERFORM assert_eq(value->>'connectionId',conn::text,'form editor can choose the connected recipient');
 PERFORM assert_true(NOT(value ? 'accountId') AND NOT(value ? 'dashboardUrl'),'editor projection does not grant account management');
 BEGIN
  PERFORM public.get_stripe_unit_connection(u,false);RAISE EXCEPTION 'editor managed connection';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.get_form_stripe_recipient(other_unit,oc,false);RAISE EXCEPTION 'foreign unit accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM assert_true(public.get_form_stripe_recipient(u,oc,true) IS NULL,'sandbox and live recipients remain separate');
END $$;
