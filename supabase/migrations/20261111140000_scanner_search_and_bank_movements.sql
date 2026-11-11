-- Ticket search by purchaser and gross bank roundtrip reporting.

-- Source: database/functions/scanning/admission.sql
CREATE OR REPLACE FUNCTION public.search_scanner_tickets(p_session uuid,p_token text,p_query text,p_after bigint DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token); SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN RAISE insufficient_privilege USING MESSAGE='manual_search_disabled'; END IF;
 IF length(p_query) NOT BETWEEN 2 AND 100 THEN RETURN jsonb_build_object('code',400,'reason','invalid_query','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT coalesce(jsonb_agg(dto ORDER BY ticket_id),'[]'::jsonb) INTO result FROM (
 SELECT * FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config) WHERE ticket_id>p_after
 AND (strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'purchaser_name'),lower(p_query))>0 OR strpos(lower(dto->>'batch_title'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;

-- Source: database/functions/eshop_transactions/payment_totals.sql
CREATE OR REPLACE FUNCTION public.payment_transaction_movements_bulk_internal(p_payments bigint[])
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 SELECT t.id::bigint,t.payment_info::bigint,t.amount,t.currency::text,t.date::timestamptz,
  coalesce(t.transaction_type='return',false) OR s.transaction_id IS NOT NULL
   -- Linked bank debits are returned money even when historical pairing
   -- predates refund requests. Keep signed manual corrections as receipts.
   OR coalesce(t.amount<0 AND t.ingest_source IN ('banksync_api','fio_api','legacy_api','legacy')
       AND t.transaction_type IS DISTINCT FROM 'manual',false),
  s.voided_at IS NOT NULL
 FROM (
  SELECT tx.* FROM eshop.transactions tx WHERE p_payments IS NULL
  UNION ALL
  SELECT tx.* FROM eshop.transactions tx WHERE p_payments IS NOT NULL AND tx.payment_info=ANY(p_payments)
 ) t LEFT JOIN eshop.refund_settlements s ON s.transaction_id=t.id;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_bulk_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.payment_transaction_movements_internal(p_payment bigint DEFAULT NULL)
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY SELECT * FROM public.payment_transaction_movements_bulk_internal(
  CASE WHEN p_payment IS NULL THEN NULL::bigint[] ELSE ARRAY[p_payment] END);
END;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
