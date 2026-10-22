DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; pt bigint; p bigint; conn uuid; available jsonb;
BEGIN
 INSERT INTO public.organizations(title,data) VALUES('Card form tenant','{"DEFAULT_URL":"https://tickets.example"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Card form organizer',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Card forms',org,u,'card-form-'||extensions.gen_random_uuid(),now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,data,is_open,key) VALUES(occ,'{}',true,extensions.gen_random_uuid()) RETURNING id INTO f;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Card tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code) VALUES(pt,occ,'Ticket',123.45,'CZK') RETURNING id INTO p;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 available:=public.form_payment_availability_internal(f);
 PERFORM assert_eq(available->'available','["bank"]'::jsonb,'old forms retain bank, card defaults off');
 BEGIN
  PERFORM public.reserve_public_link_internal('occasion',occ,'stripe',true);RAISE EXCEPTION 'payment route shadowed by occasion';
 EXCEPTION WHEN invalid_parameter_value THEN IF SQLERRM<>'Reserved public link' THEN RAISE; END IF; END;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
 VALUES(org,u,'acct_formFixture',false,'connected',false,true,true,true) RETURNING id INTO conn;
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',true,'stripeConnectionId',conn)) WHERE id=f;
 PERFORM public.validate_form_payment_configuration_internal(f);
 PERFORM assert_eq(public.form_payment_availability_internal(f)->>'stripeUnavailableReason','payments_disabled','connection alone never enables card');
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces)
 VALUES(org,false,true,true,true,true,ARRAY['web']);
 available:=public.form_payment_availability_internal(f);
 PERFORM assert_eq(available->'available','["stripe", "bank"]'::jsonb,'both configured methods offered');
 PERFORM assert_eq(available#>>'{recipient,name}','Card form organizer','missing Stripe public name retains the bound organizer identity');
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'stripeConnectionId',conn)) WHERE id=f;
 PERFORM public.validate_form_payment_configuration_internal(f);
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','["stripe"]'::jsonb,'Stripe-only excludes bank on the server');
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false}}'::jsonb WHERE id=f;
 BEGIN
  PERFORM public.validate_form_payment_configuration_internal(f);RAISE EXCEPTION 'no configured payment method accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_CONFIGURATION_INVALID' THEN RAISE; END IF; END;
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',true,'stripeConnectionId',conn)) WHERE id=f;
 PERFORM assert_true(NOT available::text LIKE '%acct_%','safe projection excludes provider account identity');
 PERFORM assert_eq(public.assert_stripe_form_payable_internal(f,conn,'web'),conn,'server checks receiver and surface');
 BEGIN
  PERFORM public.assert_stripe_form_payable_internal(f,extensions.gen_random_uuid(),'web');RAISE EXCEPTION 'receiver spoof accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_RECIPIENT_CHANGED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.assert_stripe_form_payable_internal(f,conn,'native');RAISE EXCEPTION 'unverified surface accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_SURFACE_UNVERIFIED' THEN RAISE; END IF; END;
 UPDATE eshop.stripe_connections SET paused=true WHERE id=conn;
 available:=public.form_payment_availability_internal(f);
 PERFORM assert_true((available#>>'{configured,stripe}')::boolean,'pause retains editor choice');
 PERFORM assert_eq(available->'available','["bank"]'::jsonb,'pause disables new card attempts');
 UPDATE eshop.stripe_connections SET paused=false,payouts_enabled=false WHERE id=conn;
 PERFORM assert_true(public.form_payment_availability_internal(f)->'available' ? 'stripe','payout restrictions alone do not disable charges');
 UPDATE eshop.products SET data='{"deposit":{"amount":10}}' WHERE id=p;
 PERFORM assert_eq(public.stripe_form_compatibility_internal(f),'deposit_unsupported','MVP deposit rejection');
 UPDATE eshop.products SET data='{"meta_surcharge":{"amount":10}}' WHERE id=p;
 PERFORM assert_eq(public.stripe_form_compatibility_internal(f),'surcharge_unsupported','virtual surcharge rejection');
 UPDATE eshop.products SET data='{}' WHERE id=p;
 INSERT INTO eshop.external_services(unit,type) VALUES(u,'FAKTUROID');
 PERFORM assert_eq(public.stripe_form_compatibility_internal(f),'fakturoid_unsupported','Fakturoid rejection stays on server');
END $$;
