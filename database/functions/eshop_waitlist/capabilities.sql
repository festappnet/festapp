-- Only visible name/surname definitions in this form can label a ticket.
CREATE OR REPLACE FUNCTION public.get_waitlist_ticket_display_name_internal(p_form bigint,p_answers jsonb,p_contact jsonb DEFAULT '{}')
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(nullif((SELECT string_agg(btrim(answer.value#>>'{}'),' ' ORDER BY CASE definition.type WHEN 'name' THEN 0 ELSE 1 END,definition."order" NULLS LAST,definition.id)
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_answers->'fields')='array' THEN p_answers->'fields' ELSE '[]' END) field
 CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(field)='object' THEN field ELSE '{}' END) answer
 JOIN public.form_fields definition ON definition.id::text=answer.key
 WHERE definition.form=p_form AND definition.is_ticket_field AND NOT definition.is_hidden
 AND definition.type IN ('name','surname') AND jsonb_typeof(answer.value)='string' AND btrim(answer.value#>>'{}')<>''),''),
 nullif(btrim(concat_ws(' ',nullif(btrim(p_contact->>'name'),''),nullif(btrim(p_contact->>'surname'),''))),''));
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_ticket_display_name_internal(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(p_ticket bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN t.state='storno' THEN CASE WHEN t.ticket_symbol IS NULL THEN 'withdrawn' ELSE 'cancelled' END
 WHEN t.state IS DISTINCT FROM 'waitlisted' THEN 'admitted'
 WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id AND s.outcome='pending' AND w.expires_at>clock_timestamp()) THEN 'offered'
 ELSE coalesce((SELECT CASE s.outcome WHEN 'expired' THEN 'offer_expired' WHEN 'declined' THEN 'offer_declined' WHEN 'cancelled' THEN 'offer_cancelled' WHEN 'pending' THEN 'offer_expired' ELSE 'waiting' END
 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id WHERE s.ticket_id=t.id ORDER BY w.created_at DESC,s.updated_at DESC,s.id DESC LIMIT 1),'waiting') END
 FROM eshop.tickets t WHERE t.id=p_ticket;
$$;
REVOKE ALL ON FUNCTION public.get_effective_waitlist_ticket_lifecycle_internal(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.check_waitlist_scope_internal(p_order bigint,p_offer uuid,p_token text,p_actor uuid,p_operation text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; c eshop.waitlist_capabilities; occ public.occasions;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order; SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 IF o.id IS NULL OR o.form IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_actor IS NOT NULL AND public.order_editor_membership_as_actor_internal(p_actor,o.occasion) THEN
  IF p_offer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order AND form_id=o.form) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF; RETURN o.form;
 END IF;
 IF p_operation IN ('send','cancel','proposal') OR p_token IS NULL OR length(p_token)<>64 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND organization_id=occ.organization AND form_id=o.form AND order_id=o.id AND (revoked_at IS NULL OR p_operation='read')
 AND ((p_operation='withdraw' AND kind='manage' AND o.state='waitlisted') OR
 (p_operation IN ('read','accept','decline') AND kind='offer' AND offer_id=p_offer));
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Expired offer links may read their own terminal state; writers recheck time under locks.
 IF p_operation<>'read' AND c.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 RETURN o.form;
END $$;
-- Action/activity policy is shared by compact ordinary orders and full waitlist summaries.
CREATE OR REPLACE FUNCTION public.get_order_action_summary_internal(
 p_state text, p_has_waiting boolean DEFAULT false, p_pending_places bigint DEFAULT 0
) RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('isActive',CASE WHEN p_state='waitlisted' THEN
  coalesce(p_has_waiting,false) OR coalesce(p_pending_places,0)>0 ELSE p_state IS DISTINCT FROM 'storno' END,
 'allowedActions',CASE WHEN p_state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN p_state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN p_state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END);
$$;
REVOKE ALL ON FUNCTION public.get_order_action_summary_internal(text,boolean,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH effective AS (SELECT public.get_effective_waitlist_ticket_lifecycle_internal(person.id) lifecycle
 FROM public.get_order_tickets_internal(p_order) person), p AS (SELECT lifecycle,count(*) n FROM effective GROUP BY lifecycle),
 s AS (SELECT count(*) n,min(w.expires_at) expiry FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers w ON w.id=x.offer_id
 JOIN public.get_order_tickets_internal(p_order) person ON person.id=x.ticket_id WHERE true AND x.outcome='pending' AND w.expires_at>clock_timestamp())
 SELECT jsonb_build_object('counts',coalesce((SELECT jsonb_object_agg(lifecycle,n) FROM p),'{}'),
 'pendingPlaces',s.n,'earliestExpiry',s.expiry) || public.get_order_action_summary_internal(
 o.state,coalesce((SELECT n>0 FROM p WHERE lifecycle='waiting'),false),s.n)
 FROM eshop.orders o CROSS JOIN s WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_form(p_token text DEFAULT NULL,p_offer_id uuid DEFAULT NULL,p_order_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oid bigint; fid bigint; bundle jsonb; w eshop.waitlist_offers;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO w FROM eshop.waitlist_offers WHERE id=p_offer_id;
 oid:=coalesce(w.order_id,p_order_id);
 fid:=public.check_waitlist_scope_internal(oid,p_offer_id,p_token,auth.uid(),CASE WHEN p_offer_id IS NULL THEN 'withdraw' ELSE 'read' END);
 -- Terminal links explain their own outcome without exposing form answers,
 -- contact data, products, or payment details after capability revocation.
 IF p_offer_id IS NOT NULL AND (w.expires_at<=clock_timestamp() OR NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending')) THEN
  RETURN jsonb_build_object('code',200,'registrationMode','offer',
   'occasionTitle',(SELECT title FROM public.occasions WHERE id=(SELECT occasion FROM eshop.orders WHERE id=oid)),
   'orderSymbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),
   'timeZone',public.get_waitlist_form_timezone_internal(fid),
   'communicationTone',public.get_effective_form_data(fid)->>'communication_tone',
   'form',NULL,'formLink',(SELECT link FROM public.forms WHERE id=fid),
   'organizationIdentity',(SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.forms f JOIN public.occasions o ON o.id=f.occasion JOIN public.units u ON u.id=o.unit WHERE f.id=fid),
   'offerId',w.id,'pendingCount',0,'expiresAt',w.expires_at,'serverTime',clock_timestamp(),
   'offerStatus',CASE
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='declined') THEN 'declined'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='cancelled') THEN 'cancelled'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND (outcome='expired' OR outcome='pending' AND w.expires_at<=clock_timestamp())) THEN 'expired'
    ELSE 'accepted' END,'tickets','[]'::jsonb,'slots','[]'::jsonb);
 END IF;
 -- A revoked token can explain a terminal outcome above, never reopen live data.
 IF p_token IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.waitlist_capabilities
  WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND revoked_at IS NOT NULL) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY';
 END IF;
 bundle:=public.get_form_bundle_internal(fid,true)::jsonb;
 bundle:=jsonb_set(bundle,'{data,registrationMode}',to_jsonb(CASE WHEN p_offer_id IS NOT NULL THEN 'offer'::text ELSE 'waitlist' END),true);
 RETURN jsonb_build_object('code',200,'form',bundle->'data','registrationMode',CASE WHEN p_offer_id IS NOT NULL THEN 'offer' ELSE 'waitlist' END,
  'timeZone',public.get_waitlist_form_timezone_internal(fid),
  'orderSymbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),
  'occasionTitle',(SELECT occ.title FROM public.occasions occ JOIN eshop.orders source ON source.occasion=occ.id WHERE source.id=oid),
  'orderData',(SELECT data FROM eshop.orders WHERE id=oid),'pendingCount',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending' AND w.expires_at>clock_timestamp()),
  'orderId',oid,'offerId',p_offer_id,'serverTime',clock_timestamp(),'expiresAt',w.expires_at,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'displayName',public.get_waitlist_ticket_display_name_internal(fid,data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(oid))=1 THEN (SELECT source.data FROM eshop.orders source WHERE source.id=oid) ELSE '{}'::jsonb END),'answers',public.extract_ticket_answers_internal(fid,data),'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(id)) ORDER BY created_at,id),'[]')
   FROM public.get_order_tickets_internal(oid)),
  'slots',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'ticketId',ticket_id,'outcome',CASE WHEN outcome='pending' AND w.expires_at<=clock_timestamp() THEN 'expired' ELSE outcome END)),'[]')
   FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id),'waitlistSummary',public.get_waitlist_summary_internal(oid));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.check_waitlist_scope_internal(bigint,uuid,text,uuid,text),public.get_waitlist_summary_internal(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_waitlist_order_detail(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 IF NOT public.can_read_orders(o.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Order viewer required'; END IF;
 RETURN jsonb_build_object('orderId',o.id,'sourceOrderId',o.source_waitlist_order_id,
 'occasionTitle',(SELECT title FROM public.occasions WHERE id=o.occasion),'waitlistSummary',public.get_waitlist_summary_internal(o.id),
 'capacity',public.get_form_capacity_snapshot_internal(o.form),
 'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'displayName',public.get_waitlist_ticket_display_name_internal(o.form,p.data,CASE WHEN (SELECT count(*) FROM public.get_order_tickets_internal(o.id))=1 THEN o.data ELSE '{}'::jsonb END),'createdAt',p.created_at,'waitlistQueueAt',p.waitlist_queue_at,'answers',public.extract_ticket_answers_internal(o.form,p.data),
  'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id)) ORDER BY created_at,id),'[]') FROM public.get_order_tickets_internal(o.id) p),
 'offers',(SELECT coalesce(jsonb_agg(to_jsonb(w)||jsonb_build_object('slots',(SELECT coalesce(jsonb_agg((to_jsonb(s)-'ticket_id')||jsonb_build_object('ticketId',s.ticket_id)),'[]') FROM eshop.waitlist_offer_slots s WHERE offer_id=w.id)) ORDER BY created_at),'[]')
 FROM eshop.waitlist_offers w WHERE order_id=o.id),
 'linkedOrders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'orderSymbol',order_symbol,'state',state)),'[]') FROM eshop.orders WHERE source_waitlist_order_id=o.id));
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_order_detail(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_order_detail(bigint) TO authenticated;
