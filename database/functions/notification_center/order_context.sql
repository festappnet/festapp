CREATE OR REPLACE FUNCTION public.notification_center_order_form_context_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('formId',f.id,'allowsMultiple',least(public.ticket_order_limit(),coalesce(min(
 CASE WHEN ff.data->>'max_tickets' ~ '^[0-9]{1,9}$' THEN greatest(1,(ff.data->>'max_tickets')::integer) ELSE 1 END),1))>1)
 FROM public.forms f LEFT JOIN public.form_fields ff ON ff.form=f.id AND ff.type='ticket' WHERE f.id=p_form GROUP BY f.id;
$$;
REVOKE ALL ON FUNCTION public.notification_center_order_form_context_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
