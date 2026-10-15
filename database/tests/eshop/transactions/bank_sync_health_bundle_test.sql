DO $$
DECLARE org bigint:=-971510; unit_id bigint:=-971510; oc bigint:=-971510; bank bigint:=-971510;
 form_id bigint:=-971510; pi bigint:=-971510; actor uuid; conn bigint; bundle jsonb; item jsonb;
BEGIN
 INSERT INTO public.organizations(id,title) VALUES(org,'Bank warning bundle tenant');
 INSERT INTO public.units(id,title,organization) VALUES(unit_id,'Bank warning bundle unit',org);
 INSERT INTO public.occasions(id,title,organization,unit,link,start_time,end_time)
 VALUES(oc,'Bank warning bundle occasion',org,unit_id,'bank-health-bundle',now(),now()+interval '1 day');
 INSERT INTO public.forms(id,occasion,link,key,data,is_open) VALUES(form_id,oc,'bank-health-bundle-form',gen_random_uuid(),'{}',true);
 INSERT INTO eshop.bank_accounts(id,title,type,account_number) VALUES(bank,'Bundle bank','FIO','971510/2010');
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(unit_id,bank);
 INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
  provider,mode,state,manifest_sha256,legacy_blocked_at)
 VALUES('health-bundle','festapp','971510',bank,'971510/2010','FIO','api','suspended',repeat('b',64),now()) RETURNING id INTO conn;
 PERFORM public.create_user_for_test('bank_bundle_admin','bundle-admin@example.invalid');
 actor:=public.get_user_id('bank_bundle_admin');
 UPDATE public.user_info SET organization=org,email_delivery='bundle-admin@example.invalid' WHERE id=actor;
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank,actor,true);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES(oc,actor,true,true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(unit_id,actor,true);
 INSERT INTO eshop.payment_info(id,bank_account,variable_symbol,amount,currency_code) VALUES(pi,bank,971510,100,'CZK');
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data,price,currency_code,payment_info,form)
 VALUES(oc,public.next_order_sequence(oc),public.generate_order_symbol(),'ordered','{}',100,'CZK',pi,form_id);
  PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 bundle:=public.get_orders('bank-health-bundle',NULL,NULL);
 PERFORM assert_eq((bundle->>'code')::integer,200,'authorized order reader gets health summary');
 PERFORM assert_eq(bundle#>>'{data,payment_info,0,bank_sync_warning,code}','suspended','order bundle shows pause');
 PERFORM assert_eq(bundle#>>'{data,payment_info,0,bank_sync_warning,bank_account_id}',bank::text,'warning links to the actual receiving account');
 PERFORM assert_eq(bundle#>>'{data,payment_info,0,bank_sync_warning,is_admin}','true'::text,'bank account administrator gets settings action');
 PERFORM assert_eq(bundle#>>'{data,payment_info,0,bank_sync_warning,contacts,0,email}','bundle-admin@example.invalid','order tooltip contact from same authorized bundle');
 bundle:=public.get_form_for_edit('bank-health-bundle-form');
 PERFORM assert_eq((bundle->>'code')::integer,200,'form editor gets account health');
 PERFORM assert_eq(bundle#>>'{data,available_bank_accounts,0,bank_sync_warning,code}','suspended','form bank card sees same diagnosis');
 SELECT to_jsonb(x) INTO item FROM public.get_bank_accounts_for_unit_management(unit_id) x WHERE id=bank;
 PERFORM assert_eq(item#>>'{bank_sync_warning,code}','suspended','unit account card sees same diagnosis');
 RESET ROLE;
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=bank AND "user"=actor;
 SET LOCAL ROLE authenticated;
 bundle:=public.get_orders('bank-health-bundle',NULL,NULL);
 PERFORM assert_eq(bundle#>>'{data,payment_info,0,bank_sync_warning,is_admin}','false'::text,'unit manager without bank account admin rights cannot manage synchronization');
 RESET ROLE;
 UPDATE public.occasion_users SET is_editor_order_view=false,is_editor_order=false WHERE occasion=oc AND "user"=actor;
 SET LOCAL ROLE authenticated;
 bundle:=public.get_orders('bank-health-bundle',NULL,NULL);
 PERFORM assert_eq((bundle->>'code')::integer,403,'unauthorized order reader receives no health or contacts');
 RESET ROLE;
END $$;
