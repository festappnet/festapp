CREATE OR REPLACE FUNCTION public.abort_waitlist_acceptance_internal(p_order bigint,p_command uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.waitlist_acceptance_attempts; s jsonb; p jsonb; expiry timestamptz;
 original_ticket eshop.tickets; restored_outcome text; original_id bigint;
BEGIN
 SELECT * INTO a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command AND target_order_id=p_order;
 IF a.command_id IS NULL THEN RETURN false; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.source_order_id,a.target_order_id]);
 SELECT * INTO STRICT a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command FOR UPDATE;
 IF a.state='aborted' THEN RETURN true; END IF;
 IF a.state<>'preparing' THEN RAISE EXCEPTION 'Acceptance attempt already completed'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=a.offer_id FOR UPDATE;
 PERFORM public.cancel_order_email_intents(p_order);
 PERFORM public.internal_storno_tickets_221(a.ticket_ids);
 DELETE FROM eshop.order_product_ticket WHERE "order"=a.target_order_id AND ticket=ANY(a.ticket_ids);
 IF a.conversion='in_place' THEN
  UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=a.previous_order_data->'data',updated_at=clock_timestamp() WHERE id=a.target_order_id;
 ELSE
  UPDATE eshop.orders SET state='storno',price=0,payment_info=NULL,updated_at=clock_timestamp() WHERE id=a.target_order_id;
 END IF;
 -- Only the selected tickets are fenced by the preparing target. Never restore
 -- unselected/displaced answers or resurrect a concurrently withdrawn remainder.
 FOR p IN SELECT * FROM jsonb_array_elements(a.previous_tickets) LOOP
  IF NOT (p->>'id')::bigint=ANY(a.ticket_ids) THEN CONTINUE; END IF;
  UPDATE eshop.tickets SET state=p->>'state',ticket_symbol=p->>'ticket_symbol',data=p->'data',note=p->>'note',
   note_hidden=p->>'note_hidden',waitlist_queue_at=(p->>'waitlist_queue_at')::timestamptz,updated_at=clock_timestamp() WHERE id=(p->>'id')::bigint;
 END LOOP;
 INSERT INTO eshop.order_product_ticket SELECT * FROM jsonb_populate_recordset(NULL::eshop.order_product_ticket,a.previous_links);
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(a.slot_ids);
 FOR s IN SELECT * FROM jsonb_array_elements(a.previous_slots) LOOP
  original_id:=(s->>'ticket_id')::bigint;
  SELECT * INTO STRICT original_ticket FROM eshop.tickets WHERE id=original_id FOR UPDATE;
  restored_outcome:=CASE
   WHEN original_ticket.state<>'waitlisted' OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=original_id AND x."order"=a.source_order_id)
    OR EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other WHERE other.ticket_id=original_id AND other.outcome='pending' AND NOT other.id=ANY(a.slot_ids)) THEN 'cancelled'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other JOIN eshop.waitlist_offers ow ON ow.id=other.offer_id
     WHERE other.ticket_id=original_id AND other.outcome IN ('declined','cancelled')
     AND ow.created_at>(SELECT created_at FROM eshop.waitlist_offers WHERE id=a.offer_id)) THEN 'cancelled'
   WHEN expiry<=clock_timestamp() THEN 'expired' ELSE 'pending' END;
  UPDATE eshop.waitlist_offer_slots SET ticket_id=original_id,outcome=restored_outcome,resulting_order_id=NULL,updated_at=clock_timestamp() WHERE id=(s->>'id')::uuid;
  IF restored_outcome='expired' AND original_ticket.state='waitlisted' THEN
   UPDATE eshop.tickets SET waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=original_id;
  END IF;
 END LOOP;
 UPDATE eshop.waitlist_acceptance_attempts SET state='aborted',updated_at=clock_timestamp() WHERE command_id=p_command;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=(SELECT form FROM eshop.orders WHERE id=a.source_order_id);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(a.source_order_id,'waitlisted',jsonb_build_object('action','acceptance_aborted','commandId',p_command,'targetOrderId',a.target_order_id));
 PERFORM public.notification_center_order_capacity_internal(a.source_order_id);
 PERFORM public.notification_center_order_state_internal(p_order);
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.expire_waitlist_offers(p_batch_size integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; affected integer:=0; n integer; occ bigint; impacts jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.cleanup_order_overview_sources_internal(p_batch_size);
 IF p_batch_size NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid expiry batch'; END IF;
 FOR f IN SELECT DISTINCT form_id FROM eshop.waitlist_offers w WHERE expires_at<=clock_timestamp() AND EXISTS
  (SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.offer_id=w.id AND outcome='pending') ORDER BY form_id LIMIT p_batch_size LOOP
  PERFORM 1 FROM public.forms WHERE id=f FOR UPDATE;
  PERFORM 1 FROM eshop.orders WHERE form=f ORDER BY id FOR UPDATE;
  n:=public.expire_waitlist_form_internal(f,clock_timestamp(),p_batch_size-affected); affected:=affected+n;
  IF n>0 THEN
   SELECT occasion INTO occ FROM public.forms WHERE id=f;
   SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,'userId',ou."user")),'[]') INTO impacts
    FROM public.occasion_users ou CROSS JOIN unnest(ARRAY['private_profile','private_inventory']) component WHERE ou.occasion=occ;
   PERFORM public.record_client_sync_commit_v1(occ,'inventory.waitlist.expire','inventory',
    jsonb_build_array(jsonb_build_object('entityType','form','entityId',f,'operation','update','safeLabel','Offer expiry',
    'changedFields',jsonb_build_array('capacity','waitlistSummary'))),'{}',impacts,'[]','service',NULL);
  END IF;
  EXIT WHEN affected>=p_batch_size;
 END LOOP;
 RETURN jsonb_build_object('expiredSlots',affected);
END $$;
REVOKE ALL ON FUNCTION public.abort_waitlist_acceptance_internal(bigint,uuid),public.expire_waitlist_offers(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_waitlist_offers(integer) TO service_role;
