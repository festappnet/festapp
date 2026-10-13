CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer;
BEGIN
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.accept_waitlist_offer_internal(p_payload jsonb,p_command uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE w eshop.waitlist_offers; o eshop.orders; fid bigint; target bigint; ids uuid[]; selected_slots uuid[];
 n integer; remaining integer; result jsonb; input jsonb; old_people jsonb; old_slots jsonb; conversion text; ticket jsonb; position integer;
 original_group jsonb; remaining_group jsonb; accepted_group jsonb; history_snapshot jsonb;
BEGIN
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=(p_payload->>'offerId')::uuid;
 fid:=public.check_waitlist_scope_internal(w.order_id,w.id,p_payload->>'token',p_actor,'accept');
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[w.order_id]);
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=w.id FOR UPDATE;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=w.order_id;
 PERFORM public.expire_waitlist_form_internal(fid);
 IF w.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 IF o.state<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 SELECT array_agg(x::uuid) INTO ids FROM jsonb_array_elements_text(p_payload->'personIds') x;
 n:=coalesce(cardinality(ids),0);
 IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Invalid selected persons'; END IF;
 PERFORM 1 FROM eshop.order_participants WHERE current_order_id=o.id ORDER BY id FOR UPDATE;
 original_group:=public.snapshot_waitlist_participants_internal(o.id);
 IF n<>(SELECT count(*) FROM eshop.order_participants p WHERE p.id=ANY(ids) AND current_order_id=o.id
 AND lifecycle IN ('waiting','offered','offer_expired','offer_declined','offer_cancelled')
 AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.participant_id=p.id AND s.outcome='pending' AND s.offer_id<>w.id)) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Preserve slots already attached to selected people, then exchange only the necessary unused bindings.
 SELECT array_agg(id ORDER BY CASE WHEN participant_id=ANY(ids) THEN 0 ELSE 1 END,id) INTO selected_slots
 FROM (SELECT * FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending'
 ORDER BY CASE WHEN participant_id=ANY(ids) THEN 0 ELSE 1 END,id LIMIT n FOR UPDATE) s;
 IF coalesce(cardinality(selected_slots),0)<>n THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 -- Journal the exact pre-swap bindings, including displaced offered people.
 SELECT jsonb_agg(to_jsonb(p)) INTO old_people FROM eshop.order_participants p
 WHERE id=ANY(ids) OR id IN(SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots));
 SELECT jsonb_agg(to_jsonb(s)) INTO old_slots FROM eshop.waitlist_offer_slots s WHERE id=ANY(selected_slots);
 -- Release temporary bindings using a terminal outcome so the pending uniqueness invariant never needs deferral.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(selected_slots);
 UPDATE eshop.order_participants SET lifecycle='waiting' WHERE id IN(SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots)) AND NOT id=ANY(ids);
 WITH persons AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(ids) id), slots AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(selected_slots) id)
 UPDATE eshop.waitlist_offer_slots s SET participant_id=p.id FROM persons p JOIN slots x USING(n) WHERE s.id=x.id;
 SELECT count(*) INTO remaining FROM eshop.order_participants WHERE current_order_id=o.id;
 conversion:=CASE WHEN remaining=n THEN 'in_place' ELSE 'split' END;
 target:=CASE WHEN conversion='in_place' THEN o.id ELSE public.allocate_ticket_order_identity_internal(fid) END;
 IF conversion='split' THEN UPDATE eshop.orders SET source_waitlist_order_id=o.id WHERE id=target; END IF;
 input:=p_payload->'orderDetails';
 input:=jsonb_set(input,'{ticket}',public.normalize_form_participant_answers_internal(fid,input->'ticket'));
 IF (input->>'form')::uuid IS DISTINCT FROM (SELECT key FROM public.forms WHERE id=fid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF jsonb_array_length(input->'ticket')<>n THEN RAISE EXCEPTION 'Selected people and tickets differ'; END IF;
 -- Each selected person must explicitly bind their stable ID to their submitted ticket.
 IF n<>(SELECT count(DISTINCT (t->>'participantId')::uuid) FROM jsonb_array_elements(input->'ticket') t WHERE (t->>'participantId')::uuid=ANY(ids)) THEN
  RAISE EXCEPTION 'Invalid participant ticket binding'; END IF;
 PERFORM public.validate_waitlist_answers_internal(fid,input,input->'ticket',false);
 result:=public.finalize_ticket_order_internal_v1(target,input,true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 position:=0;
 FOR ticket IN SELECT * FROM jsonb_array_elements(input->'ticket') LOOP
  UPDATE eshop.order_participants SET current_order_id=target,lifecycle='admitted',
   ticket_id=(result#>>ARRAY['order','data','tickets',position::text,'id'])::bigint,
   answers=public.extract_participant_answers_internal(fid,ticket),updated_at=clock_timestamp()
  WHERE id=(ticket->>'participantId')::uuid;
  position:=position+1;
 END LOOP;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,o.occasion,result,input->>'lang');
 IF (SELECT state='preparing_payment' FROM eshop.orders WHERE id=target) THEN
  INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,participant_ids,slot_ids,previous_order_data,previous_participants,previous_slots)
  VALUES(p_command,o.id,target,w.id,conversion,ids,selected_slots,to_jsonb(o),old_people,old_slots);
 ELSE
  UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE offer_id=w.id
   AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending');
 END IF;
 remaining_group:=CASE WHEN conversion='split' THEN public.snapshot_waitlist_participants_internal(o.id) ELSE '[]'::jsonb END;
 accepted_group:=public.snapshot_waitlist_participants_internal(target);
 history_snapshot:=jsonb_build_object('action','waitlist_accept','commandId',p_command,'sourceOrderId',o.id,
  'targetOrderId',target,'personIds',ids,'conversion',conversion,'participantsBefore',original_group,
  'participantsAfter',remaining_group,'acceptedParticipants',accepted_group);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,(SELECT state FROM eshop.orders WHERE id=o.id),history_snapshot);
 IF conversion='split' THEN
  INSERT INTO eshop.orders_history("order",state,data) VALUES(target,(SELECT state FROM eshop.orders WHERE id=target),history_snapshot);
 END IF;
 RETURN result||jsonb_build_object('sourceOrderId',o.id,'conversion',conversion,'waitlistSummary',public.get_waitlist_summary_internal(o.id));
END $$;
REVOKE ALL ON FUNCTION public.validate_waitlist_answers_internal(bigint,jsonb,jsonb,boolean),public.accept_waitlist_offer_internal(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated;
