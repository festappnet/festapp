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
 SELECT name INTO v_timezone FROM pg_timezone_names WHERE name=nullif(occ.data->>'timezone','');
 IF v_timezone IS NULL THEN
  SELECT zone.name INTO v_timezone FROM public.units u JOIN pg_timezone_names zone
   ON zone.name=nullif(u.data->>'timezone','') WHERE u.id=occ.unit;
 END IF;
 IF v_timezone IS NULL THEN
  SELECT name INTO v_timezone FROM pg_timezone_names WHERE name=nullif(org.data->>'timezone','');
 END IF;
 -- Same timezone key as occasions/units; TimeHelper's canonical default is Europe/Prague.
 v_timezone:=coalesce(v_timezone,'Europe/Prague');
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
