-- Global defaults participate in the existing occasion/unit/organization
-- inheritance. Never overwrite an editor's custom content.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,v.subject,v.html FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasionTitle}}',
  '<h2>{{waitlist_confirmation_heading}}</h2><p>Potvrzujeme přihlášku <strong>{{orderSymbol}}</strong> pro {{participant_phrase}} na {{occasionTitle}}.</p><p>{{waitlist_confirmation_explanation}}</p><p>{{manage_waitlist_button}}</p>'),
 ('waitlist_offer','Nabídka pro {{offered_places}} - {{occasionTitle}}',
  '<h2>{{waitlist_offer_heading}}</h2><p>Pro přihlášku <strong>{{orderSymbol}}</strong> na {{occasionTitle}} nabízíme {{offered_places}}. Nabídka platí do <span style="white-space:nowrap">{{offer_expires_at}}</span>.</p><p>{{waitlist_offer_instructions}}</p><p>{{offer_button}}</p>')
) v(code,subject,html)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);
