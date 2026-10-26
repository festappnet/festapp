-- psql -v organization=3 -At -f inventory.sql > inventory.json
BEGIN READ ONLY;
SELECT COALESCE(jsonb_agg(row_data ORDER BY id),'[]') FROM (
 SELECT o.id,jsonb_build_object('id',o.id,'organization',o.organization,'features',o.features,'data',jsonb_build_object('font',o.data->'font'),
 'features_hash',md5(o.features::text),'version',COALESCE(v.version,0),
 'product_types',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',pt.id,'type',pt.type,
 'form_references',(SELECT count(*) FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE ff.product_type=pt.id AND f.occasion=o.id),
 'ordered_count',(SELECT count(*) FROM eshop.products p JOIN eshop.order_product_ticket opt ON opt.product=p.id WHERE p.product_type=pt.id)) ORDER BY pt.id),'[]') FROM eshop.product_types pt WHERE pt.occasion=o.id)) row_data
 FROM public.occasions o LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text
 WHERE o.organization=:'organization'::bigint AND EXISTS(SELECT 1 FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket')
) rows;
COMMIT;
