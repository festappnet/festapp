-- Global defaults participate in the existing occasion/unit/organization
-- inheritance. Never overwrite an editor's custom content.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,v.subject,v.html FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasion_title}}',
  '<h2>{{waitlist_confirmation_heading}}</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>{{waitlist_confirmation_explanation}}</p><p>{{manage_waitlist_button}}</p>'),
 ('waitlist_offer','Nabídka pro {{offered_places}} - {{occasion_title}}',
  '<h2>{{waitlist_offer_heading}}</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do <span style="white-space:nowrap">{{offer_expires_at}}</span>.</p><p>{{waitlist_offer_instructions}}</p><p>{{offer_button}}</p>')
) v(code,subject,html)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);

-- Adopt tone substitutions only for byte-exact uncustomized application defaults.
UPDATE public.email_templates t SET html=v.html
FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasion_title}}','<h2>Jste mezi náhradníky</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>Zatím nic neplatíte. Jakmile se uvolní místo, pošleme vám nabídku. Čekání můžete spravovat nebo ukončit přes tento odkaz:</p><p>{{manage_waitlist_button}}</p>','<h2>{{waitlist_confirmation_heading}}</h2><p>Potvrzujeme přihlášku <strong>{{order_symbol}}</strong> pro {{participant_phrase}} na {{occasion_title}}.</p><p>{{waitlist_confirmation_explanation}}</p><p>{{manage_waitlist_button}}</p>'),
 ('waitlist_offer','Nabídka pro {{offered_places}} - {{occasion_title}}','<h2>Máme pro vás nabídku</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do {{offer_expires_at}}.</p><p>Po otevření nabídky vyberete, kdo přijde, a produkty podle aktuální dostupnosti. Objednávku pak potvrdíte.</p><p>{{offer_button}}</p><p>{{manage_waitlist_button}}</p>','<h2>{{waitlist_offer_heading}}</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_places}}. Nabídka platí do <span style="white-space:nowrap">{{offer_expires_at}}</span>.</p><p>{{waitlist_offer_instructions}}</p><p>{{offer_button}}</p>')
) v(code,subject,previous_html,html)
WHERE t.code=v.code AND t.subject=v.subject AND t.html=v.previous_html
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL;
