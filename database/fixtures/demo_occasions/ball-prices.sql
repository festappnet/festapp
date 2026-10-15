-- Registered synthetic ball only. No checkout, email, banking or ticket delivery.
-- Labels are copied from the sanitized Scout ball reference, never from attendees.
CREATE OR REPLACE FUNCTION pg_temp.reprice_demo_ball_snapshot(value jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE tickets jsonb:='[]'; products jsonb; ticket jsonb; v_product jsonb; seat record;
BEGIN
 IF NOT value ? 'tickets' THEN RETURN value; END IF;
 FOR ticket IN SELECT v FROM jsonb_array_elements(value->'tickets') a(v) LOOP
  products:='[]';
  FOR v_product IN SELECT v FROM jsonb_array_elements(coalesce(ticket->'products','[]')) a(v) LOOP
   SELECT * INTO seat FROM pg_temp.demo_ball_seat_patch
    WHERE old_title=v_product->>'spot_title' OR title=v_product->>'spot_title' LIMIT 1;
   IF FOUND THEN
    v_product:=v_product||jsonb_build_object('id',seat.product,'price',seat.price,
     'title',seat.product_title,'spot_title',seat.title);
   END IF;
   products:=products||jsonb_build_array(v_product);
  END LOOP;
  tickets:=tickets||jsonb_build_array(ticket||jsonb_build_object('products',products));
 END LOOP;
 RETURN jsonb_set(value,'{tickets}',tickets);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.refresh_demo_ball_prices(p_org bigint)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE ball bigint; bank bigint; v_blueprint bigint; standard bigint; premium bigint;
 item record; new_data jsonb; after_total numeric;
BEGIN
 IF current_user<>'postgres' THEN RAISE insufficient_privilege; END IF;
 PERFORM pg_advisory_xact_lock(7141014,p_org::integer);
 SELECT occasion,bank_account INTO STRICT ball,bank FROM public.demo_occasions
  WHERE organization=p_org AND fixture_version='2026-10-14.3' AND demo_key='ball';
 PERFORM 1 FROM public.occasions WHERE id=ball AND organization=p_org FOR UPDATE;
 PERFORM 1 FROM public.forms WHERE occasion=ball FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE occasion=ball FOR UPDATE;
 SELECT id INTO STRICT v_blueprint FROM eshop.blueprints WHERE occasion=ball FOR UPDATE;
 SELECT id INTO STRICT standard FROM eshop.products WHERE occasion=ball AND title='Základní vstupné' AND price=450 FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.bank_accounts WHERE id=bank AND NOT is_fetch_enabled AND account_number IS NULL AND secret IS NULL)
 OR EXISTS(SELECT 1 FROM eshop.payment_info p JOIN eshop.orders o ON o.payment_info=p.id WHERE o.occasion=ball AND p.bank_account<>bank)
 OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE o.occasion=ball AND p.paid IS DISTINCT FROM (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t WHERE t.payment_info=p.id)) THEN
  RAISE EXCEPTION 'Unexpected demo bank/payment configuration';
 END IF;
 SELECT id INTO premium FROM eshop.products WHERE occasion=ball AND title='Vstupné - stoly 1-5';
 IF premium IS NULL THEN
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code,maximum)
   SELECT ball,product_type,'Vstupné - stoly 1-5',650,'CZK',NULL FROM eshop.products WHERE id=standard RETURNING id INTO premium;
 END IF;
 CREATE TEMP TABLE demo_ball_seat_patch ON COMMIT DROP AS
 SELECT s.id,s.title old_title,r->>'title' title,
  CASE WHEN (r->>'group')::int BETWEEN 1 AND 5 THEN premium ELSE standard END product,
  CASE WHEN (r->>'group')::int BETWEEN 1 AND 5 THEN 650 ELSE 450 END price,
  CASE WHEN (r->>'group')::int BETWEEN 1 AND 5 THEN 'Vstupné - stoly 1-5' ELSE 'Základní vstupné' END product_title
 FROM eshop.blueprints b CROSS JOIN LATERAL jsonb_array_elements(b.objects) ob
 JOIN eshop.spots s ON s.id=(ob->>'id')::bigint AND s.blueprint=b.id
 CROSS JOIN pg_temp.demo_reference_blueprint ref CROSS JOIN LATERAL jsonb_array_elements(ref.content->'objects') r
 WHERE b.id=v_blueprint AND ob->>'type'='spot'
  AND r->'x'=ob->'x' AND r->'y'=ob->'y' AND r->'group'=ob->'group';
 IF (SELECT count(*) FROM pg_temp.demo_ball_seat_patch)<>249
 OR (SELECT count(DISTINCT id) FROM pg_temp.demo_ball_seat_patch)<>249
 OR (SELECT count(DISTINCT title) FROM pg_temp.demo_ball_seat_patch)<>249
 OR (SELECT count(*) FROM pg_temp.demo_ball_seat_patch WHERE price=650)<>50 THEN
  RAISE EXCEPTION 'Ball layout differs from the reviewed Scout reference';
 END IF;
 UPDATE eshop.spots s SET title=m.title,product=m.product FROM pg_temp.demo_ball_seat_patch m WHERE s.id=m.id;
 UPDATE eshop.blueprints b SET objects=(SELECT jsonb_agg(ob||jsonb_build_object('title',m.title) ORDER BY n)
  FROM jsonb_array_elements(b.objects) WITH ORDINALITY a(ob,n) JOIN pg_temp.demo_ball_seat_patch m ON m.id=(ob->>'id')::bigint)
  WHERE b.id=v_blueprint;
 UPDATE eshop.order_product_ticket x SET product=s.product FROM eshop.spots s WHERE s.blueprint=v_blueprint AND s.order_product_ticket=x.id;
 UPDATE public.forms SET header='<p>Vyberte si místo v plánku sálu. Stoly 1-5: 650 Kč, ostatní stoly: 450 Kč. Všechny uvedené údaje jsou fiktivní.</p>' WHERE occasion=ball;
 UPDATE public.form_fields SET title='Vstupenka' WHERE form IN(SELECT id FROM public.forms WHERE occasion=ball) AND type='ticket';
 FOR item IN SELECT o.id,o.price,o.payment_info,p.amount,p.paid,
  (SELECT coalesce(sum(prod.price),0) FROM eshop.order_product_ticket x JOIN eshop.products prod ON prod.id=x.product
   JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=o.id AND t.state<>'storno') total
  FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball AND o.state<>'storno' LOOP
  UPDATE eshop.orders SET price=item.total WHERE id=item.id;
  IF item.payment_info IS NOT NULL THEN
   -- Preserve the examples' unpaid balances and overpayments, including split movements.
   after_total:=CASE WHEN item.paid=0 THEN 0 ELSE greatest(0,item.total+item.paid-item.amount) END;
   WITH movements AS (
    SELECT id,round(amount*after_total/nullif(item.paid,0),2) amount,row_number() OVER(ORDER BY id DESC) last,
     sum(round(amount*after_total/nullif(item.paid,0),2)) OVER() rounded_total
    FROM eshop.transactions WHERE payment_info=item.payment_info
   ) UPDATE eshop.transactions t SET amount=m.amount+CASE WHEN m.last=1 THEN after_total-m.rounded_total ELSE 0 END
     FROM movements m WHERE t.id=m.id;
   UPDATE eshop.payment_info SET amount=item.total,paid=after_total WHERE id=item.payment_info;
  END IF;
 END LOOP;
 UPDATE eshop.orders SET data=pg_temp.demo_order_snapshot(id) WHERE occasion=ball;
 FOR item IN SELECT h.* FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" WHERE o.occasion=ball LOOP
  new_data:=pg_temp.reprice_demo_ball_snapshot(item.data);
  SELECT sum((p->>'price')::numeric) INTO after_total FROM jsonb_array_elements(coalesce(new_data->'tickets','[]')) t
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p;
  UPDATE eshop.orders_history SET data=new_data,price=coalesce(after_total,item.price) WHERE id=item.id;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.occasion=ball
  AND (o.price IS DISTINCT FROM p.amount OR p.paid IS DISTINCT FROM (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t WHERE t.payment_info=p.id))) THEN
  RAISE EXCEPTION 'Repriced demo financial totals do not agree';
 END IF;
 DROP TABLE pg_temp.demo_ball_seat_patch;
END $$;
