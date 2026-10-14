BEGIN;
DO $$
DECLARE ball bigint; concert bigint; weekend bigint;
BEGIN
 SELECT occasion INTO STRICT ball FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='ball';
 SELECT occasion INTO STRICT concert FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='concert';
 SELECT occasion INTO STRICT weekend FROM public.demo_occasions WHERE organization=1 AND fixture_version='2026-10-14.3' AND demo_key='weekend';
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

 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id
  JOIN eshop.orders o ON o.id=x."order" WHERE t.occasion=weekend AND t.state='waitlisted'
   AND (t.ticket_symbol IS NOT NULL OR x.product IS NOT NULL OR o.price IS NOT NULL OR o.payment_info IS NOT NULL)), 'waiting has no finance or admission');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.tickets t ON t.id=s.ticket_id
  WHERE t.occasion=weekend AND s.outcome='accepted' AND t.state='paid'),'accepted offer keeps ticket ID');
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
ROLLBACK;
