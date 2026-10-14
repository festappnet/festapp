-- Source: fixture maintenance in database/fixtures/demo_occasions/seed.sql
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
   IF o.state='ordered' THEN stamp:=anchor-interval '2 days'+o.seq*interval '3 minutes'; END IF;
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
   ticket_state:=CASE WHEN d.demo_key<>'weekend' AND o.state IN ('paid','sent')
     AND o.seq%11<>0 THEN 'sent' ELSE o.state END;
   UPDATE eshop.orders SET state=ticket_state WHERE id=o.id;
   UPDATE eshop.tickets SET created_at=stamp,updated_at=stamp+interval '36 hours',
      waitlist_queue_at=CASE WHEN waitlist_queue_at IS NOT NULL THEN stamp END,
      state=CASE WHEN state IN ('paid','sent','used') THEN ticket_state ELSE state END
     WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id);
   IF ticket_state='sent' AND NOT EXISTS(SELECT 1 FROM eshop.orders_history WHERE "order"=o.id AND state='sent') THEN
    INSERT INTO eshop.orders_history("order",created_at,state,price,currency_code,data)
    VALUES(o.id,stamp+interval '36 hours','sent',o.price,o.currency_code,o.data);
   END IF;
   UPDATE eshop.orders_history SET created_at=stamp+interval '36 hours' WHERE "order"=o.id AND state='sent';
   IF EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id) THEN
    UPDATE eshop.payment_info SET created_at=stamp+interval '24 hours' WHERE id=o.payment_info;
    UPDATE eshop.transactions SET date=stamp+interval '36 hours' WHERE payment_info=o.payment_info;
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

-- Only the explicitly selected production tenant. Existing links and IDs stay intact.
SELECT pg_temp.refresh_demo_presentation(3);
