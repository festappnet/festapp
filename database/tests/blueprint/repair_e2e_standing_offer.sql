-- Synthetic disposable fixture only: psql -v fixture_form=2 -f this-file.
-- Standing remains an admission (type='spot') because the existing finalizer
-- requires an admission product for every ticket without an addressed spot.
SELECT set_config('festapp.fixture_form',:'fixture_form',false);
BEGIN;
DO $$
DECLARE fid bigint:=current_setting('festapp.fixture_form')::bigint; occasion_id bigint; blueprint_id bigint; standing_product bigint; standing_type bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment) THEN RAISE EXCEPTION 'disposable fixture database required'; END IF;
 SELECT occasion,blueprint INTO occasion_id,blueprint_id FROM public.forms WHERE id=fid;
 IF blueprint_id IS NULL OR (SELECT count(*) FROM eshop.blueprint_area_bindings WHERE blueprint=blueprint_id)<>1 THEN RAISE EXCEPTION 'expected one synthetic standing area required'; END IF;
 SELECT product INTO standing_product FROM eshop.blueprint_area_bindings WHERE blueprint=blueprint_id;
 SELECT id INTO standing_type FROM eshop.product_types WHERE occasion=occasion_id AND title='Standing admission' AND type='spot' ORDER BY id LIMIT 1;
 IF standing_type IS NULL THEN INSERT INTO eshop.product_types(occasion,title,type) VALUES(occasion_id,'Standing admission','spot') RETURNING id INTO standing_type; END IF;
 UPDATE eshop.products SET product_type=standing_type WHERE id=standing_product AND occasion=occasion_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'standing fixture product scope mismatch'; END IF;
 INSERT INTO public.form_fields(form,title,type,product_type,is_required,is_hidden,is_ticket_field,"order",data)
 SELECT fid,'Standing admission','product_type',standing_type,false,false,true,40,'{"selection_type":"select_one"}' WHERE NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=fid AND type='product_type' AND product_type=standing_type);
 UPDATE public.form_fields SET is_hidden=false,is_ticket_field=true,"order"=40,data=coalesce(data,'{}')||'{"selection_type":"select_one"}' WHERE form=fid AND type='product_type' AND product_type=standing_type;
 RAISE NOTICE 'Standing product % remains admission, with separate offered product type %; area product/context bindings unchanged',standing_product,standing_type;
END $$;
COMMIT;
