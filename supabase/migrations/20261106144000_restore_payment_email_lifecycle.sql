-- Restore payment-scoped reminders and reusable waitlist confirmation versions.
-- Generated from the canonical owners below; do not edit embedded definitions.

-- Source: database/functions/eshop_orders/recalculate_order_payment_status.sql
-- One financial eligibility decision for bank facts and actual product changes.
-- Callers own authorization; this private invoker owns no history snapshots.
CREATE OR REPLACE FUNCTION public.reconcile_order_payment_internal_v1(p_order_id bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    v_order eshop.orders;
    v_payment eshop.payment_info;
    v_eligible boolean;
    v_was_eligible boolean;
    v_transition jsonb;
    v_final_state text;
    v_final_version bigint;
    v_promote boolean;
BEGIN
    IF p_reason IS NULL OR p_reason NOT IN ('payment_fact','product_edit') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_RECONCILIATION_REASON';
    END IF;
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
    SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info FOR UPDATE;
    v_was_eligible := coalesce(v_order.state IN ('paid','sent'),false);
    -- Provider facts and non-admission shells retain their existing owners.
    IF v_payment.id IS NULL OR v_payment.payment_method='stripe'
       OR v_order.state NOT IN ('created','ordered','expired','paid','sent') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='product_edit' THEN
        PERFORM public.ensure_order_payment_instructions_internal(p_order_id);
        SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info;
    END IF;

    -- The saved deposit is a commercial snapshot, capped by the current price.
    v_eligible := coalesce(v_order.price,0)<=0 OR coalesce(v_payment.paid,0)>=
        least(coalesce(v_payment.deposit_amount,v_order.price),v_order.price);
    v_promote := v_eligible AND NOT v_was_eligible;

    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.cancel_order_email_intents(p_order_id);
        -- The paid primitive owns the single version bump when promoting.
        IF NOT v_promote THEN
            UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=now()
            WHERE id=p_order_id;
        END IF;
    END IF;

    IF v_promote THEN
        -- Reuse the existing atomic primitive and delivery boundary. A failed
        -- receipt must abort its outer pairing or receipted product command.
        v_transition := public.update_order_and_tickets_to_paid(p_order_id);
        IF v_transition->>'code' IS DISTINCT FROM '200' THEN
            RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                coalesce(v_transition->>'message','invalid transition receipt');
        END IF;
    ELSIF NOT v_eligible AND v_was_eligible THEN
        UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
        UPDATE eshop.tickets t SET state='ordered',updated_at=now()
        FROM eshop.order_product_ticket opt
        WHERE opt.ticket=t.id AND opt."order"=p_order_id AND t.state IN ('paid','sent');
    ELSIF p_reason='product_edit' THEN
        -- An eligible paid order needs the edited content at its final version.
        -- Already sent admission stays sent; used/cancelled tickets stay intact.
        PERFORM public.enqueue_paid_order_tickets(p_order_id);
    END IF;

    -- Cancellation above invalidates the old reminder version. Rebuild only this
    -- payment's eligible reminders, including the balance after a paid deposit.
    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.queue_payment_reminders_internal(v_order.occasion,v_payment.id);
    END IF;

    PERFORM public.notification_center_order_state_internal(p_order_id);
    SELECT state,email_payment_version INTO v_final_state,v_final_version FROM eshop.orders WHERE id=p_order_id;
    RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_final_state,
        'eligibility_changed',v_eligible IS DISTINCT FROM v_was_eligible,
        'email_payment_version',v_final_version);
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) TO postgres,service_role;

CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.reconcile_order_payment_internal_v1(p_order_id,'payment_fact');
END;
$$;

-- Source: database/functions/eshop_waitlist/fakturoid_recovery.sql
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
  -- The restored order may be accepted again with a new confirmation payload.
  -- Keep the cancelled attempt immutable and allocate a new email identity once.
  UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=a.previous_order_data->'data',
   email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=a.target_order_id;
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
