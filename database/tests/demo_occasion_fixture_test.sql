BEGIN;
DO $$
DECLARE ball bigint; concert bigint; weekend bigint;
BEGIN
 SELECT occasion INTO STRICT ball FROM public.demo_occasions WHERE organization=1 AND demo_key='ball';
 SELECT occasion INTO STRICT concert FROM public.demo_occasions WHERE organization=1 AND demo_key='concert';
 SELECT occasion INTO STRICT weekend FROM public.demo_occasions WHERE organization=1 AND demo_key='weekend';
 PERFORM assert_eq((SELECT ff.title FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form
  WHERE f.occasion=ball AND ff.type='ticket'),'Vstupenka'::text,'ball ticket label comes from field data');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.forms WHERE occasion=ball AND header LIKE '%<h2>%'),'ball header does not repeat event title');
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.occasion=ball AND p.price=650),50::bigint,'50 premium seats');
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.occasion=ball AND p.price=450),250::bigint,'250 standard seats');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
  WHERE s.occasion=ball AND s.product IS DISTINCT FROM x.product),'ordered seat retains its price product');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o WHERE o.occasion=ball AND o.state<>'storno' AND o.price IS DISTINCT FROM
  (SELECT sum(p.price) FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product WHERE x."order"=o.id)), 'ball totals reflect selected seat prices');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=ball AND state<>'storno'),260::bigint,'260 ball tickets');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=concert AND state<>'storno'),55::bigint,'55 concert tickets');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=weekend AND state NOT IN ('storno','waitlisted')),24::bigint,'24 admitted');
 PERFORM assert_eq((SELECT count(*) FROM eshop.tickets WHERE occasion=weekend AND state='waitlisted'),4::bigint,'4 waiting');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id
  JOIN eshop.orders o ON o.id=x."order" WHERE t.occasion=weekend AND t.state='waitlisted'
   AND (t.ticket_symbol IS NOT NULL OR x.product IS NOT NULL OR o.price IS NOT NULL OR o.payment_info IS NOT NULL)), 'waiting has no finance or admission');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.tickets t ON t.id=s.ticket_id
  WHERE t.occasion=weekend AND s.outcome='accepted' AND t.state='paid'),'accepted offer keeps ticket ID');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
  JOIN eshop.tickets t ON t.id=x.ticket WHERE public.is_demo_occasion(s.occasion) AND t.state='storno'),'cancelled tickets occupy no seats');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE public.is_demo_occasion(o.occasion) AND p.paid IS DISTINCT FROM
  (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t WHERE t.payment_info=p.id)), 'paid equals assigned movements');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.bank_accounts b JOIN public.demo_occasions d ON d.bank_account=b.id
   WHERE b.is_fetch_enabled OR b.account_number IS NOT NULL OR b.secret IS NOT NULL),'bank cannot route real payments');
END $$;
ROLLBACK;
