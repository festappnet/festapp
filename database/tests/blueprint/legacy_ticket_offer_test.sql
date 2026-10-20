-- test-setup: database/tests/blueprint/fixtures.sql


BEGIN;
DO $$
DECLARE f jsonb; r jsonb; ticket_field bigint; pt bigint; spot bigint; secret uuid:=gen_random_uuid();
BEGIN
 f:=public.blueprint_test_fixture_internal();
 PERFORM set_config('request.jwt.claim.sub',f->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 r:=public.update_blueprint_client_sync_v1(f->'request',gen_random_uuid());
 PERFORM public.assert_eq((r->>'code')::int,200,'canonical fixture saved');
 SELECT product_type INTO pt FROM eshop.products WHERE id=(f->>'product')::bigint;
 UPDATE public.form_fields SET is_hidden=true WHERE form=(f->>'form')::bigint AND type='product_type';
 INSERT INTO public.form_fields(form,type,product_type,is_hidden,is_ticket_field)
 VALUES((f->>'form')::bigint,'ticket',pt,false,false) RETURNING id INTO ticket_field;
 SELECT s.id INTO spot FROM eshop.spots s WHERE blueprint=(f->>'blueprint')::bigint ORDER BY s.id LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','anon',true);
 r:=public.get_blueprint(secret,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,products}'),1,'existing ticket container supplies the visible seat product');
 r:=public.select_spot((f->>'formKey')::uuid,secret,spot,true);
 PERFORM public.assert_eq((r->>'code')::int,200,'existing ticket container admits a real hold');
 PERFORM public.select_spot((f->>'formKey')::uuid,secret,spot,false);
 UPDATE public.form_fields SET is_hidden=true WHERE id=ticket_field;
 r:=public.get_blueprint(secret,(f->>'formKey')::uuid,(f->>'blueprint')::bigint);
 PERFORM public.assert_eq(jsonb_array_length(r#>'{data,products}'),0,'hidden ticket offer is omitted');
 r:=public.select_spot((f->>'formKey')::uuid,secret,spot,true);
 PERFORM public.assert_eq(r->>'reason','PRODUCT_NOT_IN_FORM','hidden ticket offer cannot reserve');
 PERFORM public.assert_eq((SELECT s.secret IS NULL FROM eshop.spots s WHERE s.id=spot),true,'rejected hold has no side effect');
 UPDATE public.form_fields SET is_hidden=false WHERE form=(f->>'form')::bigint AND type='product_type';
 r:=public.select_spot((f->>'formKey')::uuid,secret,spot,true);
 PERFORM public.assert_eq((r->>'code')::int,200,'participant product field remains supported');
END $$;
ROLLBACK;
