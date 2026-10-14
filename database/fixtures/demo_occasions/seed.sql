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

-- Use the existing stored order-history shape, priced from the actual product links.
CREATE OR REPLACE FUNCTION pg_temp.demo_order_snapshot(p_order bigint)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT o.data||jsonb_build_object('tickets',coalesce((SELECT jsonb_agg(jsonb_build_object(
  'id',t.id,'ticket_symbol',t.ticket_symbol,'note',t.note,'answers',t.data,
  'products',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'type',pt.type,
    'type_title',pt.title,'price',p.price,'currency_code',p.currency_code,'spot_title',s.title) ORDER BY x.id)
   FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product
   JOIN eshop.product_types pt ON pt.id=p.product_type LEFT JOIN eshop.spots s ON s.order_product_ticket=x.id
   WHERE x.ticket=t.id AND x."order"=o.id),'[]'::jsonb)) ORDER BY t.id)
  FROM eshop.tickets t WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=o.id)),'[]'::jsonb))
 FROM eshop.orders o WHERE o.id=p_order;
$$;
-- Load with psql, inside one transaction, supplying demo_organization explicitly.
-- This fixture never invokes checkout, Auth invitations, bank ingest or email producers.
CREATE OR REPLACE FUNCTION pg_temp.seed_demo_occasions(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $fixture$
#variable_conflict use_variable
DECLARE un bigint; oc bigint; bank bigint; f bigint; bp bigint; pt bigint; prod bigint;
 pool bigint; ctx bigint; standing_prod bigint; ticket_prod bigint; unit_price numeric; room bigint; room_slot bigint; ord bigint; pay bigint; ticket bigint; opt bigint; seat bigint;
 source_plan jsonb; source_spot jsonb; previous_data jsonb;
 accepted_ticket bigint; accepted_order bigint; offer uuid; objects jsonb; groups jsonb;
 k text; title text; summary text; price numeric; amount numeric; paid numeric;
 count_orders integer; count_seats integer; n integer; total integer; idx integer;
 stamp timestamptz; beginning timestamptz; closing timestamptz; state text; person text;
 names text[]:=ARRAY['Tereza','Jakub','Klára','Šimon','Žofie','Matěj','Anna','Jiří'];
 surnames text[]:=ARRAY['Šťastná','Novotný','Dvořáková','Černý','Říhová','Procházka','Malá','Kučera'];
 layout jsonb; features jsonb;
BEGIN
 IF current_user<>'postgres' THEN RAISE insufficient_privilege; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_org) THEN RAISE EXCEPTION 'Missing target organization'; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 IF EXISTS(SELECT 1 FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3') THEN
  IF (SELECT count(*) FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14.3')<>3 THEN
   RAISE EXCEPTION 'Incomplete demo fixture requires investigation';
  END IF;
  PERFORM pg_temp.refresh_demo_presentation(p_org);
  PERFORM pg_temp.enrich_demo_examples(p_org);
  PERFORM pg_temp.refresh_demo_artwork(p_org);
  RETURN;
 END IF;
 INSERT INTO public.units(title,organization) VALUES('Ukázkový pořadatel',p_org) RETURNING id INTO un;
 FOREACH k IN ARRAY ARRAY['ball','concert','weekend'] LOOP
  title:=CASE k WHEN 'ball' THEN 'Ples pod hvězdami' WHEN 'concert' THEN 'Večer živé hudby' ELSE 'Víkend v přírodě' END;
  summary:=CASE k WHEN 'ball' THEN 'Místa u stolů, objednávky a platby' WHEN 'concert' THEN 'Vstupenky a odbavení' ELSE 'Přihlášky, ubytování a náhradníci' END;
  beginning:=CASE k WHEN 'ball' THEN '2027-02-20 19:30+01'::timestamptz WHEN 'concert' THEN '2027-03-06 19:00+01'::timestamptz ELSE '2027-04-16 17:00+02'::timestamptz END;
  closing:=beginning+CASE k WHEN 'ball' THEN interval '6 hours 30 minutes' WHEN 'concert' THEN interval '4 hours' ELSE interval '44 hours' END;
  price:=CASE k WHEN 'ball' THEN 450 WHEN 'concert' THEN 590 ELSE 1800 END;
  count_orders:=CASE k WHEN 'ball' THEN 95 WHEN 'concert' THEN 20 ELSE 24 END;
  count_seats:=CASE WHEN k='ball' THEN 249 ELSE 0 END;
  layout:=(SELECT content FROM pg_temp.demo_ticket_layouts WHERE demo_key=k);
  IF k<>'weekend' AND layout IS NULL THEN RAISE EXCEPTION 'Load layouts.sql before seed.sql'; END IF;
  features:=jsonb_build_array(jsonb_build_object('code','form','is_enabled',true),
    CASE WHEN k='weekend' THEN jsonb_build_object('code','ticket','is_enabled',false) ELSE jsonb_build_object('code','ticket','is_enabled',true,'ticket_type','wide','layout',layout) END,
    jsonb_build_object('code','schedule','is_enabled',true),
    jsonb_build_object('code','blueprint','is_enabled',k='ball'),
    jsonb_build_object('code','services','is_enabled',false));
  INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,is_hidden,is_open,is_promoted,
    is_order_synchronization_enabled,features,description,data)
  VALUES(title,un,p_org,'demo-'||p_org||'-'||k||'-20261014-3',beginning,closing,true,false,false,false,features,
   '<p>'||summary||'. Společně naplánujeme nezapomenutelný zážitek.</p>',
   jsonb_build_object('timezone','Europe/Prague','place_name',CASE WHEN k='weekend' THEN 'Areál U Borovic' ELSE 'Společenský sál' END)) RETURNING id INTO oc;
  INSERT INTO eshop.bank_accounts(title,account_number_human_readable,account_number,creditor_name,is_fetch_enabled,supported_currencies)
  VALUES('Ukázkový účet - neposílejte platbu','UKÁZKA - NEPLATNÝ ÚČET',NULL,'Ukázkový pořadatel',false,ARRAY['CZK']) RETURNING id INTO bank;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
  INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at)
  VALUES(oc,p_org,k,'2026-10-14.3',bank,CASE k WHEN 'ball' THEN 1 WHEN 'concert' THEN 2 ELSE 3 END,summary,beginning+interval '1 hour');
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,CASE WHEN k='weekend' THEN 'Účastnický poplatek' ELSE 'Vstupné' END,'spot') RETURNING id INTO pt;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,maximum)
  VALUES(oc,pt,CASE k WHEN 'weekend' THEN 'Víkend včetně stravy a ubytování' ELSE 'Základní vstupné' END,price,'CZK',NULL) RETURNING id INTO prod;
  bp:=NULL; objects:='[]'; groups:='[]';
  SELECT content INTO source_plan FROM pg_temp.demo_reference_blueprint;
  IF count_seats>0 THEN
   INSERT INTO eshop.blueprints(occasion,organization,title,configuration,objects,groups)
   VALUES(oc,p_org,'Plánek sálu','{"dimensions":{"width":64,"height":42}}','[]','[]') RETURNING id INTO bp;
   FOR idx IN 1..count_seats LOOP
    INSERT INTO eshop.spots(occasion,blueprint,product,title) VALUES(oc,bp,prod,idx::text) RETURNING id INTO seat;
    objects:=objects||jsonb_build_array(jsonb_build_object('id',seat,'type','spot','title',idx::text,
     'group',(idx-1)/10+1,'x',4+((idx-1)%10)*5,'y',9+((idx-1)/10)));
   END LOOP;
   FOR idx IN 1..(count_seats/10) LOOP
    groups:=groups||jsonb_build_array(jsonb_build_object('id',idx,'title',CASE k WHEN 'ball' THEN 'Stůl ' ELSE 'Řada ' END||idx));
   END LOOP;
   objects:=objects||'[{"type":"table","title":"PÓDIUM","x":27,"y":2},{"type":"table","title":"VSTUP","x":2,"y":40}]'::jsonb;
   IF k='ball' THEN
    objects:='[]';
    FOR idx IN 1..count_seats LOOP
     source_spot:=source_plan->'objects'->(idx-1);
     SELECT id INTO seat FROM eshop.spots WHERE blueprint=bp ORDER BY id OFFSET idx-1 LIMIT 1;
     objects:=objects||jsonb_build_array(source_spot||jsonb_build_object('id',seat,'title',coalesce(source_spot->>'title',idx::text)));
    END LOOP;
    groups:=source_plan->'groups';
    UPDATE eshop.blueprints SET configuration=source_plan->'configuration',background_svg=source_plan->>'background_svg' WHERE id=bp;
   END IF;
   UPDATE eshop.blueprints SET objects=objects,groups=groups WHERE id=bp;
  END IF;
  INSERT INTO public.forms(occasion,title,link,blueprint,bank_account,is_open,header,header_off,
    participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds,data)
  VALUES(oc,title,'demo-form-'||p_org||'-'||k||'-20261014-3',bp,bank,true,
   '<h2>'||title||'</h2><p>Vyberte si variantu a vyplňte údaje účastníků. Všechny uvedené údaje jsou fiktivní.</p>',
   '<p>Ukázkový formulář. Přihláška se neuloží, žádný e-mail neodešleme a platba se nespustí.</p>',CASE WHEN k='weekend' THEN 24 END,k='weekend',
   CASE WHEN k='weekend' THEN 86400 END,jsonb_build_object('primary_color',CASE k WHEN 'ball' THEN '#401529' WHEN 'concert' THEN '#101820' ELSE '#123B20' END,'secondary_color',CASE k WHEN 'ball' THEN '#F9F3E8' WHEN 'concert' THEN '#ECEFF1' ELSE '#EDF4EA' END)) RETURNING id INTO f;
  INSERT INTO public.information(occasion,unit,title,description,is_hidden,"order")
  VALUES(oc,un,'Vítejte', '<h2>'||title||'</h2><p>'||summary||'. Těšíme se na společné chvíle.</p>',false,1),
   (oc,un,'Praktické informace',CASE k WHEN 'ball' THEN '<p>Vstup od 18:30, začátek v 19:30. Šatna je u vstupu, bar v zadní části sálu. Předtančení ve 20:00, půlnoční překvapení a hudba do 02:00.</p>' WHEN 'concert' THEN '<p>Vstup od 18:00. Volný vstup do prostoru před pódiem, bez rezervace sedadel. Občerstvení je v předsálí.</p>' ELSE '<p>Příjezd v pátek od 16:00, odjezd v neděli ve 13:00. Ubytování v pokojích, společná strava a sobotní workshopy. S sebou pohodlné oblečení a obuv do terénu.</p>' END,false,2);
  INSERT INTO public.places(occasion,unit,title,description)
  VALUES(oc,un,CASE WHEN k='weekend' THEN 'Společenská místnost' ELSE 'Hlavní sál' END,'Prostor společného programu'),
   (oc,un,CASE WHEN k='weekend' THEN 'Jídelna' ELSE 'Bar a občerstvení' END,'Občerstvení a místo pro setkávání');
  INSERT INTO public.form_fields(form,type,title,is_required,is_ticket_field,"order",data)
  VALUES(f,'email','Kontaktní email',true,false,0,'{}'),(f,'ticket','Účastníci',true,false,1,'{"max_tickets":10}'),
    (f,'name','Jméno',true,true,2,'{}'),(f,'surname','Příjmení',true,true,3,'{}');
  INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_ticket_field,"order",data)
  VALUES(f,'product_type',CASE WHEN k='weekend' THEN 'Účastnický poplatek' ELSE 'Vstupné' END,pt,true,true,4,'{}');
  IF k='ball' THEN
   INSERT INTO public.form_fields(form,type,title,is_required,is_ticket_field,"order",data)
   VALUES(f,'spot','Místo u stolu',true,true,5,'{}');
  END IF;
  standing_prod:=NULL; ctx:=NULL;
  IF k='concert' THEN
   INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(oc,'Kapacita koncertu','capacity',230) RETURNING id INTO pool;
   INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Koncert') RETURNING id INTO ctx;
   INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
    VALUES(oc,pt,'Zvýhodněná vstupenka',390,'CZK') RETURNING id INTO standing_prod;
   INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(standing_prod,ctx,1),(prod,ctx,1);
   INSERT INTO eshop.spots(occasion,product,inventory_context,title)
    SELECT oc,NULL,ctx,'Vstup '||i FROM generate_series(1,230) i;
  END IF;
  IF k='weekend' THEN
   INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(oc,'Ubytování','accommodation',24) RETURNING id INTO pool;
   INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Víkendový pobyt') RETURNING id INTO ctx;
   INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity) VALUES(prod,ctx,1);
   FOR idx IN 1..6 LOOP
    INSERT INTO public.resources(title,capacity,inventory_pool,occasion,unit) VALUES('Pokoj '||idx,4,pool,oc,un) RETURNING id INTO room;
    FOR total IN 1..4 LOOP
     INSERT INTO public.resource_slots(resource,title) VALUES(room,'Lůžko '||total) RETURNING id INTO room_slot;
     INSERT INTO eshop.spots(occasion,product,inventory_context,resource,resource_slot,title) VALUES(oc,prod,ctx,room,room_slot,'Pokoj '||idx||' / lůžko '||total);
    END LOOP;
   END LOOP;
  END IF;
  FOR idx IN 1..count_orders LOOP
   n:=CASE k WHEN 'ball' THEN CASE WHEN idx<=45 THEN 2 ELSE 3 END WHEN 'concert' THEN CASE WHEN idx<=5 THEN 2 ELSE 3 END ELSE 1 END;
   ticket_prod:=CASE WHEN k='concert' AND idx>10 THEN standing_prod ELSE prod END;
   unit_price:=CASE WHEN k='concert' AND idx>10 THEN 390 ELSE price END;
   amount:=unit_price*n; paid:=CASE WHEN idx=2 THEN unit_price WHEN idx=7 THEN 0 WHEN idx=4 THEN amount+100 ELSE amount END;
   state:=CASE WHEN paid<amount THEN 'ordered' ELSE 'paid' END;
   stamp:=beginning-interval '40 days'+idx*interval '6 hours';
   person:=names[(idx-1)%8+1]||' '||surnames[(idx-1)%8+1];
   INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,paid,deadline,currency_code,created_at)
   VALUES(bank,710000000+idx,amount,paid,stamp+interval '7 days','CZK',stamp) RETURNING id INTO pay;
   ord:=public.allocate_ticket_order_identity_internal(f);
   UPDATE eshop.orders SET created_at=stamp,updated_at=stamp+interval '1 day',price=amount,payment_info=pay,
    state=state,data=jsonb_build_object('email','host-'||idx||'@example.invalid','name',names[(idx-1)%8+1],'surname',surnames[(idx-1)%8+1]) WHERE id=ord;
   FOR total IN 1..n LOOP
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,created_at,updated_at,data)
    VALUES(oc,CASE WHEN k<>'weekend' AND state='paid' AND idx>8 AND idx%3=0 THEN 'used' ELSE state END,
      CASE WHEN k='weekend' THEN NULL ELSE public.generate_ticket_symbol(p_org,oc) END,stamp,CASE WHEN k<>'weekend' AND state='paid' AND idx>8 AND idx%3=0 THEN beginning+interval '30 minutes' ELSE stamp+interval '1 day' END,
      jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('name',names[(idx+total-2)%8+1]),jsonb_build_object('surname',surnames[(idx+total-2)%8+1])))) RETURNING id INTO ticket;
    INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,ticket_prod,ticket) RETURNING id INTO opt;
    SELECT id INTO seat FROM eshop.spots WHERE occasion=oc AND order_product_ticket IS NULL AND CASE WHEN k IN ('weekend','concert') THEN inventory_context=ctx ELSE blueprint=bp END ORDER BY id LIMIT 1;
    IF seat IS NOT NULL THEN UPDATE eshop.spots SET order_product_ticket=opt WHERE id=seat; END IF;
   END LOOP;
   IF paid>0 THEN
    INSERT INTO eshop.transactions(bank_account_id,payment_info,date,amount,currency,vs,counter_account_name,comment)
    VALUES(bank,pay,stamp+interval '1 day',CASE WHEN idx=3 THEN paid/2 ELSE paid END,'CZK',(710000000+idx)::text,person,'Syntetická ukázková platba');
    IF idx=3 THEN
     INSERT INTO eshop.transactions(bank_account_id,payment_info,date,amount,currency,vs,counter_account_name,comment)
     VALUES(bank,pay,stamp+interval '2 days',paid/2,'CZK',(710000000+idx)::text,person,'Doplatek - syntetická ukázka');
    END IF;
   END IF;
   UPDATE eshop.orders SET data=pg_temp.demo_order_snapshot(ord) WHERE id=ord;
   INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data)
   SELECT ord,stamp,state,amount,'CZK',pg_temp.demo_order_snapshot(ord) FROM eshop.orders o WHERE id=ord;
   -- Group changes use the same order/ticket links and immutable history snapshots.
   IF k='ball' AND idx=5 THEN
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data)
    VALUES(oc,'ordered',public.generate_ticket_symbol(p_org,oc),
     '{"fields":[{"name":"Eliška"},{"surname":"Ukázková"}]}') RETURNING id INTO ticket;
    INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,prod,ticket) RETURNING id INTO opt;
    SELECT id INTO seat FROM eshop.spots WHERE blueprint=bp AND order_product_ticket IS NULL ORDER BY id LIMIT 1;
    UPDATE eshop.spots SET order_product_ticket=opt WHERE id=seat;
    UPDATE eshop.orders SET price=amount+unit_price,state='ordered',updated_at=stamp+interval '3 days' WHERE id=ord;
    UPDATE eshop.payment_info SET amount=amount+unit_price WHERE id=pay;
    UPDATE eshop.tickets SET state='ordered' WHERE id IN (SELECT x.ticket FROM eshop.order_product_ticket x WHERE x."order"=ord);
   ELSIF k='ball' AND idx=6 THEN
    UPDATE eshop.tickets SET state='storno',updated_at=stamp+interval '3 days' WHERE id=ticket;
    UPDATE eshop.spots SET order_product_ticket=NULL WHERE order_product_ticket=opt;
    UPDATE eshop.order_product_ticket SET product=NULL WHERE id=opt;
    UPDATE eshop.orders SET price=amount-unit_price,updated_at=stamp+interval '3 days' WHERE id=ord;
    UPDATE eshop.payment_info SET amount=amount-unit_price WHERE id=pay;
   END IF;
   IF k='ball' AND idx IN (5,6) THEN
    UPDATE eshop.orders SET data=pg_temp.demo_order_snapshot(ord) WHERE id=ord;
    INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data)
    SELECT id,stamp+interval '3 days',o.state,o.price,'CZK',o.data FROM eshop.orders o WHERE id=ord;
   END IF;
   IF k='weekend' AND idx=24 THEN accepted_ticket:=ticket;accepted_order:=ord; END IF;
  END LOOP;
  -- A few real-looking answer corrections use ordinary history snapshots.
  FOR idx IN 8..10 LOOP
   SELECT id,data INTO ord,previous_data FROM eshop.orders WHERE occasion=oc AND order_sequence=idx;
   UPDATE eshop.orders SET data=jsonb_set(data,'{surname}',to_jsonb(surnames[(idx+1)%8+1])),updated_at=beginning-interval '9 days' WHERE id=ord;
   INSERT INTO eshop.orders_history("order",created_at,state,price,data)
    SELECT id,beginning-interval '9 days',state,price,pg_temp.demo_order_snapshot(id) FROM eshop.orders WHERE id=ord;
  END LOOP;
  INSERT INTO eshop.transactions(bank_account_id,date,amount,currency,vs,counter_account_name,comment)
  VALUES(bank,beginning-interval '10 days',730,'CZK','999999999','Šimon Fiktivní','Nespárovaná ukázková platba');
  -- Cancellation keeps the original order and ticket, frees any seat and creates no refund.
  FOR idx IN 1..CASE WHEN k='ball' THEN 4 ELSE 1 END LOOP
   ord:=public.allocate_ticket_order_identity_internal(f);
   UPDATE eshop.orders SET price=price,state='storno',created_at=beginning-interval '20 days',
    data=jsonb_build_object('email','storno-'||idx||'@example.invalid','name','Marek','surname','Ukázkový') WHERE id=ord;
   INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data) VALUES(oc,'storno',CASE WHEN k='weekend' THEN NULL ELSE public.generate_ticket_symbol(p_org,oc) END,'{}') RETURNING id INTO ticket;
   INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,prod,ticket);
   INSERT INTO eshop.orders_history("order",created_at,state,price,data)
   VALUES(ord,beginning-interval '20 days','ordered',price,'{"name":"Marek","surname":"Ukázkový"}'),
    (ord,beginning-interval '18 days','storno',price,'{"name":"Marek","surname":"Ukázkový"}');
   UPDATE eshop.orders_history SET data=pg_temp.demo_order_snapshot(ord) WHERE "order"=ord AND state='ordered';
   UPDATE eshop.order_product_ticket SET product=NULL WHERE "order"=ord;
   UPDATE eshop.orders SET data=pg_temp.demo_order_snapshot(ord) WHERE id=ord;
   UPDATE eshop.orders_history SET data=pg_temp.demo_order_snapshot(ord) WHERE "order"=ord AND state='storno';
  END LOOP;
  IF k='weekend' THEN
   FOR idx IN 1..4 LOOP
    ord:=public.allocate_ticket_order_identity_internal(f);
    UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,
     data=jsonb_build_object('email','nahradnik-'||idx||'@example.invalid','name',names[idx],'surname',surnames[idx]) WHERE id=ord;
    INSERT INTO eshop.tickets(occasion,state,waitlist_queue_at,data)
    VALUES(oc,'waitlisted',beginning-interval '12 days'+idx*interval '1 hour',jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('name',names[idx]),jsonb_build_object('surname',surnames[idx])))) RETURNING id INTO ticket;
    INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(ord,ticket);
   END LOOP;
   INSERT INTO eshop.waitlist_offers(order_id,form_id,created_at,expires_at,revision)
   VALUES(accepted_order,f,beginning-interval '8 days',beginning-interval '7 days',1) RETURNING id INTO offer;
   INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id,outcome,resulting_order_id,updated_at)
   VALUES(offer,accepted_ticket,f,'accepted',accepted_order,beginning-interval '7 days 12 hours');
   UPDATE eshop.orders SET created_at=beginning-interval '15 days',updated_at=beginning-interval '7 days 6 hours' WHERE id=accepted_order;
   UPDATE eshop.tickets SET created_at=beginning-interval '15 days',waitlist_queue_at=beginning-interval '15 days',updated_at=beginning-interval '7 days 6 hours' WHERE id=accepted_ticket;
   UPDATE eshop.transactions SET date=beginning-interval '7 days 6 hours' WHERE payment_info=(SELECT payment_info FROM eshop.orders WHERE id=accepted_order);
   UPDATE eshop.payment_info SET created_at=beginning-interval '7 days 12 hours' WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=accepted_order);
   UPDATE eshop.orders_history SET created_at=beginning-interval '7 days 6 hours',data=pg_temp.demo_order_snapshot(accepted_order) WHERE "order"=accepted_order;
   INSERT INTO eshop.orders_history("order",created_at,state,price,data)
   SELECT accepted_order,beginning-interval '15 days','waitlisted',NULL,
    jsonb_build_object('name',o.data->'name','surname',o.data->'surname','email',o.data->'email','tickets',
     jsonb_build_array(jsonb_build_object('id',accepted_ticket,'ticket_symbol',NULL,'products','[]'::jsonb,'answers',t.data,'lifecycle','waiting')))
   FROM eshop.orders o JOIN eshop.tickets t ON t.id=accepted_ticket WHERE o.id=accepted_order;

  END IF;
  INSERT INTO public.events(occasion,title,start_time,end_time)
  VALUES(oc,CASE k WHEN 'ball' THEN 'Otevření sálu' WHEN 'concert' THEN 'Otevření vstupu' ELSE 'Příjezd a ubytování' END,beginning-interval '1 hour',beginning),
   (oc,CASE k WHEN 'ball' THEN 'Předtančení' WHEN 'concert' THEN 'Hlavní vystoupení' ELSE 'Společný program' END,beginning+interval '30 minutes',beginning+interval '2 hours'),
   (oc,CASE k WHEN 'ball' THEN 'Půlnoční překvapení' WHEN 'concert' THEN 'Přídavky' ELSE 'Závěrečný kruh' END,CASE WHEN k='ball' THEN date_trunc('day',beginning AT TIME ZONE 'Europe/Prague') AT TIME ZONE 'Europe/Prague'+interval '24 hours' ELSE closing-interval '1 hour' END,
   CASE WHEN k='ball' THEN date_trunc('day',beginning AT TIME ZONE 'Europe/Prague') AT TIME ZONE 'Europe/Prague'+interval '24 hours 30 minutes' ELSE closing END);
  IF k='weekend' THEN
   INSERT INTO public.events(occasion,title,start_time,end_time)
   VALUES(oc,'Sobotní snídaně',beginning+interval '15 hours',beginning+interval '16 hours'),
    (oc,'Workshop: orientace v přírodě',beginning+interval '17 hours',beginning+interval '19 hours'),
    (oc,'Společný oběd',beginning+interval '19 hours',beginning+interval '20 hours'),
    (oc,'Workshop: tvořivá dílna',beginning+interval '21 hours',beginning+interval '23 hours'),
    (oc,'Večerní posezení u ohně',beginning+interval '26 hours',beginning+interval '28 hours'),
    (oc,'Nedělní snídaně',beginning+interval '39 hours',beginning+interval '40 hours');
  END IF;
 END LOOP;
 PERFORM pg_temp.refresh_demo_presentation(p_org);
 PERFORM pg_temp.enrich_demo_examples(p_org);
  PERFORM pg_temp.refresh_demo_artwork(p_org);
END $fixture$;
