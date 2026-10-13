-- Forward-only waitlist email copy and trusted occasion timezone.
-- Private queue renderer boundary. Personal capabilities remain encrypted in
-- existing queue sources; the renderer receives only their hashes and envelopes.
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
  'expiresAt',(SELECT expires_at FROM eshop.waitlist_offers WHERE id=p_offer_id),
  'tokenHash',source_cap.token_hash,'manageTokenHash',manage_cap.token_hash,
  'manageEnvelope',manage_message.data->'waitlistEnvelope',
  'manageContentHash',manage_message.data->>'content_hash');
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 TO service_role;

UPDATE public.email_templates SET subject='Potvrzení zařazení mezi náhradníky - {{occasion_title}}',html='<h2>Jste mezi náhradníky</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:</p><p>{{manage_waitlist_button}}</p>' WHERE code='waitlist_confirmation' AND organization IS NULL AND unit IS NULL AND occasion IS NULL AND subject='Potvrzení zařazení mezi náhradníky - {{occasion_title}}' AND html='<h2>Jste v pořadníku náhradníků</h2><p>Potvrzujeme přihlášení na {{occasion_title}}. Číslo přihlášky: <strong>{{order_symbol}}</strong>. Počet osob: {{participant_count}}.</p><p>Zatím nic neplatíte a nevybíráte produkty. Pokud se uvolní místa, pošleme vám nabídku.</p><p>{{manage_waitlist_button}}</p><p>Vlastní čekání můžete ukončit jednotlivě. Tento odkaz neslouží ke stornu již potvrzené objednávky.</p>';
UPDATE public.email_templates SET subject='Nabídka pro {{offered_places}} - {{occasion_title}}',html='<h2>Máme pro vás nabídku</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do {{offer_expires_at}}.</p><p>Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.</p><p>{{offer_button}}</p><p>{{manage_waitlist_button}}</p>' WHERE code='waitlist_offer' AND organization IS NULL AND unit IS NULL AND occasion IS NULL AND subject='Nabídka {{offered_count}} míst - {{occasion_title}}' AND html='<h2>Máme pro vás volná místa</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_count}} míst z celkových {{participant_count}} osob. Platnost nabídky: {{offer_expires_at}} (UTC).</p><p>Po otevření nabídky vyberete osoby a produkty a objednávku výslovně potvrdíte. Produkty nejsou rezervované; vybíráte je podle aktuální dostupnosti. Samotné otevření odkazu nic nepotvrzuje.</p><p>{{offer_button}}</p><p>Nepřijatá místa zůstávají do konce platnosti nabídky k dispozici. Čekání lze spravovat zde:</p><p>{{manage_waitlist_button}}</p>';

-- Global defaults participate in the existing occasion/unit/organization
-- inheritance. Never overwrite an editor's custom content.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,v.subject,v.html FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasion_title}}',
  '<h2>Jste mezi náhradníky</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:</p><p>{{manage_waitlist_button}}</p>'),
 ('waitlist_offer','Nabídka pro {{offered_places}} - {{occasion_title}}',
  '<h2>Máme pro vás nabídku</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do {{offer_expires_at}}.</p><p>Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.</p><p>{{offer_button}}</p><p>{{manage_waitlist_button}}</p>')
) v(code,subject,html)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);
