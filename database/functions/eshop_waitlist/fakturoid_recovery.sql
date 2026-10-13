CREATE OR REPLACE FUNCTION public.abort_waitlist_acceptance_internal(p_order bigint,p_command uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.waitlist_acceptance_attempts; previous jsonb; s jsonb; p jsonb; expiry timestamptz; ticket_ids bigint[];
 original_person eshop.order_participants; restored_outcome text; original_id uuid;
BEGIN
 SELECT * INTO a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command AND target_order_id=p_order;
 IF a.command_id IS NULL THEN RETURN false; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.source_order_id,a.target_order_id]);
 SELECT * INTO STRICT a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command FOR UPDATE;
 IF a.state='aborted' THEN RETURN true; END IF;
 IF a.state<>'preparing' THEN RAISE EXCEPTION 'Acceptance attempt already completed'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=a.offer_id FOR UPDATE;
 SELECT array_agg(ticket_id) INTO ticket_ids FROM eshop.order_participants WHERE id=ANY(a.participant_ids);
 PERFORM public.cancel_order_email_intents(p_order);
 PERFORM public.internal_storno_tickets_221(ticket_ids);
 -- The failed ticket records remain historical; detach them from the reusable identity.
 DELETE FROM eshop.order_product_ticket WHERE "order"=a.target_order_id AND ticket=ANY(ticket_ids);
 IF a.conversion='in_place' THEN
  UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=a.previous_order_data->'data',updated_at=clock_timestamp()
   WHERE id=a.target_order_id;
 ELSE
  UPDATE eshop.orders SET state='storno',price=0,payment_info=NULL,updated_at=clock_timestamp() WHERE id=a.target_order_id;
 END IF;
 -- Selected people are fenced by the preparing target. Displaced offered people
 -- remain in the source and may legitimately withdraw or receive another offer.
 -- Restore their offer lifecycle below without overwriting their current answers.
 FOR p IN SELECT * FROM jsonb_array_elements(a.previous_participants) LOOP
  IF NOT (p->>'id')::uuid=ANY(a.participant_ids) THEN CONTINUE; END IF;
  UPDATE eshop.order_participants SET current_order_id=(p->>'current_order_id')::bigint,
   lifecycle=p->>'lifecycle',answers=p->'answers',ticket_id=(p->>'ticket_id')::bigint,
   queue_at=(p->>'queue_at')::timestamptz,updated_at=clock_timestamp() WHERE id=(p->>'id')::uuid;
 END LOOP;
 -- Release all consumed bindings first: full acceptance can permute participant
 -- IDs between slots, and immediate pending uniqueness must hold throughout.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(a.slot_ids);
 FOR s IN SELECT * FROM jsonb_array_elements(a.previous_slots) LOOP
  original_id:=(s->>'participant_id')::uuid;
  SELECT * INTO STRICT original_person FROM eshop.order_participants WHERE id=original_id FOR UPDATE;
  restored_outcome:=CASE
   WHEN original_person.lifecycle IN ('withdrawn','cancelled') OR original_person.current_order_id<>a.source_order_id
     OR EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other WHERE other.participant_id=original_id
       AND other.outcome='pending' AND NOT other.id=ANY(a.slot_ids)) THEN 'cancelled'
   WHEN original_person.lifecycle='offer_declined' THEN 'declined'
   WHEN original_person.lifecycle='offer_cancelled' THEN 'cancelled'
   WHEN expiry<=clock_timestamp() OR original_person.lifecycle='offer_expired' THEN 'expired'
   ELSE 'pending' END;
  UPDATE eshop.waitlist_offer_slots SET participant_id=original_id,
   outcome=restored_outcome,resulting_order_id=NULL,updated_at=clock_timestamp()
  WHERE id=(s->>'id')::uuid;
  IF restored_outcome IN ('pending','expired') AND original_person.lifecycle IN ('waiting','offered','offer_expired') THEN
   UPDATE eshop.order_participants SET lifecycle=CASE WHEN restored_outcome='pending' THEN 'offered' ELSE 'offer_expired' END,
    queue_at=CASE WHEN restored_outcome='pending' THEN queue_at ELSE clock_timestamp() END,updated_at=clock_timestamp()
   WHERE id=original_id;
  END IF;
 END LOOP;
 UPDATE eshop.waitlist_acceptance_attempts SET state='aborted',updated_at=clock_timestamp() WHERE command_id=p_command;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=(SELECT form FROM eshop.orders WHERE id=a.source_order_id);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(a.source_order_id,'waitlisted',
  jsonb_build_object('action','acceptance_aborted','commandId',p_command,'targetOrderId',a.target_order_id));
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.expire_waitlist_offers(p_batch_size integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; affected integer:=0; n integer; occ bigint; impacts jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
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
