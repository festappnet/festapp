-- User claim authorizes the operation; only trusted renderer can attest stored bytes.
CREATE OR REPLACE FUNCTION public.claim_ticket_batch_document(p_batch uuid,p_part uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; part eshop.ticket_batch_document_parts; token uuid:=extensions.gen_random_uuid();
BEGIN
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch FOR UPDATE;
 IF auth.uid() IS NULL OR public.can_read_orders(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 PERFORM public.admit_ticket_batch_document_internal(b.occasion);
 IF b.manifest_hash IS NULL THEN
  IF b.resource_lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('state','pending'); END IF;
  UPDATE eshop.ticket_batches SET resource_lease_token=token,resource_lease_actor=auth.uid(),
   resource_lease_expires_at=clock_timestamp()+interval '2 minutes',resource_error_code=NULL WHERE id=b.id;
  RETURN public.bound_document_data_v1(jsonb_build_object('state','claimed','kind','resources','lease',token,'snapshot',b.snapshot,'batchId',b.id));
 END IF;
 IF p_part IS NULL THEN
  SELECT * INTO part FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND state<>'ready'
   AND (lease_expires_at IS NULL OR lease_expires_at<=clock_timestamp()) ORDER BY kind,part_key LIMIT 1 FOR UPDATE;
 ELSE SELECT * INTO STRICT part FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND id=p_part FOR UPDATE;
 END IF;
 IF part.id IS NULL THEN RETURN jsonb_build_object('state',CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND state<>'ready') THEN 'pending' ELSE 'ready' END); END IF;
 IF part.state='ready' THEN RETURN jsonb_build_object('state','ready','partId',part.id,'objectKey',part.object_key,'digest',part.content_digest); END IF;
 IF part.lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('state','pending'); END IF;
 UPDATE eshop.ticket_batch_document_parts SET state='rendering',lease_token=token,lease_actor=auth.uid(),
 lease_expires_at=clock_timestamp()+interval '2 minutes',error_code=NULL WHERE id=part.id;
 RETURN public.bound_document_data_v1(jsonb_build_object('state','claimed','kind',part.kind,'lease',token,'partId',part.id,
 'ticketIds',part.ticket_ids,'batchId',b.id,'manifestHash',b.manifest_hash,'manifest',b.resource_manifest,
 'objectKey',b.id::text||'/'||b.manifest_hash||'/'||part.part_key||'.pdf'));
END $$;
CREATE OR REPLACE FUNCTION public.complete_ticket_batch_resources_internal(p_batch uuid,p_lease uuid,p_manifest jsonb,p_part_size integer)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; hash text;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT b FROM eshop.ticket_batches WHERE id=p_batch FOR UPDATE;
 IF b.manifest_hash IS NOT NULL THEN RETURN b.manifest_hash; END IF;
 IF b.resource_lease_token IS DISTINCT FROM p_lease OR b.resource_lease_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'BATCH_STALE_LEASE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=b.occasion AND "user"=b.resource_lease_actor AND is_editor_order_view) THEN RAISE insufficient_privilege; END IF;
 IF jsonb_typeof(p_manifest) IS DISTINCT FROM 'object' OR octet_length(p_manifest::text)>4194304 OR p_part_size NOT BETWEEN 1 AND 20 THEN
  RAISE invalid_parameter_value; END IF;
 hash:=encode(extensions.digest(p_manifest::text,'sha256'),'hex');
 UPDATE eshop.ticket_batches SET resource_manifest=p_manifest,manifest_hash=hash,resource_lease_token=NULL,
 resource_lease_expires_at=NULL WHERE id=b.id;
 INSERT INTO eshop.ticket_batch_document_parts(batch_id,part_key,kind,ticket_ids,manifest_hash)
 SELECT b.id,'single-'||lpad(ordinal::text,3,'0'),'single',ARRAY[ticket_id],hash FROM eshop.ticket_batch_items WHERE batch_id=b.id;
 INSERT INTO eshop.ticket_batch_document_parts(batch_id,part_key,kind,ticket_ids,manifest_hash)
 SELECT b.id,'print-'||lpad(part::text,3,'0'),'print',array_agg(ticket_id ORDER BY ordinal),hash
 FROM (SELECT *,1+(ordinal-1)/p_part_size part FROM eshop.ticket_batch_items WHERE batch_id=b.id) i GROUP BY part;
 RETURN hash;
END $$;
CREATE OR REPLACE FUNCTION public.complete_ticket_batch_document_internal(p_part uuid,p_lease uuid,p_digest text,p_bytes bigint,p_pages integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; part eshop.ticket_batch_document_parts;
BEGIN
 PERFORM public.require_service_role();
 SELECT b0.* INTO STRICT b FROM eshop.ticket_batches b0 JOIN eshop.ticket_batch_document_parts p ON p.batch_id=b0.id WHERE p.id=p_part FOR UPDATE OF b0;
 SELECT * INTO STRICT part FROM eshop.ticket_batch_document_parts WHERE id=p_part FOR UPDATE;
 IF part.state='ready' THEN
  IF part.content_digest IS DISTINCT FROM p_digest THEN RAISE EXCEPTION 'BATCH_DOCUMENT_IMMUTABLE'; END IF; RETURN; END IF;
 IF part.state<>'rendering' OR part.lease_token IS DISTINCT FROM p_lease OR part.lease_expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'BATCH_STALE_LEASE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=b.occasion AND "user"=part.lease_actor AND is_editor_order_view) THEN RAISE insufficient_privilege; END IF;
 IF p_pages<>cardinality(part.ticket_ids) THEN RAISE EXCEPTION 'BATCH_DOCUMENT_PAGE_COUNT'; END IF;
 UPDATE eshop.ticket_batch_document_parts SET state='ready',object_key=b.id::text||'/'||b.manifest_hash||'/'||part.part_key||'.pdf',
 content_digest=p_digest,byte_count=p_bytes,page_count=p_pages,lease_token=NULL,lease_expires_at=NULL,error_code=NULL WHERE id=p_part;
END $$;
CREATE OR REPLACE FUNCTION public.fail_ticket_batch_document_internal(p_batch uuid,p_part uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.ticket_batches SET resource_error_code='RESOURCE_PREPARATION_FAILED',resource_lease_token=NULL,resource_lease_expires_at=NULL
 WHERE id=p_batch AND manifest_hash IS NULL AND resource_lease_token=p_lease;
 UPDATE eshop.ticket_batch_document_parts SET state='failed',error_code='RENDER_FAILED',lease_token=NULL,lease_expires_at=NULL
 WHERE batch_id=p_batch AND id=p_part AND lease_token=p_lease AND state='rendering';
END $$;
CREATE OR REPLACE FUNCTION public.get_ticket_batch_stored_document(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.ticket_batches; part eshop.ticket_batch_document_parts; oc bigint;
BEGIN
 SELECT occasion INTO oc FROM eshop.tickets WHERE id=p_ticket;
 IF auth.role()<>'service_role' AND (auth.uid() IS NULL OR public.can_read_orders(oc) IS NOT TRUE) THEN RAISE insufficient_privilege; END IF;
 SELECT b0.* INTO b FROM eshop.ticket_batches b0 JOIN eshop.ticket_batch_items i ON i.batch_id=b0.id WHERE i.ticket_id=p_ticket;
 IF b.id IS NULL THEN RETURN NULL; END IF;
 IF auth.role()<>'service_role' AND (auth.uid() IS NULL OR public.can_read_orders(b.occasion) IS NOT TRUE) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO part FROM eshop.ticket_batch_document_parts WHERE batch_id=b.id AND kind='single' AND ticket_ids=ARRAY[p_ticket];
 IF part.state IS DISTINCT FROM 'ready' THEN RAISE EXCEPTION 'BATCH_PRINT_NOT_READY'; END IF;
 RETURN jsonb_build_object('objectKey',part.object_key,'digest',part.content_digest,'bytes',part.byte_count);
END $$;
REVOKE ALL ON FUNCTION public.claim_ticket_batch_document(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.claim_ticket_batch_document(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_ticket_batch_resources_internal(uuid,uuid,jsonb,integer),
 public.complete_ticket_batch_document_internal(uuid,uuid,text,bigint,integer),public.fail_ticket_batch_document_internal(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_ticket_batch_resources_internal(uuid,uuid,jsonb,integer),
 public.complete_ticket_batch_document_internal(uuid,uuid,text,bigint,integer),public.fail_ticket_batch_document_internal(uuid,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_ticket_batch_stored_document(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_batch_stored_document(bigint) TO authenticated,service_role;
