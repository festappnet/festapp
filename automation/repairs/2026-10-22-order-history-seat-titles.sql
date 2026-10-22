-- Approved one-time repair for the three investigated Ples AKH 2026 orders.
-- Default is a read-only preview. Apply only with festapp.repair_apply=on.
-- No current order, ticket, seat assignment, price, state or timestamp is changed.
BEGIN;
DO $$
BEGIN
 IF (SELECT count(*) FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
     WHERE oc.organization=3 AND oc.id=1072585 AND
       (o.id,o.order_symbol) IN ((6764,'5G7U7I8C5Y'),(6776,'8H7U7L9P6M'),(6777,'9P2X6K6R4J')))<>3 THEN
  RAISE EXCEPTION 'Repair target identity mismatch';
 END IF;
END $$;
CREATE TEMP TABLE seat_history_repair_candidates ON COMMIT DROP AS
WITH original AS (
 SELECT DISTINCT ON (h."order") h.* FROM eshop.orders_history h
 WHERE h."order" IN (6764,6776,6777) ORDER BY h."order",h.created_at,h.id
), proven AS (
 SELECT initial."order",(t->>'id')::bigint AS ticket_id,x.product,s.title
 FROM original initial
 CROSS JOIN LATERAL jsonb_array_elements(initial.data->'tickets') WITH ORDINALITY tickets(t,ti)
 JOIN eshop.order_product_ticket x ON x."order"=initial."order" AND x.ticket=(t->>'id')::bigint
 JOIN eshop.spots s ON s.order_product_ticket=x.id AND s.product=x.product
   AND s.id=(initial.data#>>ARRAY['input_data','ticket',(ti-1)::text,'spot'])::bigint
 JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
 WHERE nullif(s.title,'') IS NOT NULL
 AND NOT EXISTS (
  SELECT 1 FROM eshop.orders_history other
  CROSS JOIN LATERAL jsonb_array_elements(other.data->'tickets') ot
  CROSS JOIN LATERAL jsonb_array_elements(ot->'products') op
  WHERE other."order"=initial."order" AND ot->>'id'=t->>'id' AND op->>'id'=x.product::text
    AND nullif(op->>'spot_title','') IS NOT NULL AND op->>'spot_title'<>s.title
 )
)
SELECT h.id AS history_id,h."order" AS order_id,
 ARRAY['tickets',(ti-1)::text,'products',(pi-1)::text,'spot_title'] AS path,
 proven.title
FROM proven JOIN eshop.orders_history h ON h."order"=proven."order"
CROSS JOIN LATERAL jsonb_array_elements(h.data->'tickets') WITH ORDINALITY tickets(t,ti)
CROSS JOIN LATERAL jsonb_array_elements(t->'products') WITH ORDINALITY products(p,pi)
WHERE t->>'id'=proven.ticket_id::text AND p->>'id'=proven.product::text
  AND nullif(p->>'spot_title','') IS NULL;
SELECT count(*) AS labels_to_restore,count(DISTINCT history_id) AS history_rows,
 count(DISTINCT order_id) AS orders FROM seat_history_repair_candidates;
DO $$
DECLARE candidate record; restored integer:=0;
BEGIN
 IF current_setting('festapp.repair_apply',true) IS DISTINCT FROM 'on' THEN RETURN; END IF;
 FOR candidate IN SELECT * FROM seat_history_repair_candidates ORDER BY history_id,path LOOP
  UPDATE eshop.orders_history h SET data=jsonb_set(h.data,candidate.path,to_jsonb(candidate.title),true)
  WHERE h.id=candidate.history_id AND nullif(h.data#>>candidate.path,'') IS NULL;
  IF FOUND THEN restored:=restored+1; END IF;
 END LOOP;
 RAISE NOTICE 'Restored % missing history seat labels',restored;
END $$;
COMMIT;
