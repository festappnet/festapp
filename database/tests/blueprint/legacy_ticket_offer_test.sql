-- test-setup: database/tests/blueprint/fixtures.sql
-- A form's associated blueprint offers its seats independently of product fields.
BEGIN;
DO $$
DECLARE f jsonb; r jsonb; spot bigint; hold_secret uuid:=gen_random_uuid(); unrelated bigint;
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq((r->>'code')::int,200,'canonical fixture saved');
 DELETE FROM public.form_fields WHERE form=(f->>'form')::bigint;
 SELECT id INTO spot FROM eshop.spots WHERE blueprint=(f->>'blueprint')::bigint ORDER BY id LIMIT 1;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
 SELECT occasion,product_type,'Not bound to this blueprint',999,'CZK' FROM eshop.products WHERE id=(f->>'product')::bigint RETURNING id INTO unrelated;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 r:=public.get_blueprint(hold_secret,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,products}'),1,'bound seat product offered without any form product field');
 PERFORM public.assert_eq((r#>>'{data,products,0,id}')::bigint,(f->>'product')::bigint,'unbound same-type product not exposed');
 r:=public.select_spot((f->>'formKey')::uuid,hold_secret,spot,true);
 PERFORM public.assert_eq(r->>'code','200','bound seat can actually be reserved');
 PERFORM public.select_spot((f->>'formKey')::uuid,hold_secret,spot,false);
 INSERT INTO public.form_fields(form,type,product_type,is_hidden,is_ticket_field)
 SELECT (f->>'form')::bigint,'product_type',product_type,true,true FROM eshop.products WHERE id=(f->>'product')::bigint;
 r:=public.select_spot((f->>'formKey')::uuid,hold_secret,spot,true);
 PERFORM public.assert_eq(r->>'code','200','hidden auxiliary form field does not hide an assigned blueprint seat');
 PERFORM public.select_spot((f->>'formKey')::uuid,hold_secret,spot,false);
 UPDATE eshop.products SET is_hidden=true WHERE id=(f->>'product')::bigint;
 r:=public.select_spot((f->>'formKey')::uuid,hold_secret,spot,true);
 PERFORM public.assert_eq(r->>'reason','PRODUCT_HIDDEN','actual product visibility remains authoritative');
 PERFORM public.assert_true((SELECT s.secret IS NULL FROM eshop.spots s WHERE s.id=spot),'rejected hold has no side effect');
END $$;
ROLLBACK;
