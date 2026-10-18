BEGIN;
DO $$
DECLARE fx jsonb; oc bigint; fm bigint; uid uuid:=gen_random_uuid(); r jsonb; expected bigint; hidden bigint; orphan bigint; parent bigint;
BEGIN
 fx:=public.scanner_test_fixture();oc:=(fx->>'occasion')::bigint;fm:=(fx->>'form')::bigint;
 INSERT INTO auth.users(id,email) VALUES(uid,uid||'@scanner.invalid');
 INSERT INTO public.user_info(id,name,organization) SELECT uid,'Catalog editor',organization FROM public.occasions WHERE id=oc;
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order) VALUES(oc,uid,true);
 PERFORM set_config('request.jwt.claim.sub',uid::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 DELETE FROM public.form_fields WHERE form=fm;
 INSERT INTO public.form_fields(form,type,title) VALUES(fm,'email',NULL) RETURNING id INTO expected;
 INSERT INTO public.form_fields(form,type,title,is_hidden) VALUES(fm,'text','Internal only',true) RETURNING id INTO hidden;
 INSERT INTO public.form_fields(form,type,title) SELECT fm,t,'Technical '||t FROM unnest(ARRAY['name','surname','note','ticket','spot','product_type','html']) t;
 UPDATE public.form_fields SET is_hidden=true WHERE form=fm AND type='ticket';
 INSERT INTO public.form_fields(form,type,title,is_ticket_field) VALUES(fm,'text','Diet',true) RETURNING id INTO orphan;
 r:=public.get_scanner_settings(oc);
 PERFORM assert_eq(jsonb_array_length(r#>'{data,fields}'),1,'catalog excludes hidden, structural, duplicate core and unrendered child fields');
 PERFORM assert_eq(r#>>'{data,fields,0,field_id}',expected::text,'real unnamed email remains available');
 PERFORM assert_eq(r#>>'{data,fields,0,type}','email','type allows canonical localized fallback title');
 UPDATE public.form_fields SET is_hidden=false WHERE form=fm AND type='ticket';
 r:=public.get_scanner_settings(oc);
 PERFORM assert_eq(jsonb_array_length(r#>'{data,fields}'),2,'visible ticket container exposes actual answer fields');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(r#>'{data,fields}') f WHERE (f->>'field_id')::bigint=orphan),'ticket answer selectable');
END $$;
ROLLBACK;
