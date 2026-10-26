-- The overview link belongs in existing order emails, never a separate message.
-- Keep historical template and delivery rows; exclude this code from the catalog.
DROP FUNCTION IF EXISTS public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text);

-- Private renderer boundary. The first ordinary order email creates the source;
-- every later message and split child reuses the root's encrypted source.
CREATE OR REPLACE FUNCTION public.get_order_email_overview_source_v1(
 p_order_id bigint,p_recipient text,p_command_id uuid,p_delivery jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE requested eshop.orders; root eshop.orders; occ public.occasions; f public.forms;
 s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT requested FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO STRICT root FROM eshop.orders WHERE id=coalesce(requested.source_waitlist_order_id,requested.id) FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 IF requested.occasion IS DISTINCT FROM root.occasion OR requested.form IS DISTINCT FROM root.form
 OR requested.data->>'email' IS DISTINCT FROM p_recipient THEN
  RAISE EXCEPTION 'INVALID_OVERVIEW_RECIPIENT';
 END IF;
 -- A repaired split child must not receive the root capability covering other
 -- orders at its former contact. Omit that optional link; preserve the root
 -- source and every other order/contact unchanged.
 IF root.data->>'email' IS DISTINCT FROM p_recipient THEN RETURN NULL; END IF;
 -- Orders without a public form have no public overview route.
 IF f.id IS NULL THEN RETURN NULL; END IF;
 SELECT src.* INTO s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE cap.order_id=root.id AND cap.form_id=f.id AND cap.organization_id=occ.organization
 AND cap.kind='order_view' AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp()
 AND src.expires_at=cap.expires_at ORDER BY src.created_at DESC LIMIT 1;
 IF s.token_hash IS NULL THEN
  -- Never silently replace an expired/revoked capability with a different link.
  IF EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=root.id AND kind='order_view') THEN RETURN NULL; END IF;
  IF p_delivery IS NOT NULL THEN
   PERFORM public.issue_order_overview_internal(root.id,p_delivery,p_command_id);
   SELECT * INTO STRICT s FROM eshop.order_overview_sources WHERE command_id=p_command_id;
  END IF;
 END IF;
 RETURN jsonb_build_object('orderId',root.id,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,
 'recipient',p_recipient,'occasionTitle',occ.title,'orderSymbol',root.order_symbol,
 'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(root.id)),
 'formLink',f.link,'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=occ.organization),
 'source',CASE WHEN s.token_hash IS NOT NULL THEN jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,'expiresAt',s.expires_at) END);
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) TO service_role;
