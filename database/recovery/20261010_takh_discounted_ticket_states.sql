-- Authorized correction for order 4F4M8N7U6J only. No email is enqueued.
-- Execute in a transaction after the discounted-ticket payment migration.
DO $$
DECLARE
  v_order eshop.orders;
  v_changed integer;
  v_impacts jsonb;
BEGIN
  SELECT o.* INTO v_order FROM eshop.orders o
  JOIN public.occasions oc ON oc.id=o.occasion
  JOIN public.units u ON u.id=oc.unit
  WHERE o.id=6523 AND o.order_symbol='4F4M8N7U6J'
    AND o.occasion=1072585 AND u.organization=3
  FOR UPDATE OF o;
  IF v_order.id IS NULL OR v_order.state<>'sent' OR v_order.price<>0 THEN
    RAISE EXCEPTION 'discounted order recovery target changed';
  END IF;
  PERFORM t.id FROM eshop.tickets t WHERE t.id IN (8690,8691)
    ORDER BY t.id FOR UPDATE;
  IF (SELECT count(DISTINCT t.id) FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket=t.id
      WHERE opt."order"=v_order.id AND t.id IN (8690,8691)
        AND t.occasion=v_order.occasion AND t.state IN ('ordered','sent')
        AND EXISTS(SELECT 1 FROM public.email_messages m
          WHERE m.order_id=v_order.id AND m.message_kind='order_tickets'
            AND m.source_version=v_order.email_payment_version
            AND m.workflow_state='accepted' AND m.delivered_at IS NOT NULL
            AND m.post_action_state='done'
            AND m.post_action->'ticket_ids' @> to_jsonb(t.id)))<>2 THEN
    RAISE EXCEPTION 'discounted ticket recovery delivery evidence changed';
  END IF;
  UPDATE eshop.tickets SET state='sent',updated_at=now()
    WHERE id IN (8690,8691) AND state='ordered';
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed=0 THEN RETURN; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'component','private_inventory','userId',ou."user")),'[]'::jsonb)
    INTO v_impacts FROM public.occasion_users ou
    WHERE ou.occasion=v_order.occasion AND ou.ticket IN (8690,8691);
  PERFORM public.record_client_sync_commit_v1(v_order.occasion,
    'recovery.discounted_ticket_states','private',
    '[{"entityType":"ticket","entityId":"8690","operation":"update","safeLabel":"Correct delivered ticket state","changedFields":["state"]},
      {"entityType":"ticket","entityId":"8691","operation":"update","safeLabel":"Correct delivered ticket state","changedFields":["state"]}]'::jsonb,
    '{}'::text[],v_impacts,'[]'::jsonb,'system',
    'Repair ordered ticket projection after confirmed zero-price order delivery');
  RAISE NOTICE 'Corrected % delivered ticket states',v_changed;
END $$;
