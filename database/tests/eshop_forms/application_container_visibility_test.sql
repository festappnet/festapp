BEGIN;
DO $$
DECLARE org bigint; un bigint; oc bigint; fm bigint; container bigint;
 price_field bigint; note_field bigint; hidden_field bigint; pt bigint;
 product bigint; hidden_product bigint; form_link text:=gen_random_uuid()::text;
 reply jsonb; fields jsonb;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Application container regression') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Application container regression',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time)
 VALUES('Application without issued tickets',un,org,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.forms(occasion,link,is_open) VALUES(oc,form_link,true) RETURNING id INTO fm;
 INSERT INTO public.form_fields(form,type,is_hidden,is_required,data)
 VALUES(fm,'ticket',true,true,'{"max_tickets":1}') RETURNING id INTO container;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Registration fee','other') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Registration',1900,'CZK',false) RETURNING id INTO product;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,is_hidden)
 VALUES(oc,pt,'Internal price',1,'CZK',true) RETURNING id INTO hidden_product;
 INSERT INTO public.form_fields(form,type,product_type,is_ticket_field,is_hidden,is_required)
 VALUES(fm,'product_type',pt,true,false,true) RETURNING id INTO price_field;
 INSERT INTO public.form_fields(form,type,is_ticket_field,is_hidden)
 VALUES(fm,'note',true,false) RETURNING id INTO note_field;
 INSERT INTO public.form_fields(form,type,title,is_hidden)
 VALUES(fm,'text','Internal answer',true) RETURNING id INTO hidden_field;
 PERFORM pg_temp.adopt_public_link_fixtures();
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM set_config('request.jwt.claim.role','anon',true);
 EXECUTE 'SET LOCAL ROLE anon';
 reply:=public.get_form_by_link(form_link)::jsonb;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(reply->>'code','200','Anonymous application is available');
 fields:=reply#>'{data,fields}';
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f WHERE (f->>'id')::bigint=container),
   'Disabled ticket issuance must not remove the application container and orphan its prices');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f WHERE (f->>'id')::bigint=container AND (f->>'is_hidden')::boolean),
   'Public bundle preserves the ticket issuance flag');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f WHERE (f->>'id')::bigint=note_field),
   'Application note remains available');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f,
   LATERAL jsonb_array_elements(f#>'{product_type_data,products}') p
   WHERE (f->>'id')::bigint=price_field AND (p->>'id')::bigint=product AND (p->>'price')::numeric=1900),
   'Application retains its actual offered price');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f WHERE (f->>'id')::bigint=hidden_field),
   'Ordinary hidden fields stay private');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(fields) f,
   LATERAL jsonb_array_elements(f#>'{product_type_data,products}') p WHERE (p->>'id')::bigint=hidden_product),
   'Hidden catalog products stay private');
 PERFORM assert_false((public.get_occasion_sale_forms_internal(oc)->0->>'has_tickets')::boolean,
   'Rendering application prices must not enable ticket issuance');
 UPDATE public.form_fields SET is_hidden=false WHERE id=container;
 reply:=public.get_form_by_link(form_link)::jsonb;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(reply#>'{data,fields}') f WHERE (f->>'id')::bigint=container),
   'Ticket-enabled applications retain their container');
 UPDATE public.forms SET is_open=false WHERE id=fm;
 EXECUTE 'SET LOCAL ROLE anon';
 reply:=public.get_form_by_link(form_link)::jsonb;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq(reply->>'code','400','Closed forms remain closed');
 PERFORM assert_false((reply->'data') ? 'fields','Closed form does not expose its fields');
END $$;
ROLLBACK;
