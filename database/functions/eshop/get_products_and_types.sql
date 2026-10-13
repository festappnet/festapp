CREATE OR REPLACE FUNCTION public.get_products_and_types(p_occasion_id bigint)
RETURNS json
SET search_path = public, extensions AS $$
DECLARE
  product_types json;
  products json;
  offered_type_ids bigint[];
  referenced_type_ids bigint[];
  form_metadata jsonb;
BEGIN
  SELECT array_agg(DISTINCT ff.product_type) FILTER(WHERE NOT COALESCE(ff.is_hidden,false)),array_agg(DISTINCT ff.product_type) INTO offered_type_ids,referenced_type_ids FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE f.occasion=p_occasion_id;
  SELECT jsonb_object_agg(type_id,refs) INTO form_metadata FROM (SELECT ff.product_type type_id,jsonb_agg(jsonb_build_object('title',COALESCE(f.title,ff.title),'fieldTitle',ff.title,'hidden',COALESCE(ff.is_hidden,false)) ORDER BY ff.id) refs FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE f.occasion=p_occasion_id AND ff.product_type IS NOT NULL GROUP BY ff.product_type) metadata;
  -- Fetch product types filtered by occasion.
  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title',pt.title,
             'occasion',pt.occasion,
             'admission',EXISTS(SELECT 1 FROM eshop.products ap JOIN eshop.spots asp ON asp.product=ap.id WHERE ap.product_type=pt.id),
             'forms',COALESCE(form_metadata->pt.id::text,'[]'::jsonb),
             'referenced',COALESCE(pt.id=ANY(referenced_type_ids),false),
             'offered',COALESCE(pt.id=ANY(offered_type_ids),false)
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = p_occasion_id;

  -- Fetch products whose product_type is in the filtered product types.
  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'short_title', p.data->>'short_title',
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order',p."order"
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = p_occasion_id
  );

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json)
  );
END;
$$ LANGUAGE plpgsql;
