-- Private, data-minimal projection. The checked creation command is its sole
-- caller and invokes it only after its durable mutation receipt is completed.
-- Analytics is deliberately absent from that stored receipt and from all replay
-- and personal-order readers: at most one response may contain a purchase.
CREATE OR REPLACE FUNCTION public.form_purchase_datalayer_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN o.price>0 AND trim(o.currency_code) ~ '^[A-Z]{3}$'
   AND o.order_symbol ~ '^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$'
   AND jsonb_array_length(lines.items) BETWEEN 1 AND 200 THEN
  jsonb_build_object('event','purchase','ecommerce',jsonb_build_object(
   'transaction_id',o.order_symbol,'currency',trim(o.currency_code),
   'payment_type',CASE WHEN pi.payment_method='stripe' THEN 'card' ELSE 'bank_transfer' END,
   'items',lines.items,'value',lines.value)) END
 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
 CROSS JOIN LATERAL (
  SELECT jsonb_agg(jsonb_build_object('item_id','product_'||x.product,'item_name',x.title,'price',x.price,'quantity',x.quantity) ORDER BY x.product) items,
    sum(x.price*x.quantity) value
  FROM (SELECT opt.product,p.title,round(coalesce(p.price,0),2) price,count(*) quantity
    FROM eshop.order_product_ticket opt JOIN eshop.products p ON p.id=opt.product
    WHERE opt."order"=o.id GROUP BY opt.product,p.title,p.price) x
 ) lines WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.form_purchase_datalayer_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
