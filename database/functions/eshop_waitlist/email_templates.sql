-- Global defaults participate in the existing occasion/unit/organization
-- inheritance. Never overwrite an editor's custom content.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,v.subject,v.html FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasion_title}}',
  '<h2>Jste v pořadníku náhradníků</h2><p>Potvrzujeme přihlášení na {{occasion_title}}. Číslo přihlášky: <strong>{{order_symbol}}</strong>. Počet osob: {{participant_count}}.</p><p>Zatím nic neplatíte a nevybíráte produkty. Pokud se uvolní místa, pošleme vám nabídku.</p><p>{{manage_waitlist_button}}</p><p>Vlastní čekání můžete ukončit jednotlivě. Tento odkaz neslouží ke stornu již potvrzené objednávky.</p>'),
 ('waitlist_offer','Nabídka {{offered_count}} míst - {{occasion_title}}',
  '<h2>Máme pro vás volná místa</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_count}} míst z celkových {{participant_count}} osob. Platnost nabídky: {{offer_expires_at}} (UTC).</p><p>Po otevření nabídky vyberete osoby a produkty a objednávku výslovně potvrdíte. Produkty nejsou rezervované; vybíráte je podle aktuální dostupnosti. Samotné otevření odkazu nic nepotvrzuje.</p><p>{{offer_button}}</p><p>Nepřijatá místa zůstávají do konce platnosti nabídky k dispozici. Čekání lze spravovat zde:</p><p>{{manage_waitlist_button}}</p>')
) v(code,subject,html)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);
