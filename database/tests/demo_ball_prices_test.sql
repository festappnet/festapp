-- test-setup: database/fixtures/demo_occasions/reference.sql
-- test-setup: database/fixtures/demo_occasions/seed.sql
-- test-setup: database/fixtures/demo_occasions/ball-prices.sql
BEGIN;
DO $$
DECLARE ball bigint; before_state jsonb; after_state jsonb;
BEGIN
 SELECT occasion INTO STRICT ball FROM public.demo_occasions WHERE organization=1 AND demo_key='ball' AND fixture_version='2026-10-14.3';
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots s JOIN eshop.products p ON p.id=s.product WHERE s.occasion=ball AND p.price=650),50::bigint,'premium price follows five table groups');
 PERFORM assert_eq((SELECT count(*) FROM eshop.spots s JOIN eshop.products p ON p.id=s.product WHERE s.occasion=ball AND p.price=450),199::bigint,'remaining seats use standard price');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.blueprints b CROSS JOIN LATERAL jsonb_array_elements(b.objects) ob
  JOIN eshop.spots s ON s.id=(ob->>'id')::bigint WHERE b.occasion=ball AND (s.title IS DISTINCT FROM ob->>'title'
   OR s.title !~ ('^'||(ob->>'group')||'[A-O]$'))),'seat labels carry table number and seat letter');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form WHERE f.occasion=ball AND ff.type='ticket' AND ff.title='Vstupenka'),'field label is data');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.forms WHERE occasion=ball AND header LIKE '%<h2>%'),'no duplicated title');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o WHERE o.occasion=ball AND o.state<>'storno' AND o.price IS DISTINCT FROM
  (SELECT coalesce(sum(p.price),0) FROM eshop.order_product_ticket x JOIN eshop.products p ON p.id=x.product
   JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=o.id AND t.state<>'storno')),'orders reflect active seats');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball
  AND (o.price IS DISTINCT FROM p.amount OR p.paid IS DISTINCT FROM (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t WHERE t.payment_info=p.id))),'payments match orders and movements');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball AND p.paid=0),'unpaid example retained');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball AND p.paid>0 AND p.paid<p.amount),'partial payment retained');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball AND p.paid>p.amount),'overpayment retained');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order"
  WHERE o.occasion=ball AND h.state<>'storno' AND EXISTS(SELECT 1 FROM jsonb_array_elements(h.data->'tickets') t CROSS JOIN LATERAL jsonb_array_elements(t->'products') p WHERE p->>'price' IS NOT NULL) AND h.price IS DISTINCT FROM
   (SELECT coalesce(sum((p->>'price')::numeric),0) FROM jsonb_array_elements(h.data->'tickets') t
    CROSS JOIN LATERAL jsonb_array_elements(t->'products') p)),'history prices match their own ticket snapshots');
 SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) INTO before_state FROM eshop.orders o WHERE o.occasion=ball;
 PERFORM pg_temp.refresh_demo_ball_prices(1);
 SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) INTO after_state FROM eshop.orders o WHERE o.occasion=ball;
 PERFORM assert_eq(after_state,before_state,'reapplying maintenance preserves all orders');
END $$;
ROLLBACK;
