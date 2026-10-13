-- Count-aware waitlist instructions and shared authoritative display timezone.

-- Source: database/functions/eshop_waitlist/email_render_context.sql
-- Shared presentation metadata; no lifecycle or capability decisions.
CREATE OR REPLACE FUNCTION public.get_waitlist_form_timezone_internal(p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(occasion_zone.name,unit_zone.name,organization_zone.name,'Europe/Prague')
 FROM public.forms f JOIN public.occasions occ ON occ.id=f.occasion
 LEFT JOIN public.units u ON u.id=occ.unit
 LEFT JOIN public.organizations org ON org.id=occ.organization
 LEFT JOIN pg_timezone_names occasion_zone ON occasion_zone.name=nullif(occ.data->>'timezone','')
 LEFT JOIN pg_timezone_names unit_zone ON unit_zone.name=nullif(u.data->>'timezone','')
 LEFT JOIN pg_timezone_names organization_zone ON organization_zone.name=nullif(org.data->>'timezone','')
 WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_form_timezone_internal(bigint) FROM PUBLIC,anon,authenticated;

-- One presentation vocabulary for both gated delivery and authenticated preview.
-- The existing effective-form resolver owns tone inheritance.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_tone_substitutions_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object(
  'waitlist_offer_button_single','Potvrdit přihlášení',
  'waitlist_offer_button_multiple','Potvrdit vybrané osoby',
  'waitlist_manage_button_label','Spravovat čekání',
  'waitlist_confirmation_heading',CASE WHEN informal THEN 'Jsi mezi náhradníky' ELSE 'Jste mezi náhradníky' END,
  'waitlist_confirmation_explanation',CASE WHEN informal THEN 'Zatím nic neplatíš. Jakmile se uvolní místo, pošleme ti nabídku. Čekání můžeš spravovat nebo ukončit přes tento odkaz:' ELSE 'Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:' END,
  'waitlist_offer_heading',CASE WHEN informal THEN 'Máme pro tebe nabídku' ELSE 'Máme pro vás nabídku' END,
  'waitlist_offer_instructions_single',CASE WHEN informal THEN 'Po otevření nabídky doplníš údaje a vybereš produkty podle aktuální dostupnosti. Přihlášení pak potvrdíš.' ELSE 'Po otevření nabídky doplníte údaje a vyberete produkty podle aktuální dostupnosti. Přihlášení pak potvrdíte.' END,
  'waitlist_offer_instructions',CASE WHEN informal THEN 'Po otevření nabídky vybereš, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíš.' ELSE 'Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.' END)
 FROM (SELECT coalesce(public.get_effective_form_data(p_form)->>'communication_tone','formal')='informal' informal) tone;
$$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_tone_substitutions_internal(bigint) FROM PUBLIC,anon,authenticated;

-- Private queue renderer boundary. Personal capabilities remain encrypted in
-- existing queue sources; the renderer receives only their hashes and envelopes.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_render_context_v1(
 p_order_id bigint,p_offer_id uuid DEFAULT NULL,p_recipient text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; org public.organizations;
 manage_message public.email_messages; manage_cap eshop.waitlist_capabilities;
 source_cap eshop.waitlist_capabilities; v_recipient text; v_timezone text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO f FROM public.forms WHERE id=o.form;
 SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 SELECT * INTO org FROM public.organizations WHERE id=occ.organization;
 IF o.id IS NULL OR f.id IS NULL OR f.occasion<>occ.id OR o.state<>'waitlisted'
 OR (p_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers
  WHERE id=p_offer_id AND order_id=o.id AND form_id=f.id AND expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending'))) THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 v_timezone:=public.get_waitlist_form_timezone_internal(f.id);
 v_recipient:=coalesce(p_recipient,o.data->>'email');
 SELECT * INTO manage_message FROM public.email_messages m
 WHERE m.order_id=o.id AND m.message_kind='waitlist_confirmation'
 AND m.recipient=v_recipient
 AND m.data ? 'waitlistEnvelope' ORDER BY m.id LIMIT 1;
 SELECT * INTO manage_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id
 AND kind='manage' AND revoked_at IS NULL;
 SELECT * INTO source_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id AND revoked_at IS NULL
 AND CASE WHEN p_offer_id IS NULL THEN kind='manage'
  ELSE kind='offer' AND offer_id=p_offer_id AND expires_at>clock_timestamp() END;
 IF manage_message.id IS NULL OR manage_cap.token_hash IS NULL OR source_cap.token_hash IS NULL THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 RETURN jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,
  'organization',org.id,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
  'webLink',org.data->>'DEFAULT_URL','replyTo',public.get_reply_to_email_for_order(o.id),
  'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(o.id)),
  'offeredCount',(SELECT count(*) FROM eshop.waitlist_offer_slots
    WHERE offer_id=p_offer_id AND outcome='pending'),
  'timeZone',v_timezone,
  'communicationTone',public.get_effective_form_data(f.id)->>'communication_tone',
  'toneSubstitutions',public.get_waitlist_email_tone_substitutions_internal(f.id),
  'expiresAt',(SELECT expires_at FROM eshop.waitlist_offers WHERE id=p_offer_id),
  'tokenHash',source_cap.token_hash,'manageTokenHash',manage_cap.token_hash,
  'manageEnvelope',manage_message.data->'waitlistEnvelope',
  'manageContentHash',manage_message.data->>'content_hash');
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 TO service_role;


-- Source: database/functions/eshop_waitlist/email_preview.sql
-- An editor preview resolves the same inherited template/wrapper as delivery.
-- It never creates a capability, offer, intent, or reservation.
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_email_preview(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE f public.forms; occ public.occasions; resolved jsonb; tone jsonb;
 v_key text; v_value text; html text; subject text; v_timezone text; instructions_html text;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 resolved:=public.get_email_template_and_wrapper('waitlist_offer',
  jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit));
 -- Match the trusted delivery context's existing occasion/unit/org fallback.
 v_timezone:=public.get_waitlist_form_timezone_internal(f.id);
 -- Older preview clients know order/count/date variables, but not the new
 -- semantic copy keys. Expand only trusted copy here; leave those old keys.
 tone:=public.get_waitlist_email_tone_substitutions_internal(f.id);
 html:=resolved#>>'{template,html}'; subject:=resolved#>>'{template,subject}';
 instructions_html:=html;
 FOR v_key,v_value IN SELECT key,value FROM jsonb_each_text(tone) LOOP
  v_value:=replace(replace(replace(replace(replace(v_value,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),chr(39),'&#39;');
  html:=replace(html,'{{'||v_key||'}}',v_value);
  IF v_key<>'waitlist_offer_instructions' THEN
   instructions_html:=replace(instructions_html,'{{'||v_key||'}}',v_value);
  END IF;
  subject:=replace(subject,'{{'||v_key||'}}',v_value);
 END LOOP;
 IF html IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template,html}',to_jsonb(html)); END IF;
 IF subject IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template,subject}',to_jsonb(subject)); END IF;
 RETURN resolved||jsonb_build_object('code',200,'occasionTitle',occ.title,'formLink',f.link,
 'timeZone',v_timezone,'instructionsTemplateHtml',instructions_html,
 'communicationTone',public.get_effective_form_data(f.id)->>'communication_tone',
 'toneSubstitutions',tone);
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_email_preview(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_email_preview(bigint) TO authenticated;


-- Source: database/functions/eshop_waitlist/capabilities.sql
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
 IF p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=o.occasion AND "user"=p_actor AND is_editor_order) THEN
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
CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH effective AS (SELECT public.get_effective_waitlist_ticket_lifecycle_internal(person.id) lifecycle
 FROM public.get_order_tickets_internal(p_order) person), p AS (SELECT lifecycle,count(*) n FROM effective GROUP BY lifecycle),
 s AS (SELECT count(*) n,min(w.expires_at) expiry FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers w ON w.id=x.offer_id
 JOIN public.get_order_tickets_internal(p_order) person ON person.id=x.ticket_id WHERE true AND x.outcome='pending' AND w.expires_at>clock_timestamp())
 SELECT jsonb_build_object('counts',coalesce((SELECT jsonb_object_agg(lifecycle,n) FROM p),'{}'),
 'pendingPlaces',s.n,'earliestExpiry',s.expiry,'isActive',CASE WHEN o.state='waitlisted' THEN
  coalesce((SELECT n>0 FROM p WHERE lifecycle='waiting'),false) OR s.n>0 ELSE o.state IS DISTINCT FROM 'storno' END,
 'allowedActions',CASE WHEN o.state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN o.state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN o.state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END)
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
 IF NOT public.get_is_editor_order_view_on_occasion(o.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Order viewer required'; END IF;
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
