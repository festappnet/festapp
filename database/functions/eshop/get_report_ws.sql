CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE r jsonb; invalid_payment boolean;
BEGIN
  WITH scope AS MATERIALIZED (
    SELECT o.id, o.title FROM public.occasions o
    JOIN public.user_info u ON u.organization = o.organization AND u.id = auth.uid()
    WHERE o.id = public.resolve_occasion_link_internal(occasion_link) AND public.can_read_orders(o.id)
  ), orders_scope AS MATERIALIZED (
    SELECT o.* FROM eshop.orders o JOIN scope s ON s.id = o.occasion
  ), payments AS MATERIALIZED (
    SELECT p.* FROM eshop.payment_info p
    WHERE p.id IN (SELECT payment_info FROM orders_scope)
  ), invalid AS (
    SELECT EXISTS (SELECT 1 FROM payments p JOIN eshop.orders o ON o.payment_info = p.id
      WHERE o.occasion IS DISTINCT FROM (SELECT id FROM scope)
         OR o.currency_code IS DISTINCT FROM p.currency_code) AS value
  ), transactions_scope AS MATERIALIZED (
    SELECT t.* FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    WHERE t.currency=p.currency_code
  ), stripe_movements AS MATERIALIZED (
    SELECT m.*,a.payment_info_id FROM eshop.stripe_payment_movements m JOIN eshop.stripe_checkout_attempts a ON a.id=m.attempt_id
     JOIN payments p ON p.id=a.payment_info_id WHERE m.currency=p.currency_code::text
  ), financial_totals AS MATERIALIZED (
    SELECT p.id,t.* FROM payments p CROSS JOIN LATERAL public.payment_financial_totals_internal(p.id) t
  ), stripe_money AS (
    SELECT payment_info_id,(coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2) AS received,
     (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) AS returned
    FROM stripe_movements GROUP BY payment_info_id
  ), order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM orders_scope GROUP BY 1,2
  ), payment_days AS (
    SELECT day,currency,sum(received)::text AS received,sum(returned)::text AS returned FROM (
     SELECT date::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE amount>0),0) AS received,
      coalesce(-sum(amount) FILTER (WHERE amount<0),0) AS returned
      FROM transactions_scope GROUP BY 1,2
     UNION ALL
     SELECT (occurred_at AT TIME ZONE 'Europe/Prague')::date,currency,
      (coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2),
      (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) FROM stripe_movements GROUP BY 1,2
    ) facts GROUP BY day,currency
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual' AND t.amount > 0) AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(p.paid,0)) AS received,
      sum(coalesce(p.returned,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      sum(coalesce(sm.received,0)) AS stripe_received,sum(coalesce(sm.returned,0)) AS stripe_refunded,
      sum(coalesce(ft.disputed,0)) AS disputed,sum(coalesce(p.paid_externally,0)) AS external_unattributed,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(p.paid,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(p.paid,0)-p.deposit_amount,0) ELSE 0 END) AS beyond
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id LEFT JOIN stripe_money sm ON sm.payment_info_id=p.id
     LEFT JOIN financial_totals ft ON ft.id=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.stripe_received,0) AS stripe_received,coalesce(p.stripe_refunded,0) AS stripe_refunded,
      coalesce(p.disputed,0) AS disputed,coalesce(p.external_unattributed,0) AS external_unattributed,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond
    FROM order_money o FULL JOIN payment_money p USING(currency)
  ), ticket_scope AS (
    SELECT t.* FROM eshop.tickets t JOIN scope s ON s.id=t.occasion
    WHERE EXISTS (SELECT 1 FROM eshop.order_product_ticket i WHERE i.ticket=t.id)
  ), valid_orders AS MATERIALIZED (
    SELECT * FROM orders_scope WHERE state IS DISTINCT FROM 'storno' AND state IS DISTINCT FROM 'waitlisted'
  ), valid_tickets AS MATERIALIZED (
    SELECT t.* FROM ticket_scope t
    WHERE t.state IS DISTINCT FROM 'storno' AND EXISTS (
      SELECT 1 FROM eshop.order_product_ticket i JOIN valid_orders o ON o.id=i."order"
      WHERE i.ticket=t.id
    )
  ), valid_order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM valid_orders GROUP BY 1,2
  ), ticket_order_dates AS (
    SELECT DISTINCT ON (t.id) t.id,t.created_at,o.currency_code
    FROM ticket_scope t JOIN eshop.order_product_ticket i ON i.ticket=t.id
    JOIN orders_scope o ON o.id=i."order"
    ORDER BY t.id,o.created_at,o.id
  ), valid_ticket_order_dates AS (
    SELECT DISTINCT ON (t.id) t.id,t.created_at,o.currency_code
    FROM valid_tickets t JOIN eshop.order_product_ticket i ON i.ticket=t.id
    JOIN valid_orders o ON o.id=i."order"
    ORDER BY t.id,o.created_at,o.id
  ), ticket_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,
      currency_code::text AS currency,count(*) AS count
    FROM ticket_order_dates GROUP BY 1,2
  ), valid_ticket_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,
      currency_code::text AS currency,count(*) AS count
    FROM valid_ticket_order_dates GROUP BY 1,2
  ), order_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM orders_scope GROUP BY 1
  ), ticket_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM ticket_scope GROUP BY 1
  ), spots AS (
    SELECT count(*) AS total,count(*) FILTER (WHERE order_product_ticket IS NOT NULL) AS occupied,
      count(*) FILTER (WHERE order_product_ticket IS NULL) AS free
    FROM eshop.spots WHERE occasion IN (SELECT id FROM scope)
  ), products AS (
    SELECT p.id::text AS product_id,coalesce(p.title,'') AS product_title,
      pt.id::text AS type_id,pt.title AS type_title,count(*) AS confirmed_count
    FROM orders_scope o JOIN eshop.order_product_ticket i ON i."order"=o.id
    JOIN eshop.products p ON p.id=i.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
    WHERE o.state IN ('paid','sent','used') GROUP BY p.id,pt.id
  ), warnings AS (
    SELECT 'missing_order_price' AS code,count(*) AS count FROM orders_scope WHERE price IS NULL AND state IS DISTINCT FROM 'waitlisted' HAVING count(*)>0
    UNION ALL SELECT 'transaction_currency_mismatch',count(*) FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info WHERE t.currency<>p.currency_code HAVING count(*)>0
    UNION ALL SELECT 'negative_other_received',count(*) FROM money WHERE received-manual<0 HAVING count(*)>0
    UNION ALL SELECT 'external_unattributed',count(*) FROM payments WHERE coalesce(paid_externally,0)<>0 HAVING count(*)>0
    UNION ALL SELECT 'payment_total_without_ledger',count(*) FROM payments p JOIN financial_totals ft ON ft.id=p.id
     WHERE coalesce(p.paid,0)<>ft.gross_received OR coalesce(p.returned,0)<>ft.refunded HAVING count(*)>0
  )
  SELECT jsonb_build_object(
    'schema_version',1,'occasion',jsonb_build_object('id',s.id::text,'title',coalesce(s.title,'')),
    'generated_at',to_char(statement_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'spots',(SELECT to_jsonb(spots) FROM spots),
    'orders',jsonb_build_object('total',(SELECT count(*) FROM orders_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM order_states x),'[]'::jsonb)),
    'tickets',jsonb_build_object('total',(SELECT count(*) FROM ticket_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM ticket_states x),'[]'::jsonb)),
    'valid',jsonb_build_object(
      'orders',jsonb_build_object('total',(SELECT count(*) FROM valid_orders),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_orders GROUP BY 1) x),'[]'::jsonb)),
      'tickets',jsonb_build_object('total',(SELECT count(*) FROM valid_tickets),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_tickets GROUP BY 1) x),'[]'::jsonb)),
      'ticket_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_ticket_days d),'[]'::jsonb),
      'order_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_order_days d),'[]'::jsonb)
    ),
    'money_by_currency',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'currency',currency,'current_order_value',value::text,'received',received::text,'returned',returned::text,
      'net_received',(received-returned)::text,'manual_received',manual::text,'other_received',(received-manual)::text,
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text
    ) || CASE WHEN stripe_received>0 OR stripe_refunded>0 OR disputed>0 THEN jsonb_build_object(
      'stripe_received',stripe_received::numeric(30,2)::text,'stripe_refunded',stripe_refunded::numeric(30,2)::text,'disputed',disputed::numeric(30,2)::text,
      'available_after_disputes',greatest(received-returned-disputed,0)::numeric(30,2)::text) ELSE '{}'::jsonb END
      || CASE WHEN external_unattributed<>0 THEN jsonb_build_object('external_unattributed',external_unattributed::text) ELSE '{}'::jsonb END
     ORDER BY currency) FROM money),'[]'::jsonb),
    'timeline',jsonb_build_object(
      'order_timezone','Europe/Prague','payment_date_basis','bank_transaction_date_and_provider_occurrence',
      'tickets',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM ticket_days d),'[]'::jsonb),
      'orders',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day) FROM order_days d),'[]'::jsonb),
      'payments',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM payment_days d),'[]'::jsonb)
    ),
    'products',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY type_id,product_id) FROM products p),'[]'::jsonb),
    'warnings',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY code) FROM warnings w),'[]'::jsonb)
  ), invalid.value INTO r,invalid_payment FROM scope s CROSS JOIN invalid;
  IF r IS NULL THEN RETURN jsonb_build_object('code',403,'message','Report unavailable or access denied.'); END IF;
  IF invalid_payment THEN RETURN jsonb_build_object('code',409,'message','Report payment allocation is inconsistent.'); END IF;
  RETURN jsonb_build_object('code',200,'data',public.format_occasion_report_text(r),'report',r);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code',500,'message','Report could not be generated.');
END;
$$;
REVOKE ALL ON FUNCTION public.get_report_ws(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_ws(text) TO authenticated;
