-- Export is a read of frozen documents, never another ticket generation path.
CREATE OR REPLACE FUNCTION public.get_ticket_batch_export_manifest(p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; docs jsonb; feature jsonb; template jsonb;
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch;
 IF auth.uid() IS NULL OR public.can_read_orders(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 PERFORM public.admit_ticket_batch_document_internal(b.occasion);
 IF b.manifest_hash IS NULL OR EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND kind='single' AND state<>'ready') THEN
  RAISE EXCEPTION 'BATCH_PRINT_NOT_READY'; END IF;
 SELECT jsonb_agg(jsonb_build_object('ordinal',i.ordinal,'objectKey',p.object_key,'digest',p.content_digest,'bytes',p.byte_count) ORDER BY i.ordinal)
 INTO docs FROM eshop.ticket_batch_items i JOIN eshop.ticket_batch_document_parts p ON p.batch_id=i.batch_id AND p.kind='single' AND p.ticket_ids=ARRAY[i.ticket_id]
 WHERE i.batch_id=b.id;
 IF jsonb_array_length(docs) IS DISTINCT FROM (SELECT count(*)::integer FROM eshop.ticket_batch_items WHERE batch_id=b.id) OR docs IS NULL THEN
  RAISE EXCEPTION 'BATCH_PRINT_NOT_READY'; END IF;
 SELECT value INTO feature FROM jsonb_array_elements(b.resource_manifest#>'{snapshot,occasion,features}') WHERE value->>'code'='ticket';
 template:=feature#>ARRAY['layout','templates',CASE WHEN feature->>'ticket_type'='named' THEN 'named' ELSE 'wide' END];
 RETURN public.bound_document_data_v1(jsonb_build_object('batchId',b.id,'documents',docs,'template',template));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_batch_export_manifest(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_ticket_batch_export_manifest(uuid) TO authenticated;
