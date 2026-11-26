-- Run on the verified database after installing the automatic refund migration.
-- Supply organization_id, unit_id and bank_account_id as psql variables.
-- Preview is the default. Pass -v apply=true to apply the selected matches.
\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif

BEGIN;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='5s';
SET LOCAL request.jwt.claim.role='service_role';

CREATE TEMP TABLE refund_replay_scope ON COMMIT DROP AS
SELECT :'organization_id'::bigint AS organization_id, :'unit_id'::bigint AS unit_id,
       :'bank_account_id'::bigint AS bank_account_id;

DO $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM refund_replay_scope s JOIN public.units u ON u.id=s.unit_id AND u.organization=s.organization_id
  JOIN eshop.unit_bank_accounts b ON b.unit=u.id AND b.bank_account=s.bank_account_id
  WHERE NOT public.is_demo_bank_account(b.bank_account)
 ) THEN
  RAISE EXCEPTION 'Bank account does not belong to the selected unit and organization';
 END IF;
END $$;

CREATE TEMP TABLE refund_replay_candidates ON COMMIT DROP AS
SELECT t.id AS movement_id, o.id AS order_id, t.date::date AS bank_date, t.currency, t.amount
FROM refund_replay_scope s
JOIN eshop.transactions t ON t.bank_account_id=s.bank_account_id
CROSS JOIN LATERAL public.bank_transaction_reference_candidates_internal(t) m
JOIN eshop.payment_info p ON p.id=m.payment_ids[1] AND p.payment_method='bank'
JOIN eshop.orders o ON o.payment_info=p.id
JOIN public.occasions oc ON oc.id=o.occasion AND oc.unit=s.unit_id AND oc.organization=s.organization_id
WHERE t.payment_info IS NULL AND t.amount<0
  AND t.ingest_source IN ('banksync_api','fio_api') AND t.transaction_type IS DISTINCT FROM 'manual'
  AND t.date>=(now() AT TIME ZONE 'UTC')-interval '30 days'
  AND t.date::date>=(o.created_at AT TIME ZONE 'UTC')::date
  AND cardinality(m.payment_ids)=1
  AND NOT EXISTS (SELECT 1 FROM eshop.orders other WHERE other.payment_info=p.id AND other.id<>o.id)
  AND NOT EXISTS (SELECT 1 FROM eshop.transaction_pairing_events e
                  WHERE e.transaction_snapshot_id=t.id AND e.method='manual_unlink')
  AND NOT EXISTS (SELECT 1 FROM public.bank_sync_api_review_row_internal(t.id) r
                  WHERE r.delivery_id IS NOT NULL AND r.resolution->>'action' IS DISTINCT FROM 'api_distinct');

TABLE refund_replay_candidates;

\if :apply
DO $$
DECLARE candidate record; result jsonb;
BEGIN
 FOR candidate IN SELECT * FROM refund_replay_candidates ORDER BY bank_date,movement_id LOOP
  result:=public.observe_bank_refund_internal(candidate.movement_id);
  IF result->>'matched' IS DISTINCT FROM 'true' OR (result->>'orderId')::bigint IS DISTINCT FROM candidate.order_id THEN
   RAISE EXCEPTION 'Refund target changed for movement %',candidate.movement_id;
  END IF;
 END LOOP;
END $$;
COMMIT;
\else
ROLLBACK;
\endif
