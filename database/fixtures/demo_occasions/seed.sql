-- Load with psql, inside one transaction, supplying demo_organization explicitly.
-- This fixture never invokes checkout, Auth invitations, bank ingest or email producers.
CREATE OR REPLACE FUNCTION pg_temp.seed_demo_occasions(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $fixture$
#variable_conflict use_variable
DECLARE un bigint; oc bigint; bank bigint; f bigint; bp bigint; pt bigint; prod bigint;
 premium_prod bigint; seat_prod bigint;
 pool bigint; ctx bigint; ord bigint; pay bigint; ticket bigint; opt bigint; seat bigint;
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
 IF EXISTS(SELECT 1 FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14') THEN
  IF (SELECT count(*) FROM public.demo_occasions WHERE organization=p_org AND fixture_version='2026-10-14')<>3 THEN
   RAISE EXCEPTION 'Incomplete demo fixture requires investigation';
  END IF;
  RETURN;
 END IF;
 INSERT INTO public.units(title,organization) VALUES('Ukázkový pořadatel',p_org) RETURNING id INTO un;
 FOREACH k IN ARRAY ARRAY['ball','concert','weekend'] LOOP
  title:=CASE k WHEN 'ball' THEN 'Ples pod hvězdami' WHEN 'concert' THEN 'Večer živé hudby' ELSE 'Víkend v přírodě' END;
  summary:=CASE k WHEN 'ball' THEN 'Místa u stolů, objednávky a platby' WHEN 'concert' THEN 'Vstupenky, sektory a odbavení' ELSE 'Přihlášky, ubytování a náhradníci' END;
  beginning:=CASE k WHEN 'ball' THEN '2027-02-20 19:30+01'::timestamptz WHEN 'concert' THEN '2027-03-06 19:00+01'::timestamptz ELSE '2027-04-16 17:00+02'::timestamptz END;
  closing:=beginning+CASE k WHEN 'ball' THEN interval '6 hours 30 minutes' WHEN 'concert' THEN interval '4 hours' ELSE interval '44 hours' END;
  price:=CASE k WHEN 'ball' THEN 450 WHEN 'concert' THEN 590 ELSE 1800 END;
  count_orders:=CASE k WHEN 'ball' THEN 95 WHEN 'concert' THEN 20 ELSE 24 END;
  count_seats:=CASE k WHEN 'ball' THEN 300 WHEN 'concert' THEN 80 ELSE 0 END;
  layout:=(SELECT content FROM pg_temp.demo_ticket_layouts WHERE demo_key=k);
  IF layout IS NULL THEN RAISE EXCEPTION 'Load layouts.sql before seed.sql'; END IF;
  features:=jsonb_build_array(jsonb_build_object('code','form','is_enabled',true),
    jsonb_build_object('code','ticket','is_enabled',true,'ticket_type','wide','layout',layout),
    jsonb_build_object('code','schedule','is_enabled',true),
    jsonb_build_object('code','blueprint','is_enabled',true),
    jsonb_build_object('code','services','is_enabled',true));
  INSERT INTO public.occasions(title,unit,organization,link,start_time,end_time,is_hidden,is_open,is_promoted,
    is_order_synchronization_enabled,features,description,data)
  VALUES(title,un,p_org,'demo-'||p_org||'-'||k||'-20261014',beginning,closing,true,false,false,false,features,
   '<p>'||summary||'. Společně naplánujeme nezapomenutelný zážitek.</p>',
   jsonb_build_object('timezone','Europe/Prague')) RETURNING id INTO oc;
  PERFORM public.reserve_public_link_internal('occasion',oc,(SELECT link FROM public.occasions WHERE id=oc),true);
  INSERT INTO eshop.bank_accounts(title,account_number_human_readable,account_number,creditor_name,is_fetch_enabled,supported_currencies)
  VALUES('Ukázkový účet - neposílejte platbu','UKÁZKA - NEPLATNÝ ÚČET',NULL,'Ukázkový pořadatel',false,ARRAY['CZK']) RETURNING id INTO bank;
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
  INSERT INTO public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at)
  VALUES(oc,p_org,k,'2026-10-14',bank,CASE k WHEN 'ball' THEN 1 WHEN 'concert' THEN 2 ELSE 3 END,summary,beginning+interval '1 hour');
  INSERT INTO eshop.product_types(occasion,title,type) VALUES(oc,'Vstupné','spot') RETURNING id INTO pt;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,maximum)
  VALUES(oc,pt,CASE k WHEN 'weekend' THEN 'Víkend včetně stravy a ubytování' ELSE 'Základní vstupné' END,price,'CZK',NULL) RETURNING id INTO prod;
  premium_prod:=NULL;
  IF k='ball' THEN
   INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,maximum)
   VALUES(oc,pt,'Vstupné u pódia - stoly 1-5',650,'CZK',NULL) RETURNING id INTO premium_prod;
  END IF;
  bp:=NULL; objects:='[]'; groups:='[]';
  IF count_seats>0 THEN
   INSERT INTO eshop.blueprints(occasion,organization,title,configuration,objects,groups)
   VALUES(oc,p_org,'Plánek sálu','{"dimensions":{"width":64,"height":42}}','[]','[]') RETURNING id INTO bp;
   FOR idx IN 1..count_seats LOOP
    INSERT INTO eshop.spots(occasion,blueprint,product,title)
    VALUES(oc,bp,CASE WHEN k='ball' AND idx<=50 THEN premium_prod ELSE prod END,idx::text) RETURNING id INTO seat;
    objects:=objects||jsonb_build_array(jsonb_build_object('id',seat,'type','spot','title',idx::text,
     'group',(idx-1)/10+1,'x',4+((idx-1)%10)*5,'y',9+((idx-1)/10)));
   END LOOP;
   FOR idx IN 1..(count_seats/10) LOOP
    groups:=groups||jsonb_build_array(jsonb_build_object('id',idx,'title',CASE k WHEN 'ball' THEN 'Stůl ' ELSE 'Řada ' END||idx));
   END LOOP;
   objects:=objects||'[{"type":"table","title":"PÓDIUM","x":27,"y":2},{"type":"table","title":"VSTUP","x":2,"y":40}]'::jsonb;
   UPDATE eshop.blueprints SET objects=objects,groups=groups WHERE id=bp;
  END IF;
  INSERT INTO public.forms(occasion,title,link,blueprint,bank_account,is_open,header,header_off,
    participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds,data)
  VALUES(oc,title,'demo-form-'||p_org||'-'||k,bp,bank,false,
   CASE WHEN k='ball' THEN '<p>Vyberte si místo v plánku sálu. Stoly 1-5: 650 Kč, ostatní stoly: 450 Kč. Všechny uvedené údaje jsou fiktivní.</p>'
    ELSE '<h2>'||title||'</h2><p>Vyberte si variantu a vyplňte údaje účastníků. Všechny uvedené údaje jsou fiktivní.</p>' END,
   '<p>Ukázkový formulář - pouze k prohlížení.</p>',CASE WHEN k='weekend' THEN 24 END,k='weekend',
   CASE WHEN k='weekend' THEN 86400 END,'{}') RETURNING id INTO f;
  PERFORM public.reserve_public_link_internal('form',f,(SELECT link FROM public.forms WHERE id=f),true);
  INSERT INTO public.form_fields(form,type,title,is_required,is_ticket_field,"order",data)
  VALUES(f,'email','Kontaktní email',true,false,0,'{}'),(f,'ticket',CASE WHEN k='ball' THEN 'Vstupenka' ELSE 'Účastníci' END,true,false,1,'{"max_tickets":10}'),
    (f,'name','Jméno',true,true,2,'{}'),(f,'surname','Příjmení',true,true,3,'{}');
  INSERT INTO public.form_fields(form,type,title,product_type,is_required,is_ticket_field,"order",data)
  VALUES(f,'product_type','Vstupné',pt,true,true,4,'{}');
  IF k='concert' THEN
   INSERT INTO public.inventory_pools(occasion,title,type,sellable_capacity) VALUES(oc,'Stání','capacity',150) RETURNING id INTO pool;
   INSERT INTO public.inventory_contexts(inventory_pool,title) VALUES(pool,'Koncert') RETURNING id INTO ctx;
  END IF;
  FOR idx IN 1..count_orders LOOP
   n:=CASE k WHEN 'ball' THEN CASE WHEN idx<=25 THEN 2 ELSE 3 END WHEN 'concert' THEN CASE WHEN idx<=5 THEN 2 ELSE 3 END ELSE 1 END;
   amount:=price*n;
   IF bp IS NOT NULL THEN
    SELECT sum(p.price) INTO amount FROM (
     SELECT s.product FROM eshop.spots s WHERE s.occasion=oc AND s.order_product_ticket IS NULL ORDER BY s.id LIMIT n
    ) available JOIN eshop.products p ON p.id=available.product;
   END IF;
   paid:=CASE WHEN idx=2 THEN price WHEN idx=7 THEN 0 WHEN idx=4 THEN amount+100 ELSE amount END;
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
      public.generate_ticket_symbol(p_org,oc),stamp,CASE WHEN k<>'weekend' AND state='paid' AND idx>8 AND idx%3=0 THEN beginning+interval '30 minutes' ELSE stamp+interval '1 day' END,
      jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('name',names[(idx+total-2)%8+1]),jsonb_build_object('surname',surnames[(idx+total-2)%8+1])))) RETURNING id INTO ticket;
    SELECT id,product INTO seat,seat_prod FROM eshop.spots WHERE occasion=oc AND order_product_ticket IS NULL ORDER BY id LIMIT 1;
    INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,coalesce(seat_prod,prod),ticket) RETURNING id INTO opt;
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
   INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data)
   SELECT ord,stamp,state,amount,'CZK',o.data||jsonb_build_object('tickets',public.snapshot_waitlist_tickets_internal(ord)) FROM eshop.orders o WHERE id=ord;
   IF k='weekend' AND idx=24 THEN accepted_ticket:=ticket;accepted_order:=ord; END IF;
  END LOOP;
  INSERT INTO eshop.transactions(bank_account_id,date,amount,currency,vs,counter_account_name,comment)
  VALUES(bank,beginning-interval '10 days',730,'CZK','999999999','Šimon Fiktivní','Nespárovaná ukázková platba');
  -- Cancellation keeps the original order and ticket, frees any seat and creates no refund.
  FOR idx IN 1..CASE WHEN k='ball' THEN 4 ELSE 1 END LOOP
   ord:=public.allocate_ticket_order_identity_internal(f);
   UPDATE eshop.orders SET price=price,state='storno',created_at=beginning-interval '20 days',
    data=jsonb_build_object('email','storno-'||idx||'@example.invalid','name','Marek','surname','Ukázkový') WHERE id=ord;
   INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data) VALUES(oc,'storno',public.generate_ticket_symbol(p_org,oc),'{}') RETURNING id INTO ticket;
   INSERT INTO eshop.order_product_ticket("order",product,ticket) VALUES(ord,prod,ticket);
   INSERT INTO eshop.orders_history("order",created_at,state,price,data)
   VALUES(ord,beginning-interval '20 days','ordered',price,'{"name":"Marek","surname":"Ukázkový"}'),
    (ord,beginning-interval '18 days','storno',price,'{"name":"Marek","surname":"Ukázkový"}');
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
  END IF;
  INSERT INTO public.events(occasion,title,start_time,end_time)
  VALUES(oc,CASE k WHEN 'ball' THEN 'Otevření sálu' WHEN 'concert' THEN 'Otevření vstupu' ELSE 'Příjezd a ubytování' END,beginning-interval '1 hour',beginning),
   (oc,CASE k WHEN 'ball' THEN 'Předtančení' WHEN 'concert' THEN 'Hlavní vystoupení' ELSE 'Společný program' END,beginning+interval '30 minutes',beginning+interval '2 hours'),
   (oc,CASE k WHEN 'ball' THEN 'Půlnoční překvapení' WHEN 'concert' THEN 'Přídavky' ELSE 'Závěrečný kruh' END,closing-interval '1 hour',closing);
 END LOOP;
END $fixture$;
