CREATE OR REPLACE FUNCTION public.notification_center_order_internal(p_order bigint,p_kind text,p_transition text,p_actor uuid DEFAULT auth.uid(),p_extra jsonb DEFAULT '{}')
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; org bigint; event uuid; ticket_count bigint; form_context jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF NOT FOUND OR o.state='stock' THEN RETURN; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=o.occasion;
 SELECT count(DISTINCT ticket) INTO ticket_count FROM eshop.order_product_ticket WHERE "order"=o.id;
 SELECT jsonb_build_object('formId',f.id,'allowsMultiple',least(public.ticket_order_limit(),coalesce(min(CASE WHEN ff.data->>'max_tickets' ~ '^[0-9]{1,9}$' THEN greatest(1,(ff.data->>'max_tickets')::integer) ELSE 1 END),1))>1)
 INTO form_context FROM public.forms f LEFT JOIN public.form_fields ff ON ff.form=f.id AND ff.type='ticket' WHERE f.id=o.form GROUP BY f.id;
 event:=public.notification_center_publish_internal(org,o.occasion,p_kind,p_kind||':'||p_order||':'||p_transition,
 jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'state',o.state,'formContext',form_context)||
 CASE WHEN p_kind IN ('order_created','waitlist_registered') THEN jsonb_build_object('count',ticket_count) ELSE '{}'::jsonb END||p_extra,p_actor);
 UPDATE public.notification_center_events SET status=o.state WHERE id=event;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_order_state_internal(p_order bigint)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 UPDATE public.notification_center_events e SET status=o.state,data=e.data||jsonb_build_object('state',o.state)
 FROM eshop.orders o WHERE o.id=p_order AND e.data->>'orderId'=p_order::text
 AND e.occasion=o.occasion AND e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
$$;
REVOKE ALL ON FUNCTION public.notification_center_order_internal(bigint,text,text,uuid,jsonb),public.notification_center_order_state_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
