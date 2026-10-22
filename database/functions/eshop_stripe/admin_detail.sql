CREATE OR REPLACE FUNCTION public.get_stripe_order_admin_detail(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; a eshop.stripe_checkout_attempts; c eshop.stripe_connections; totals record;
 d eshop.stripe_admission_decisions; revision text; note text; tickets jsonb; card_refunded bigint;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.can_write_orders(o.occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions occasion JOIN public.user_info viewer ON viewer.organization=occasion.organization AND viewer.id=auth.uid() WHERE occasion.id=o.occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.payment_method IS DISTINCT FROM 'stripe' THEN RETURN NULL; END IF;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor),0) INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 SELECT * INTO d FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason IN ('partial_refund_keep','partial_refund_cancel') ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(provider_id,amount_minor) ORDER BY provider_id)::text,'[]'),'sha256'),'hex')
  INTO revision FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF d.id IS NOT NULL THEN
  SELECT data->>'note' INTO note FROM eshop.orders_history WHERE "order"=o.id AND data->>'decisionId'=d.id::text ORDER BY created_at DESC LIMIT 1;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',coalesce(t.ticket_symbol,t.id::text),'state',t.state) ORDER BY t.id),'[]'::jsonb)
 INTO tickets FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id;
 RETURN jsonb_build_object('orderId',o.id,'currency',a.currency,'refundedMinor',card_refunded,'amountMinor',a.amount_minor,
  'canDecide',card_refunded>0 AND card_refunded<a.amount_minor AND a.state='paid' AND o.state IN ('paid','sent') AND NOT totals.invalid_identity
   AND a.refund_cursor IS NULL AND a.session_lookup_cursor IS NULL AND pi.id=a.payment_info_id AND pi.stripe_connection_id=a.connection_id,
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,
  'decision',CASE WHEN d.id IS NOT NULL THEN jsonb_build_object('action',CASE WHEN d.reason='partial_refund_keep' THEN 'keep' ELSE 'cancel_selected' END,
   'ticketIds',d.ticket_ids,'note',note,'createdAt',d.created_at,'isCurrent',d.provider_revision=revision) END,
  'tickets',tickets,'dashboardUrl',CASE WHEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=a.unit_id AND "user"=auth.uid() AND is_manager)
   THEN 'https://dashboard.stripe.com/'||c.account_id||CASE WHEN a.livemode THEN '' ELSE '/test' END||'/dashboard' END);
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_order_admin_detail(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_order_admin_detail(bigint) TO authenticated;
