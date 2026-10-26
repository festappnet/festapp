CREATE OR REPLACE FUNCTION public.issue_order_overview_internal(p_order bigint,p_delivery jsonb,p_command uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; expiry timestamptz;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order AND source_waitlist_order_id IS NULL FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF occ.end_time IS NULL THEN RAISE EXCEPTION 'OVERVIEW_EVENT_END_REQUIRED'; END IF;
 expiry:=greatest(occ.end_time+interval '90 days',statement_timestamp()+interval '30 days');
 IF p_command IS NULL OR p_delivery->>'tokenHash' IS NULL OR p_delivery->>'tokenHash' !~ '^[0-9a-f]{64}$'
 OR p_delivery->>'contentHash' IS NULL OR p_delivery->>'contentHash' !~ '^[0-9a-f]{64}$'
 OR jsonb_typeof(p_delivery->'sealed') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'INVALID_OVERVIEW_SOURCE'; END IF;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,kind,expires_at)
 VALUES(p_delivery->>'tokenHash',occ.organization,o.form,o.id,'order_view',expiry);
 INSERT INTO eshop.order_overview_sources(token_hash,sealed,content_hash,expires_at,command_id)
 VALUES(p_delivery->>'tokenHash',p_delivery->'sealed',p_delivery->>'contentHash',expiry,p_command);
END $$;
REVOKE ALL ON FUNCTION public.issue_order_overview_internal(bigint,jsonb,uuid) FROM PUBLIC,anon,authenticated;

-- Called only by trusted Edge after authentication. A view capability can never resolve write scope.
CREATE OR REPLACE FUNCTION public.resolve_customer_order_access_v1(p_token text,p_order_id bigint,p_offer_id uuid,
 p_command_id uuid,p_delivery jsonb DEFAULT NULL,p_actor uuid DEFAULT NULL,p_reissue boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; c eshop.waitlist_capabilities; s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_offer_id IS NOT NULL THEN
  IF p_order_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer_id AND order_id=p_order_id) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT order_id INTO p_order_id FROM eshop.waitlist_offers WHERE id=p_offer_id;
 END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL FOR UPDATE;
 SELECT * INTO STRICT f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF p_reissue THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=o.id AND kind='manage' AND form_id=f.id AND organization_id=occ.organization) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  IF NOT public.can_write_orders_as_actor_internal(p_actor,occ.id) THEN
   RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 ELSE
  IF o.state<>'waitlisted' OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted') THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
  SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
   AND order_id=o.id AND form_id=f.id AND organization_id=occ.organization AND revoked_at IS NULL
   AND (expires_at IS NULL OR expires_at>statement_timestamp())
   AND ((p_offer_id IS NULL AND kind='manage') OR (kind='offer' AND offer_id=p_offer_id));
  IF p_token IS NULL OR length(p_token)<>64 OR c.token_hash IS NULL OR (p_offer_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots x ON x.offer_id=w.id
   WHERE w.id=p_offer_id AND w.order_id=o.id AND w.form_id=f.id AND w.expires_at>statement_timestamp() AND x.outcome='pending')) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 END IF;
 -- Command replay precedes rotation. It never resurrects a revoked/expired generation.
 SELECT src.* INTO s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE cap.order_id=o.id AND cap.kind='order_view' AND cap.revoked_at IS NULL
 AND cap.expires_at>statement_timestamp() AND src.expires_at=cap.expires_at
 AND (NOT p_reissue OR src.command_id=p_command_id) ORDER BY src.created_at DESC LIMIT 1;
 IF s.token_hash IS NULL AND p_delivery IS NOT NULL THEN
  IF p_reissue AND EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=o.id
   AND data->>'action'='order_overview_reissued' AND data->>'commandId'=p_command_id::text) THEN
   RAISE EXCEPTION 'OVERVIEW_REISSUE_REQUIRED'; END IF;
  IF NOT p_reissue AND EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=o.id AND kind='order_view') THEN
   RAISE EXCEPTION 'OVERVIEW_REISSUE_REQUIRED'; END IF;
  IF p_reissue THEN UPDATE eshop.waitlist_capabilities SET revoked_at=statement_timestamp() WHERE order_id=o.id AND kind='order_view' AND revoked_at IS NULL; END IF;
  PERFORM public.issue_order_overview_internal(o.id,p_delivery,p_command_id);
  IF p_reissue THEN INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,o.state,
   jsonb_build_object('action','order_overview_reissued','commandId',p_command_id,'actor',p_actor)); END IF;
  SELECT * INTO s FROM eshop.order_overview_sources WHERE command_id=p_command_id;
 END IF;
 RETURN jsonb_build_object('code',200,'orderId',o.id,'formLink',f.link,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,
  'orderSymbol',o.order_symbol,
  'email',(SELECT jsonb_build_object('message_id',message_id,'workflow_state',workflow_state) FROM public.email_messages WHERE dedupe_key='order-overview:'||p_command_id::text AND order_id=o.id),
  'recipient',o.data->>'email','occasionTitle',occ.title,'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
  'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=occ.organization),
  'source',CASE WHEN s.token_hash IS NOT NULL THEN jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,'expiresAt',s.expires_at) END);
END $$;
REVOKE ALL ON FUNCTION public.resolve_customer_order_access_v1(text,bigint,uuid,uuid,jsonb,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_customer_order_access_v1(text,bigint,uuid,uuid,jsonb,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_order_overview_sources_internal(p_limit integer DEFAULT 200)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 DELETE FROM eshop.order_overview_sources WHERE token_hash IN
 (SELECT token_hash FROM eshop.order_overview_sources WHERE expires_at<statement_timestamp() ORDER BY expires_at LIMIT least(greatest(p_limit,0),1000));
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.cleanup_order_overview_sources_internal(integer) FROM PUBLIC,anon,authenticated;

-- Registration replay reads its original encrypted generation, never the freshly
-- prepared retry candidate. Raw URLs are added by Edge after the durable receipt.
CREATE OR REPLACE FUNCTION public.get_registered_order_overview_source_v1(p_order_id bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; f public.forms; s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO STRICT f FROM public.forms WHERE id=o.form AND occasion=o.occasion;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 SELECT src.* INTO STRICT s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities c USING(token_hash)
 WHERE src.command_id=p_command_id AND c.order_id=o.id AND c.form_id=f.id AND c.organization_id=occ.organization
 AND c.kind='order_view' AND c.revoked_at IS NULL AND c.expires_at>statement_timestamp() AND src.expires_at=c.expires_at;
 RETURN jsonb_build_object('orderId',o.id,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
 'recipient',o.data->>'email','webLink',(SELECT data->>'DEFAULT_URL' FROM organizations WHERE id=occ.organization),
 'source',jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash));
END $$;
REVOKE ALL ON FUNCTION public.get_registered_order_overview_source_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_registered_order_overview_source_v1(bigint,uuid) TO service_role;
