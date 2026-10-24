-- Explicit editor redelivery uses the existing encrypted prepared-email path.
-- It shares the global send gate, rate limits, pause and provider worker.
INSERT INTO public.email_templates(code,subject,html)
SELECT 'ORDER_OVERVIEW','Přehled objednávky - {{occasion_title}}',
 '<h2>{{occasion_title}}</h2><p>Přehled přihlášky {{order_symbol}}, objednávek, evidovaných úhrad a vstupenek:</p><p>{{order_overview_button}}</p>'
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates WHERE code='ORDER_OVERVIEW' AND organization IS NULL AND unit IS NULL AND occasion IS NULL);
CREATE OR REPLACE FUNCTION public.enqueue_order_overview_reissue_v1(p_order_id bigint,p_command_id uuid,p_actor uuid,p_prepared jsonb,p_content_hash text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; s eshop.order_overview_sources; result jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ.id AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 SELECT src.* INTO STRICT s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE src.command_id=p_command_id AND cap.order_id=o.id AND cap.form_id=o.form AND cap.organization_id=occ.organization
 AND cap.kind='order_view' AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp() AND src.expires_at=cap.expires_at;
 IF jsonb_typeof(p_prepared) IS DISTINCT FROM 'object' OR p_content_hash IS NULL OR p_content_hash !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_OVERVIEW_SOURCE'; END IF;
 result:=public.enqueue_email('custom',jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit,'actor_id',p_actor),
 o.data->>'email',jsonb_build_object('content_hash',p_content_hash,'order_overview_command',p_command_id),
 'order-overview:'||p_command_id::text,'ORDER_OVERVIEW',now(),s.expires_at,o.id,NULL);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),
 prepared_at=coalesce(prepared_at,now()),tracking_policy='disabled'
 WHERE message_id=(result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(result->>'message_id')::uuid),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text) TO service_role;
