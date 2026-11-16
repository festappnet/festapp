CREATE OR REPLACE FUNCTION public.notification_center_order_internal(p_order bigint,p_kind text,p_transition text,p_actor uuid DEFAULT auth.uid(),p_extra jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; org bigint; event uuid; ticket_count bigint; form_context jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND OR o.state='stock' THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.notification_center_organizations WHERE organization=org) THEN RETURN; END IF;
 -- Financial facts carry no ticket/person contribution. NULL means not
 -- applicable here; the shared facts owner never invokes legacy hydration.
 IF p_kind NOT IN ('order_payment_received','payment_problem') THEN
  SELECT count(DISTINCT ticket) INTO ticket_count FROM eshop.order_product_ticket WHERE "order"=o.id;
  form_context:=public.notification_center_order_form_context_internal(o.form);
 END IF;
 event:=public.notification_center_publish_internal(org,o.occasion,p_kind,p_kind||':'||p_order||':'||p_transition,
 jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'state',o.state,'formContext',form_context,'count',ticket_count)||p_extra,p_actor);
 UPDATE public.notification_center_events SET status=o.state WHERE id=event;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_state_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.notification_center_events e JOIN eshop.orders o ON o.occasion=e.occasion
  WHERE o.id=p_order AND e.data->>'orderId'=p_order::text AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted') AND (e.status='storno') IS DISTINCT FROM (o.state='storno')) OR EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 JOIN public.email_messages m ON m.order_id=o.id AND m.occasion=o.occasion AND m.organization=oc.organization
 JOIN public.notification_center_events e ON e.organization=m.organization AND e.source_key='email:'||m.message_id AND e.kind='email_problem'
 WHERE o.id=p_order AND o.state='storno' AND m.message_kind<>'order_storno' AND e.status NOT IN ('recovered','resolved')) THEN
  PERFORM public.notification_center_prepared_invalidate_order(p_order);
 END IF;
 UPDATE public.notification_center_events e SET status=o.state,data=e.data||jsonb_build_object('state',o.state)
 FROM eshop.orders o WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
 AND e.occasion=o.occasion AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_internal(bigint,text,text,uuid,jsonb),public.notification_center_order_state_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
