-- Source: canonical temporary fixture maintenance in database/fixtures/demo_occasions/seed.sql
-- Synthetic fixture maintenance only. No checkout, email or payment producer is called.
CREATE OR REPLACE FUNCTION pg_temp.refresh_demo_presentation(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $presentation$
DECLARE d record; o record; anchor timestamptz := '2026-10-14 12:00:00+00';
 stamp timestamptz; ticket_state text;
BEGIN
 IF current_user <> 'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 FOR d IN SELECT * FROM public.demo_occasions
   WHERE organization=p_org AND fixture_version='2026-10-14.3' LOOP
  UPDATE public.occasions SET features=(SELECT jsonb_agg(
    CASE WHEN f->>'code'='services' THEN f||'{"is_enabled":false}'::jsonb ELSE f END ORDER BY n)
    FROM jsonb_array_elements(features) WITH ORDINALITY a(f,n)) WHERE id=d.occasion;
  UPDATE public.demo_occasions SET reference_at=anchor WHERE occasion=d.occasion;
  FOR o IN SELECT x.*,row_number() OVER(ORDER BY order_sequence,id) AS seq,
      count(*) OVER() AS total FROM eshop.orders x WHERE occasion=d.occasion LOOP
   -- Spread ordinary sales over six weeks, with recent pending payments.
   stamp := anchor-interval '46 days'+interval '42 days'*
     power(o.seq::double precision/o.total,0.7);
   IF o.state='ordered' THEN
    stamp:=CASE WHEN o.order_sequence=7 THEN anchor-interval '12 days' ELSE anchor-interval '2 days'+o.seq*interval '3 minutes' END;
   END IF;
   UPDATE eshop.orders SET created_at=stamp,updated_at=stamp+interval '36 hours' WHERE id=o.id;
   UPDATE eshop.payment_info SET created_at=stamp,deadline=stamp+interval '7 days' WHERE id=o.payment_info;
   WITH movements AS (SELECT id,row_number() OVER(ORDER BY id) AS n
     FROM eshop.transactions WHERE payment_info=o.payment_info)
   UPDATE eshop.transactions t SET date=stamp+interval '12 hours'*m.n
     FROM movements m WHERE t.id=m.id;
   WITH history AS (SELECT id,row_number() OVER(ORDER BY CASE state WHEN 'waitlisted' THEN 0 WHEN 'ordered' THEN 1 WHEN 'paid' THEN 2 WHEN 'sent' THEN 3 ELSE 4 END,id) AS n
     FROM eshop.orders_history WHERE "order"=o.id)
   UPDATE eshop.orders_history h SET created_at=stamp+interval '6 hours'*history.n
     FROM history WHERE h.id=history.id;
   ticket_state:=CASE WHEN o.state IN ('paid','sent') THEN 'sent' ELSE o.state END;
   UPDATE eshop.orders SET state=ticket_state WHERE id=o.id;
   UPDATE eshop.tickets SET created_at=stamp,updated_at=stamp+interval '36 hours',
      waitlist_queue_at=CASE WHEN waitlist_queue_at IS NOT NULL THEN stamp END,
      state=CASE WHEN state IN ('paid','sent','used') THEN ticket_state ELSE state END
     WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id);
   IF ticket_state='sent' AND NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=o.id AND state='sent') THEN
    INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data)
    VALUES(o.id,stamp+interval '36 hours','sent',o.price,o.currency_code,o.data);
   END IF;
   UPDATE eshop.orders_history SET created_at=stamp+interval '24 hours' WHERE "order"=o.id AND state='paid';
   UPDATE eshop.orders_history SET created_at=stamp+interval '36 hours' WHERE "order"=o.id AND state='sent';
   IF EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id) THEN
    UPDATE eshop.payment_info SET created_at=stamp+interval '24 hours' WHERE id=o.payment_info;
    UPDATE eshop.transactions SET date=stamp+interval '36 hours' WHERE payment_info=o.payment_info;
    UPDATE eshop.orders_history SET created_at=stamp+interval '36 hours' WHERE "order"=o.id AND state='paid';
    UPDATE eshop.orders_history SET created_at=stamp+interval '42 hours' WHERE "order"=o.id AND state='sent';
    UPDATE eshop.orders SET updated_at=stamp+interval '42 hours' WHERE id=o.id;
    UPDATE eshop.tickets SET updated_at=stamp+interval '42 hours' WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id);
   END IF;
   UPDATE eshop.waitlist_offers SET created_at=stamp+interval '12 hours',
     expires_at=stamp+interval '36 hours' WHERE order_id=o.id;
   UPDATE eshop.waitlist_offer_slots SET updated_at=stamp+interval '24 hours'
     WHERE resulting_order_id=o.id;
  END LOOP;
  UPDATE eshop.transactions SET date=anchor-interval '3 days'
   WHERE bank_account_id=d.bank_account AND payment_info IS NULL;
 END LOOP;
END $presentation$;

-- Temporary, explicitly scoped maintenance of registered synthetic demos only.
CREATE OR REPLACE FUNCTION pg_temp.enrich_demo_examples(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $examples$
DECLARE d record; f bigint; item record; bank_display text;
BEGIN
 IF current_user<>'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 -- Copy display text only from the operator's already configured Fio account.
 -- The demo routing number/secret/fetch flag remain disabled and copies never inherit this bank.
 SELECT CASE WHEN count(DISTINCT b.id)=1 THEN min(b.account_number_human_readable) END INTO bank_display
 FROM eshop.bank_accounts b JOIN eshop.unit_bank_accounts ub ON ub.bank_account=b.id
 JOIN public.units u ON u.id=ub.unit
 WHERE p_org=3 AND u.organization=p_org AND b.title='Michael Bujnovsky'
   AND b.account_number_human_readable LIKE '%/2010'
   AND NOT EXISTS(SELECT 1 FROM public.demo_occasions x WHERE x.bank_account=b.id);
 FOR d IN SELECT * FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3' LOOP
  IF bank_display IS NOT NULL THEN
   UPDATE eshop.bank_accounts SET account_number_human_readable=bank_display,
     title='Ukázkový účet - platby se neprovádějí' WHERE id=d.bank_account;
  END IF;
  IF d.demo_key<>'weekend' THEN CONTINUE; END IF;
  SELECT id INTO STRICT f FROM public.forms WHERE occasion=d.occasion AND link='demo-form-'||p_org||'-weekend-20261014-3';
  UPDATE public.forms SET header=$header$
<p><img src="https://vstupenky.online/demo-assets/weekend-nature.jpg" alt="Ukázková chata na louce u lesa" style="width:100%;height:auto;"></p>
<h2>Víkend v přírodě</h2>
<p>Na chvíli vypnout, projít se lesem a potkat nové lidi. Od pátku do neděle nás čeká společné vaření, sobotní výlet, tvořivý workshop i večer u ohně. Program si můžeme přizpůsobit počasí a náladě skupiny.</p>
<h3>Kde a kdy</h3><p>Ukázková chata U Borovic, 16.-18. dubna 2027. Příjezd v pátek od 16:00, odjezd v neděli ve 13:00. Kapacita je 24 účastníků; po naplnění se můžete zapsat mezi náhradníky.</p>
<h3>Ubytování a strava</h3><p>Šest čtyřlůžkových pokojů, společná koupelna a jídelna. Cena 1 800 Kč zahrnuje dvě noci, páteční večeři, sobotní stravu a nedělní snídani. Stravovací omezení uveďte za každého účastníka.</p>
<h3>Co si přibalit</h3><p>Pevné boty, pláštěnku, láhev na vodu, přezůvky a oblíbenou deskovou hru. Sdílenou dopravu bychom domluvili před odjezdem. Prostor bude také pro odpočinek a vlastní program.</p>
<h3>Přihlášení a podmínky</h3><p>Ve skutečné akci bychom po přihlášení poslali potvrzení a údaje k platbě, splatné do sedmi dnů. Při zrušení více než týden před akcí by se vracel celý poplatek; později bychom nabídli převod na náhradníka.</p>
<p><strong>Toto je ukázkový formulář.</strong> Místo, program i kontakty jsou fiktivní. Přihláška ani souhlasy se neuloží, žádný e-mail neodešleme a platba se nespustí. Texty podmínek jsou součástí ukázky.</p>
$header$, title='Přihláška na víkend' WHERE id=f;
  UPDATE public.occasions SET description=(SELECT header FROM public.forms WHERE id=f) WHERE id=d.occasion;
  UPDATE public.information SET description=(SELECT header FROM public.forms WHERE id=f) WHERE occasion=d.occasion AND title='Vítejte';
  UPDATE public.form_fields SET "order"=20 WHERE form=f AND type='ticket';
  UPDATE public.form_fields SET "order"=21 WHERE form=f AND type='name' AND is_ticket_field;
  UPDATE public.form_fields SET "order"=22 WHERE form=f AND type='surname' AND is_ticket_field;
  UPDATE public.form_fields SET "order"=23 WHERE form=f AND type='product_type';
  FOR item IN SELECT * FROM (VALUES
   ('phone','Kontaktní telefon','<p>Pro organizační zprávy před odjezdem a domluvu společné dopravy.</p>',true,false,2,'{}'::jsonb),
   ('text','Odkud přijedeš?','<p>Stačí město. Pomůže nám propojit účastníky pro společnou cestu.</p>',false,false,3,'{}'::jsonb),
   ('select_one','Jak přijedeš?','<p>Jde o orientační plán, dopravu bychom doladili před akcí.</p>',false,false,4,'{"options":[{"value":"Vlakem nebo autobusem"},{"value":"Autem - mohu někoho svézt"},{"value":"Rád/a se s někým svezu"},{"value":"Ještě nevím"}]}'::jsonb),
   ('birth_year','Rok narození','<p>Pro orientaci ve věku účastníků; celé datum narození nepotřebujeme.</p>',true,true,24,'{}'::jsonb),
   ('select_one','Stravovací omezení','<p>Další omezení nebo alergii prosím doplň do poznámky. V ukázce nic neukládáme.</p>',true,true,25,'{"options":[{"value":"Bez omezení"},{"value":"Vegetariánská strava"},{"value":"Bezlepková strava"},{"value":"Jiné - uvedu v poznámce"}]}'::jsonb),
   ('note','Poznámka k účastníkovi','<p>Například přání ohledně pokoje nebo informaci k jídlu.</p>',false,true,26,'{}'::jsonb),
   ('text','Chceš nám něco vzkázat?','<p>Prostor pro otázku nebo poznámku k celé skupině.</p>',false,false,30,'{}'::jsonb),
   ('select_many','Podmínky účasti a storna','<p>Ukázkové podmínky jsou uvedené v popisu. Toto potvrzení se neukládá.</p>',true,false,40,'{"options":[{"value":"Seznámil/a jsem se s podmínkami účasti a storna."}]}'::jsonb),
   ('select_many','Informace o osobních údajích','<p>V běžné akci by se údaje použily k zajištění pobytu a komunikaci s účastníky. <a href="https://vstupenky.online/privacy/">Informace o zpracování osobních údajů</a>. V této ukázce údaje ani potvrzení neukládáme.</p>',true,false,41,'{"options":[{"value":"Seznámil/a jsem se s informacemi o zpracování osobních údajů."}]}'::jsonb),
   ('select_many','Zprávy o dalších akcích','<p>Dobrovolný ukázkový souhlas, který lze u běžné akce kdykoliv odvolat. Tady žádný odběr nevytváříme a žádný e-mail neposíláme.</p>',false,false,42,'{"options":[{"value":"Souhlasím se zasíláním informací o dalších akcích."}]}'::jsonb)
  ) AS fields(type,title,description,required,ticket_field,position,data) LOOP
   IF NOT EXISTS(SELECT 1 FROM public.form_fields WHERE form=f AND title=item.title AND type=item.type) THEN
    INSERT INTO public.form_fields(form,type,title,description,is_required,is_ticket_field,"order",data)
    VALUES(f,item.type,item.title,item.description,item.required,item.ticket_field,item.position,item.data);
   END IF;
  END LOOP;
  -- Synthetic answer samples use existing name-based answer shape, no real customer data.
  UPDATE eshop.orders SET data=data||jsonb_build_object('phone','+420 700 000 '||lpad(order_sequence::text,3,'0'),
    'Odkud přijedeš?',CASE WHEN order_sequence%2=0 THEN 'Brno' ELSE 'Ostrava' END,
    'Jak přijedeš?',CASE WHEN order_sequence%3=0 THEN 'Autem - mohu někoho svézt' ELSE 'Vlakem nebo autobusem' END,
    'Podmínky účasti a storna','Seznámil/a jsem se s podmínkami účasti a storna.',
    'Informace o osobních údajích','Seznámil/a jsem se s informacemi o zpracování osobních údajů.')
    WHERE occasion=d.occasion;
  UPDATE eshop.tickets SET data=jsonb_set(coalesce(data,'{}'),'{fields}',
    coalesce((SELECT jsonb_agg(value) FROM jsonb_array_elements(coalesce(data->'fields','[]'))
      WHERE NOT(value ? 'birth_year' OR value ? 'Stravovací omezení')),'[]')||jsonb_build_array(
      jsonb_build_object('birth_year',1990+(id%15)),
      jsonb_build_object('Stravovací omezení',CASE WHEN id%5=0 THEN 'Vegetariánská strava' ELSE 'Bez omezení' END)))
    WHERE occasion=d.occasion;
 END LOOP;
END $examples$;


SELECT pg_temp.refresh_demo_presentation(3);
SELECT pg_temp.enrich_demo_examples(3);
