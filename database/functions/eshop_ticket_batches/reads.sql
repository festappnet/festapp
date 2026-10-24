CREATE OR REPLACE FUNCTION public.get_ticket_batch_detail(p_batch uuid,p_after integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; can_edit boolean; can_sell boolean;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 IF auth.uid() IS NULL OR public.get_is_editor_order_view_on_occasion(b.occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order viewer required'; END IF;
 can_edit:=public.get_is_editor_order_on_occasion(b.occasion);
 can_sell:=can_edit AND public.get_is_manager_on_unit((SELECT unit FROM public.occasions WHERE id=b.occasion))
  AND NOT EXISTS(SELECT 1 FROM eshop.external_services s JOIN public.occasions o ON o.unit=s.unit WHERE o.id=b.occasion AND s.type='FAKTUROID')
  AND b.manifest_hash IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND state<>'ready');
 RETURN jsonb_build_object('id',b.id,'occasion',b.occasion,'form',b.form,'title',b.title,'stockOrderId',b.stock_order_id,
 'currency',b.currency_code,'createdAt',b.created_at,'manifestHash',b.manifest_hash,
 'counts',(SELECT jsonb_build_object('total',count(*),'available',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state<>'storno'),
 'soldActive',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state<>'storno'),
 'voidedUnsold',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state='storno'),
 'cancelledAfterSale',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state='storno'))
 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id WHERE i.batch_id=b.id),
 'stockValue',(SELECT coalesce(sum((p->>'price')::numeric),0) FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
 CROSS JOIN LATERAL jsonb_array_elements(b.snapshot->'tickets') st CROSS JOIN LATERAL jsonb_array_elements(st->'products') p
 WHERE i.batch_id=b.id AND i.sale_order_id IS NULL AND t.state<>'storno' AND (st->>'id')::bigint=t.id),
 'receivedAmount',(SELECT coalesce(sum(coalesce(pi.paid,0)-coalesce(pi.returned,0)),0) FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
 WHERE o.id IN(SELECT sale_order_id FROM eshop.ticket_batch_items WHERE batch_id=b.id)),
 'sales',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'createdAt',o.created_at,'amount',o.price) ORDER BY o.created_at DESC),'[]')
 FROM (SELECT * FROM eshop.orders WHERE id IN(SELECT sale_order_id FROM eshop.ticket_batch_items WHERE batch_id=b.id) ORDER BY created_at DESC,id LIMIT 20) o),
 'allowedActions',jsonb_build_array('view','download')||CASE WHEN can_edit THEN jsonb_build_array('void','prepare') ELSE '[]' END
  ||CASE WHEN can_sell THEN jsonb_build_array('sell') ELSE '[]' END,
 'items',(SELECT coalesce(jsonb_agg(to_jsonb(row) ORDER BY ordinal),'[]') FROM (
 SELECT i.ordinal,t.id,t.ticket_symbol,t.state,i.sale_order_id,
 (SELECT value FROM jsonb_array_elements(b.snapshot->'tickets') WHERE (value->>'id')::bigint=t.id) snapshot
 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id WHERE i.batch_id=b.id AND i.ordinal>greatest(0,p_after)
 ORDER BY i.ordinal LIMIT 50) row),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'key',part_key,'kind',kind,'state',state,
 'bytes',byte_count,'pages',page_count,'errorCode',error_code) ORDER BY part_key),'[]') FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id));
END $$;
CREATE OR REPLACE FUNCTION public.get_ticket_batches(p_occasion bigint,p_before timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR public.get_is_editor_order_view_on_occasion(p_occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 RETURN (SELECT coalesce(jsonb_agg(public.get_ticket_batch_detail(id) ORDER BY created_at DESC,id),'[]') FROM (
  SELECT id,created_at FROM eshop.ticket_batches WHERE occasion=p_occasion AND (p_before IS NULL OR created_at<p_before)
  ORDER BY created_at DESC,id LIMIT 20) b);
END $$;
CREATE OR REPLACE FUNCTION public.preview_ticket_batch(p_form bigint,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; normalized jsonb; prices jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR public.get_is_editor_order_on_occasion(f.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 PERFORM public.check_ticket_batch_eligible_internal(f.id);
 normalized:=public.normalize_ticket_batch_selection_internal(f.id,p_selection);
 RETURN public.ticket_batch_selection_summary_internal(f.id,normalized)||jsonb_build_object('selection',normalized);
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_batch_detail(uuid,integer),public.get_ticket_batches(bigint,timestamptz),
 public.preview_ticket_batch(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_batch_detail(uuid,integer),public.get_ticket_batches(bigint,timestamptz),
 public.preview_ticket_batch(bigint,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_ticket_batch_create_options(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR public.get_is_editor_order_on_occasion(p_occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'blueprint',f.blueprint,'products',
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'price',p.price,'currency',p.currency_code) ORDER BY p.id),'[]')
   FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND pt.type='spot' AND NOT p.is_hidden
   AND EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=p.product_type AND NOT ff.is_hidden))) ORDER BY f.id),'[]')
 FROM public.forms f WHERE f.occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_batch_create_options(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_batch_create_options(bigint) TO authenticated;
