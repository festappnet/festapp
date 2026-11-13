-- Retract existing payment notices through the normal bounded repair workers.
-- Keep source facts, deliveries, email subscriptions and read receipts intact.
DO $$ DECLARE item record; BEGIN
 FOR item IN SELECT e.id FROM public.notification_center_events e
 WHERE e.kind='order_payment_received'
  AND EXISTS(SELECT 1 FROM public.notification_center_deliveries d WHERE d.event_id=e.id)
 LOOP PERFORM public.notification_center_prepared_invalidate(item.id); END LOOP;
END $$;
