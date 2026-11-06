BEGIN;
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; k uuid:=gen_random_uuid(); oid bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Email form access') RETURNING id INTO org;
 INSERT INTO public.units(title,organization,data) VALUES('Email organizer',org,'{"communication_tone":"informal"}') RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Email evening',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,key,data) VALUES(occ,k,'{}') RETURNING id INTO f;
 INSERT INTO public.form_fields(form,type) VALUES(f,'text');
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,form,state,price,currency_code,data)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,f,'ordered',100,'CZK',jsonb_build_object('form',k,'tickets','[]'::jsonb)) RETURNING id INTO oid;
 PERFORM set_config('email_form_access.order',oid::text,true);
END $$;
SET LOCAL ROLE service_role;
SELECT assert_eq(public.get_order_details_for_email(current_setting('email_form_access.order')::bigint)#>>'{data,form_data,communication_tone}',
 'informal','Real email worker can render inherited form settings');
RESET ROLE;
SELECT assert_false(has_function_privilege('anon','public.get_effective_form_data(bigint)','EXECUTE'),'Anonymous callers cannot read private form settings');
SELECT assert_false(has_function_privilege('authenticated','public.get_effective_form_data(bigint)','EXECUTE'),'Client callers cannot bypass checked form RPCs');
ROLLBACK;
