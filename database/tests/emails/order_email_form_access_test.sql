BEGIN;
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; k uuid:=gen_random_uuid(); oid bigint;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Email form access') RETURNING id INTO org;
 INSERT INTO public.units(title,organization,data) VALUES('Email organizer',org,'{"communication_tone":"informal"}') RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Email evening',org,u,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO public.forms(occasion,key,data) VALUES(occ,k,'{"analytics":{"enabled":true},"communication_tone":"formal"}') RETURNING id INTO f;
 INSERT INTO public.form_fields(form,type) VALUES(f,'text');
 INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,form,state,price,currency_code,data)
 VALUES(public.next_order_sequence(occ),public.generate_order_symbol(),occ,f,'ordered',100,'CZK',jsonb_build_object('form',k,'tickets','[]'::jsonb)) RETURNING id INTO oid;
 PERFORM set_config('email_form_access.order',oid::text,true);
END $$;
SET LOCAL ROLE service_role;
SELECT assert_eq(public.get_order_details_for_email(current_setting('email_form_access.order')::bigint)#>>'{data,form_data,communication_tone}',
 'formal','Real email worker can render form communication settings');
SELECT assert_false(public.get_order_details_for_email(current_setting('email_form_access.order')::bigint)#>'{data,form_data}' ? 'analytics','Email metadata excludes measurement configuration');
SELECT assert_eq(public.effective_form_metadata_internal('[null,{}]'::jsonb,'{"communication_tone":"informal"}') ->>'communication_tone','informal','Historical metadata inherits the unit tone');
RESET ROLE;
SELECT assert_false(has_function_privilege('anon','public.get_effective_form_data(bigint)','EXECUTE'),'Anonymous callers cannot read private form settings');
SELECT assert_false(has_function_privilege('authenticated','public.get_effective_form_data(bigint)','EXECUTE'),'Client callers cannot bypass checked form RPCs');
SELECT assert_false(has_function_privilege('anon','public.normalize_form_metadata_internal(jsonb)','EXECUTE'),'Normalizer stays private to backend callers');
SELECT assert_false(has_function_privilege('authenticated','public.effective_form_metadata_internal(jsonb,jsonb)','EXECUTE'),'Pure metadata helper is not exposed to clients');
SELECT assert_false(has_function_privilege('service_role','public.form_measurement_runtime_internal(bigint)','EXECUTE'),'Email worker does not gain analytics helper access');
ROLLBACK;
