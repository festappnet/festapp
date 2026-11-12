-- test-setup: database/fixtures/demo_occasions/layouts.sql
-- test-setup: database/fixtures/demo_occasions/reference.sql
-- test-setup: database/fixtures/demo_occasions/reference.en.sql
-- test-setup: database/fixtures/demo_occasions/artwork.sql
-- test-setup: database/fixtures/demo_occasions/titles.sql
-- test-setup: database/fixtures/demo_occasions/ball-prices.sql
-- test-setup: database/fixtures/demo_occasions/seed.sql
-- test-setup: database/fixtures/demo_occasions/locales.sql
-- test-setup: database/fixtures/demo_occasions/localization.sql
BEGIN;
DO $$
DECLARE ball bigint; concert bigint; weekend bigint;
BEGIN
 SELECT occasion INTO STRICT ball FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='ball';
 SELECT occasion INTO STRICT concert FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='concert';
 SELECT occasion INTO STRICT weekend FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='weekend';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions WHERE id IN(ball,concert,weekend) AND data->>'image' LIKE 'https://img.festapp.net/images/demo-occasions/20261014/%-cover-v1.jpg'),3::bigint,'all demos have introductory artwork');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=ball AND f->>'code'='ticket' AND (f#>>'{layout,templates,wide,ticketArea,width}')::numeric <= (f#>>'{layout,templates,wide,ticketArea,height}')::numeric),'ball ticket is landscape');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=concert AND f->>'code'='ticket' AND (f#>>'{layout,templates,wide,ticketArea,width}')::numeric < (f#>>'{layout,templates,wide,ticketArea,height}')::numeric),'concert ticket is portrait');
 PERFORM public.validate_ticket_layout_references(ball,(SELECT f->'layout' FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=ball AND f->>'code'='ticket'));
 PERFORM public.validate_ticket_layout_references(concert,(SELECT f->'layout' FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=concert AND f->>'code'='ticket'));
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=ball AND state<>'storno'),240::bigint,'240 ball tickets');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=concert AND state<>'storno'),55::bigint,'55 concert tickets');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=weekend AND state NOT IN ('storno','waitlisted')),24::bigint,'24 admitted');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=weekend AND state='waitlisted'),4::bigint,'4 waiting');
 PERFORM assert_eq((SELECT count(*) FROM eshop.blueprints WHERE occasion=ball),1::bigint,'only ball has a seating plan');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion IN (concert,weekend)),'concert and weekend have no plan');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.forms WHERE occasion IN (concert,weekend) AND blueprint IS NOT NULL),'their forms have no seat picker');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.tickets WHERE occasion=weekend AND ticket_symbol IS NOT NULL),'weekend applications have no admission QR');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=weekend AND f->>'code'='ticket' AND f->>'is_enabled'='false' AND NOT f ? 'layout'),'weekend ticket feature disabled without a layout');

 PERFORM assert_false(EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f
  WHERE o.id IN(ball,concert,weekend) AND f->>'code'='services' AND f->>'is_enabled'='true'),'no capacity groups in demo navigation');
 PERFORM assert_true((SELECT count(*) FILTER(WHERE state='sent') > count(*)::numeric*0.8
  FROM eshop.tickets WHERE occasion IN(ball,concert) AND state<>'storno'),'upcoming ticket events predominantly show sent tickets');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.tickets WHERE occasion IN(ball,concert) AND state='used'),'future events have no check-ins');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders WHERE occasion IN(ball,concert,weekend) AND created_at > '2026-10-14 12:00Z'),'sales precede fixture reference');
 PERFORM assert_true((SELECT count(DISTINCT created_at::date)>15 FROM eshop.orders WHERE occasion=ball),'report spans several weeks');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.transactions t JOIN public.demo_occasions d ON d.bank_account=t.bank_account_id
  WHERE d.occasion IN(ball,concert,weekend) AND t.date > '2026-10-14 12:00Z'),'payments precede fixture reference');

 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders WHERE occasion IN(ball,concert,weekend) AND state='paid'),'fully paid demo orders have been sent');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE o.occasion=ball AND o.state='ordered' AND p.paid=0 AND p.deadline<'2026-10-14 12:00Z'),'expired unpaid order uses ordinary deadline semantics');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE o.occasion=ball AND p.paid>p.amount),'overpayment example');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE o.occasion=ball AND p.paid>0 AND p.paid<p.amount AND o.state='ordered'),'partial payment stays pending');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.forms WHERE occasion=weekend AND header LIKE '%/demo-assets/weekend-nature.jpg%' AND header LIKE '%žádný e-mail%'),'illustrated weekend description with explicit simulation notice');
 PERFORM assert_true((SELECT count(*)>=10 FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form
  WHERE f.occasion=weekend AND ff.type IN ('phone','birth_year','select_one','select_many','text','note')),'realistic contact, travel, dietary and consent fields');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form
  WHERE f.occasion=weekend AND ff.type='select_many' AND ff.data ? 'default_value'),'consents are never preselected');

 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id
  JOIN eshop.orders o ON o.id=x."order" WHERE t.occasion=weekend AND t.state='waitlisted'
   AND (t.ticket_symbol IS NOT NULL OR x.product IS NOT NULL OR o.price IS NOT NULL OR o.payment_info IS NOT NULL)), 'waiting has no finance or admission');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.tickets t ON t.id=s.ticket_id
  WHERE t.occasion=weekend AND s.outcome='accepted' AND t.state='sent'),'accepted offer keeps ticket ID');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
  JOIN eshop.tickets t ON t.id=x.ticket WHERE public.is_demo_occasion(s.occasion) AND t.state='storno'),'cancelled tickets occupy no seats');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o WHERE public.is_demo_occasion(o.occasion)
  AND o.state NOT IN ('storno','waitlisted') AND o.price IS DISTINCT FROM
   (SELECT coalesce(sum(p.price),0) FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product WHERE x."order"=o.id)), 'order prices match actual active products');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE public.is_demo_occasion(o.occasion) AND p.amount IS DISTINCT FROM o.price),'payment amount follows order price');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o WHERE o.occasion=ball AND o.state<>'storno'
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=o.id AND t.state='storno')
  AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=o.id AND t.state<>'storno')), 'partial group cancellation example');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE public.is_demo_occasion(o.occasion) AND p.paid IS DISTINCT FROM
  (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t WHERE t.payment_info=p.id)), 'paid equals assigned movements');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.bank_accounts b JOIN public.demo_occasions d ON d.bank_account=b.id
   WHERE b.is_fetch_enabled OR b.account_number IS NOT NULL OR b.secret IS NOT NULL),'bank cannot route real payments');
END $$;

-- The same seed builds the English tenant without changing the Czech catalogue.
DO $english$
DECLARE org bigint; identities bigint[]; counts_before jsonb; untranslated text;
 cs_before text; demo_row record; b record;
BEGIN
 SELECT md5(string_agg(o::text,'|' ORDER BY o.id)) INTO cs_before
  FROM public.occasions o JOIN public.demo_occasions d ON d.occasion=o.id WHERE d.organization=1;
 SELECT coalesce(max(id),0)+1 INTO org FROM public.organizations;
 INSERT INTO public.organizations(id,title,data) VALUES(org,'Global demo test','{}');
 PERFORM pg_temp.seed_demo_occasions_localized(org,'en');
 SELECT array_agg(occasion ORDER BY sort_order) INTO identities FROM public.demo_occasions WHERE organization=org;
 PERFORM assert_eq(cardinality(identities),3,'one shared seed creates three English demos');
 PERFORM assert_eq((SELECT count(*) FROM public.demo_occasions WHERE organization=org AND is_listed),0::bigint,'new demos remain unlisted until verification');
 PERFORM assert_eq((SELECT count(*) FROM public.units WHERE organization=org),1::bigint,'one dedicated demo organizer');
 PERFORM assert_eq((SELECT title FROM public.units WHERE organization=org),'Festapp Tickets Demo','English organizer');
 PERFORM assert_true((SELECT bool_and(data->>'demo_locale'='en') FROM public.occasions WHERE id=ANY(identities)),'explicit locale metadata');
 PERFORM assert_eq((SELECT array_agg(title ORDER BY d.sort_order) FROM public.occasions o JOIN public.demo_occasions d ON d.occasion=o.id WHERE d.organization=org),
  ARRAY['Gala Ball','Live Concert','Weekend Retreat'],'English catalogue titles');
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots WHERE occasion=identities[1]),249::bigint,'shared canonical seating capacity');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=identities[1] AND state<>'storno'),240::bigint,'same ball sales rules');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=identities[3] AND state='waitlisted'),4::bigint,'same waiting-list rules');
 FOR b IN SELECT * FROM eshop.blueprints WHERE occasion=ANY(identities) LOOP
  PERFORM public.check_blueprint_text_resources_internal(b.layout,b.occasion);
  PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(b.layout->'nodes') n
   WHERE n->>'kind'='text' AND n->>'text' NOT IN('Balcony','Stage','Entrance','Stairs','Bar')),'English labels use actual canonical shaped resources');
 END LOOP;
 FOR demo_row IN SELECT * FROM public.demo_occasions WHERE organization=org LOOP
  PERFORM assert_true(public.is_demo_occasion(demo_row.occasion),'same server-owned demo identity');
  PERFORM assert_true(public.is_demo_unit((SELECT unit FROM public.occasions WHERE id=demo_row.occasion)),'dedicated organizer is protected');
  PERFORM assert_true((SELECT NOT is_fetch_enabled AND account_number IS NULL AND secret IS NULL FROM eshop.bank_accounts WHERE id=demo_row.bank_account),'no real payment routing');
 END LOOP;
 SELECT value INTO untranslated FROM (
  SELECT title||coalesce(description,'')||coalesce(data::text,'')||features::text AS value FROM public.occasions WHERE id=ANY(identities)
  UNION ALL SELECT title||coalesce(header,'')||coalesce(header_off,'') FROM public.forms WHERE occasion=ANY(identities)
  UNION ALL SELECT ff.title||coalesce(ff.description,'')||coalesce(ff.data::text,'') FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE f.occasion=ANY(identities)
  UNION ALL SELECT title||coalesce(description,'') FROM public.information WHERE occasion=ANY(identities)
  UNION ALL SELECT title||coalesce(description,'') FROM public.places WHERE occasion=ANY(identities)
  UNION ALL SELECT title FROM public.events WHERE occasion=ANY(identities)
  UNION ALL SELECT title FROM eshop.products WHERE occasion=ANY(identities)
  UNION ALL SELECT title FROM eshop.product_types WHERE occasion=ANY(identities)
  UNION ALL SELECT data::text FROM eshop.orders WHERE occasion=ANY(identities)
  UNION ALL SELECT data::text||coalesce(note,'') FROM eshop.tickets WHERE occasion=ANY(identities)
  UNION ALL SELECT h.data::text FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" WHERE o.occasion=ANY(identities)
 ) visible WHERE value~'[áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]' OR value LIKE '%vstupenky.online%' LIMIT 1;
 IF untranslated IS NOT NULL THEN RAISE EXCEPTION 'Untranslated English demo content: %',left(untranslated,240); END IF;
 SELECT jsonb_build_object('orders',(SELECT count(*) FROM eshop.orders WHERE occasion=ANY(identities)),
  'tickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=ANY(identities))) INTO counts_before;
 PERFORM pg_temp.seed_demo_occasions_localized(org,'en');
 PERFORM assert_eq((SELECT array_agg(occasion ORDER BY sort_order) FROM public.demo_occasions WHERE organization=org),identities,'English replay keeps identities');
 PERFORM assert_eq(jsonb_build_object('orders',(SELECT count(*) FROM eshop.orders WHERE occasion=ANY(identities)),
  'tickets',(SELECT count(*) FROM eshop.tickets WHERE occasion=ANY(identities))),counts_before,'English replay creates no extra examples');
 PERFORM assert_eq((SELECT md5(string_agg(o::text,'|' ORDER BY o.id)) FROM public.occasions o JOIN public.demo_occasions d ON d.occasion=o.id WHERE d.organization=1),cs_before,'Czech source catalogue remains unchanged');
 BEGIN
  PERFORM pg_temp.seed_demo_occasions_localized(org,'cs');
  RAISE EXCEPTION 'Locale overwrite must fail';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='Locale overwrite must fail' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM pg_temp.seed_demo_occasions_localized(org,'xx');
  RAISE EXCEPTION 'Unsupported locale must fail';
 EXCEPTION WHEN no_data_found THEN NULL;
 END;
END $english$;
ROLLBACK;
