CREATE OR REPLACE FUNCTION public.get_waitlist_email_context_v1(p_operation text,p_payload jsonb,p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; f public.forms; occ public.occasions; contexts jsonb; r jsonb; o eshop.orders;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSE RAISE EXCEPTION 'Invalid email context operation'; END IF;
 SELECT * INTO STRICT f FROM public.forms WHERE id=fid; SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 IF p_operation='send' AND NOT public.order_editor_membership_as_actor_internal(p_actor,occ.id) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 contexts:='[]';
 IF p_operation='register' THEN contexts:=jsonb_build_array(jsonb_build_object('recipient',p_payload->>'email','organization',occ.organization,
  'occasion',occ.id,'unit',occ.unit,'occasionTitle',occ.title,'participantCount',jsonb_array_length(p_payload->'tickets'),'formLink',f.link));
 ELSE
  FOR r IN SELECT * FROM jsonb_array_elements(p_payload->'recipients') LOOP
   SELECT * INTO STRICT o FROM eshop.orders WHERE id=(r->>'orderId')::bigint AND form=fid;
   contexts:=contexts||jsonb_build_array(jsonb_build_object('orderId',o.id,'recipient',o.data->>'email','organization',occ.organization,
   'occasion',occ.id,'unit',occ.unit,'occasionTitle',occ.title,'orderSymbol',o.order_symbol,
   'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
   'offeredCount',(r->>'count')::integer,'formLink',f.link,'expiresAt',p_payload->>'expiresAt'));
  END LOOP;
 END IF;
 RETURN contexts;
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_context_v1(text,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_context_v1(text,jsonb,uuid) TO service_role;
