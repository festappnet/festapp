-- Fence writers before checking: a concurrent old-client write must be seen.
LOCK TABLE public.forms, eshop.customer_order_change_policies, eshop.customer_order_change_capabilities, eshop.customer_order_change_requests, eshop.customer_order_change_events IN ACCESS EXCLUSIVE MODE;
-- Never discard a term, credential or business history during this cutover.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.forms WHERE term_start_at IS NOT NULL OR term_end_at IS NOT NULL)
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_requests WHERE operation='move' OR target_form_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_capabilities WHERE operation='move')
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_events WHERE operation='move')
 OR EXISTS(SELECT 1 FROM eshop.customer_order_change_policies WHERE policy#>'{move,enabled}'='true'::jsonb) THEN
  RAISE EXCEPTION 'Term-moving state requires explicit preservation before cutover';
 END IF;
END $$;
