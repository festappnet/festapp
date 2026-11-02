-- Apply ONLY to the owned disposable embed backend, after tenant.sql and fixture-fixes.sql.
-- psql -v help_locale=cs -f automation/help_capture/localize_embed_fixture.sql
-- Repeat with help_locale=en before English captures. Original fixture links remain reserved as stable aliases.
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('festapp.help_capture_locale', :'help_locale', true);
DO $$
DECLARE
 locale text := current_setting('festapp.help_capture_locale');
 oc bigint;
 labels jsonb;
BEGIN
 IF locale NOT IN ('cs','en') THEN RAISE EXCEPTION 'Expected help_locale=cs or en'; END IF;
 IF (SELECT count(*) FROM public.organizations)<>1 OR
    (SELECT title FROM public.organizations WHERE id=1)<>'Test Organization' THEN
  RAISE EXCEPTION 'Owned disposable embed backend required';
 END IF;
 SELECT id INTO STRICT oc FROM public.occasions WHERE link='embedded-event' AND organization=1;
 IF NOT EXISTS(SELECT 1 FROM public.form_link_reservations r JOIN public.forms f ON f.id=r.form WHERE f.occasion=oc AND r.slug='embedded-seats') THEN
  RAISE EXCEPTION 'Embed seating fixture required';
 END IF;
 labels := CASE locale WHEN 'cs' THEN
  '{"event":"Slavnostní ples U Lípy","form":"Vstupenky na ples U Lípy","seats":"Vstupenky s místenkou","plan":"Plánek sálu","organizer":"Spolek U Lípy","bank":"Účet pořadatele","admission":"Vstupenka","tickets":"Vstupenky","email":"E-mail","name":"Jméno","surname":"Příjmení","spot":"Místo","birth_date":"Datum narození","closed":"Prodej vstupenek byl ukončen.","waitlist":"Náhradníci na ples U Lípy","information":"Zveme Vás na slavnostní ples s živou hudbou. Vyberte si vstupenky a místa v sále.","street":"Lipová 12","city":"Praha"}'::jsonb
 ELSE
  '{"event":"Linden Hall Ball","form":"Tickets for the Linden Hall Ball","seats":"Tickets with reserved seats","plan":"Seating plan","organizer":"Linden Hall Association","bank":"Organizer account","admission":"Admission","tickets":"Tickets","email":"Email","name":"First name","surname":"Last name","spot":"Seat","birth_date":"Date of birth","closed":"Ticket sales have closed.","waitlist":"Linden Hall Ball waiting list","information":"Join us for a ball with live music. Choose your tickets and seats in the hall.","street":"12 Linden Street","city":"Prague"}'::jsonb END;
 UPDATE public.occasions SET title=labels->>'event' WHERE id=oc;
 UPDATE public.forms f SET title=labels->>CASE r.slug
  WHEN 'embedded-seats' THEN 'seats' WHEN 'embedded-waitlist' THEN 'waitlist'
  WHEN 'embedded-closed' THEN 'closed' ELSE 'form' END,
  header=CASE WHEN r.slug='embedded-closed' THEN header ELSE
   '<h1>'||(labels->>CASE r.slug WHEN 'embedded-seats' THEN 'seats' WHEN 'embedded-waitlist' THEN 'waitlist' ELSE 'form' END)||'</h1><p>'||(labels->>'information')||'</p>' END,
  header_off=CASE WHEN r.slug='embedded-closed' THEN '<p>'||(labels->>'closed')||'</p>' ELSE header_off END
 FROM public.form_link_reservations r
 WHERE f.occasion=oc AND r.form=f.id AND r.slug IN ('embedded-synthetic','embedded-seats','embedded-closed','embedded-waitlist');
 -- Public examples use natural links; original fixture aliases keep resolving.
 UPDATE public.forms f SET link=public.reserve_public_link_internal('form',f.id,
  (CASE locale WHEN 'cs' THEN 'ples-u-lipy' ELSE 'linden-hall-ball' END)||
  CASE r.slug WHEN 'embedded-seats' THEN CASE locale WHEN 'cs' THEN '-mistenky' ELSE '-seats' END
   WHEN 'embedded-closed' THEN CASE locale WHEN 'cs' THEN '-ukonceno' ELSE '-closed' END
   WHEN 'embedded-waitlist' THEN CASE locale WHEN 'cs' THEN '-nahradnici' ELSE '-waiting-list' END ELSE '' END,true)
 FROM public.form_link_reservations r
 WHERE f.occasion=oc AND r.form=f.id AND r.slug IN ('embedded-synthetic','embedded-seats','embedded-closed','embedded-waitlist');
 UPDATE eshop.blueprints SET title=labels->>'plan' WHERE occasion=oc;
 UPDATE eshop.product_types SET title=labels->>'admission' WHERE occasion=oc;
 UPDATE eshop.products SET title=labels->>'admission'
 WHERE product_type IN (SELECT id FROM eshop.product_types WHERE occasion=oc);
 UPDATE public.form_fields SET title=labels->>CASE type WHEN 'ticket' THEN 'tickets' WHEN 'product_type' THEN 'admission' ELSE type END
 WHERE form IN (SELECT id FROM public.forms WHERE occasion=oc)
 AND type IN ('email','ticket','product_type','name','surname','spot','birth_date');
 UPDATE public.unit_legal_profiles SET legal_name=labels->>'organizer',street=labels->>'street',city=labels->>'city',postal_code='11000'
 WHERE unit_id=1;
 UPDATE eshop.bank_accounts SET title=labels->>'bank',creditor_name=labels->>'organizer'
 WHERE id IN (SELECT bank_account FROM eshop.unit_bank_accounts WHERE unit=1);
END $$;
COMMIT;
