-- Payment facts are published by financial owners, never inferred by delivery.
CREATE TABLE IF NOT EXISTS eshop.payment_notification_incidents (
 payment_id bigint PRIMARY KEY REFERENCES eshop.payment_info(id) ON DELETE CASCADE,
 incident_id uuid NOT NULL DEFAULT gen_random_uuid(), active boolean NOT NULL DEFAULT true,
 reason text NOT NULL, opened_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE eshop.payment_notification_incidents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.payment_notification_incidents FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_payment_fact_internal(p_order bigint,p_namespace text,p_fact text,p_amount numeric,p_currency text,p_at timestamptz,p_reassigned boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_amount<=0 OR p_fact IS NULL OR p_namespace IS NULL THEN RETURN; END IF;
 -- An existing source snapshot wins on replay, including detach/reattach.
 IF EXISTS(SELECT 1 FROM public.notification_center_events e JOIN eshop.orders o ON o.occasion=e.occasion
  WHERE o.id=p_order AND e.source_key='order_payment_received:'||p_order||':'||p_namespace||':'||p_fact) THEN RETURN; END IF;
 PERFORM public.notification_center_order_internal(p_order,'order_payment_received',p_namespace||':'||p_fact,NULL,
  jsonb_build_object('amount',p_amount,'currency',p_currency,'paymentFact',p_namespace||':'||p_fact,'receivedAt',p_at,'reassigned',p_reassigned));
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_payment_problem_internal(p_order bigint,p_problem boolean,p_reason text)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE payment bigint; incident eshop.payment_notification_incidents; event uuid;
BEGIN
 SELECT payment_info INTO payment FROM eshop.orders WHERE id=p_order;
 IF payment IS NULL THEN RETURN; END IF;
 SELECT * INTO incident FROM eshop.payment_notification_incidents WHERE payment_id=payment FOR UPDATE;
 IF p_problem THEN
  IF NOT FOUND THEN
   INSERT INTO eshop.payment_notification_incidents(payment_id,reason) VALUES(payment,p_reason) RETURNING * INTO incident;
  ELSIF NOT incident.active THEN
   UPDATE eshop.payment_notification_incidents SET active=true,incident_id=gen_random_uuid(),reason=p_reason,opened_at=clock_timestamp() WHERE payment_id=payment RETURNING * INTO incident;
  ELSE UPDATE eshop.payment_notification_incidents SET reason=p_reason WHERE payment_id=payment;
  END IF;
  SELECT id INTO event FROM public.notification_center_events WHERE kind='payment_problem'
   AND data->>'orderId'=p_order::text AND data->>'incidentId'=incident.incident_id::text;
  IF FOUND THEN
   IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE id=event AND data->>'reason' IS DISTINCT FROM p_reason) THEN
    PERFORM public.notification_center_prepared_invalidate(event);
    UPDATE public.notification_center_events SET data=data||jsonb_build_object('reason',p_reason) WHERE id=event;
   END IF;
   RETURN;
  END IF;
  PERFORM public.notification_center_order_internal(p_order,'payment_problem',incident.incident_id::text,NULL,
   jsonb_build_object('incidentId',incident.incident_id,'reason',p_reason));
 ELSE
  UPDATE eshop.payment_notification_incidents SET active=false WHERE payment_id=payment;
  FOR event IN SELECT id FROM public.notification_center_events WHERE kind='payment_problem' AND data->>'orderId'=p_order::text AND status NOT IN ('recovered','resolved') LOOP
   PERFORM public.notification_center_prepared_invalidate(event);
   UPDATE public.notification_center_events SET status='recovered' WHERE id=event;
  END LOOP;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_payment_fact_internal(bigint,text,text,numeric,text,timestamptz,boolean),public.notification_center_payment_problem_internal(bigint,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
