BEGIN;
DO $test$
DECLARE
  org bigint; unit_id bigint; occasion_id bigint; other_id bigint;
  type_id bigint; other_type bigint; visible_id bigint; hidden_id bigint;
  catalog jsonb; product jsonb;
BEGIN
  INSERT INTO public.organizations(title) VALUES ('Preview RPC test') RETURNING id INTO org;
  INSERT INTO public.units(title,organization) VALUES ('Preview RPC test',org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(title,unit,link,start_time,end_time)
    VALUES ('Preview',unit_id,'preview-rpc-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occasion_id;
  INSERT INTO public.occasions(title,unit,link,start_time,end_time)
    VALUES ('Other',unit_id,'preview-other-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO other_id;
  INSERT INTO eshop.product_types(title,type,occasion) VALUES ('Food','food',occasion_id) RETURNING id INTO type_id;
  INSERT INTO eshop.product_types(title,type,occasion) VALUES ('Other','spot',other_id) RETURNING id INTO other_type;
  INSERT INTO eshop.products(title,product_type,occasion,price,currency_code,is_hidden,data)
    VALUES ('Dinner',type_id,occasion_id,170,'CZK',false,'{"short_title":"Steak"}') RETURNING id INTO visible_id;
  INSERT INTO eshop.products(title,product_type,occasion,price,currency_code,is_hidden)
    VALUES ('Hidden',type_id,occasion_id,0,'EUR',true) RETURNING id INTO hidden_id;
  INSERT INTO eshop.products(title,product_type,occasion,price)
    VALUES ('Other',other_type,other_id,999);
  catalog:=public.get_products_and_types(occasion_id)::jsonb;
  IF jsonb_array_length(catalog->'products')<>2 OR jsonb_array_length(catalog->'product_types')<>1 THEN
    RAISE EXCEPTION 'RPC must keep products scoped to the selected occasion';
  END IF;
  SELECT value INTO product FROM jsonb_array_elements(catalog->'products') WHERE (value->>'id')::bigint=visible_id;
  IF product->'price' IS DISTINCT FROM '170'::jsonb OR product->>'currency_code'<>'CZK'
    OR product->'is_hidden' IS DISTINCT FROM 'false'::jsonb OR product->>'short_title'<>'Steak'
    OR product->'data' IS DISTINCT FROM '{"short_title":"Steak"}'::jsonb THEN
    RAISE EXCEPTION 'RPC must include real preview price/currency/visibility and existing fields';
  END IF;
  SELECT value INTO product FROM jsonb_array_elements(catalog->'products') WHERE (value->>'id')::bigint=hidden_id;
  IF product->'price' IS DISTINCT FROM '0'::jsonb OR product->>'currency_code'<>'EUR'
    OR product->'is_hidden' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'RPC must preserve free and hidden products for preview filtering';
  END IF;
  IF public.get_products_and_types(-1)::jsonb IS DISTINCT FROM '{"products":[],"product_types":[]}'::jsonb THEN
    RAISE EXCEPTION 'Missing catalog must return empty arrays';
  END IF;
END;
$test$;
ROLLBACK;
