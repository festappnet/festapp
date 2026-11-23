-- Compare possible email duplicates by bank-local date.
CREATE OR REPLACE FUNCTION public.bank_sync_fact_dates_match_internal(p_tx eshop.transactions,p_data jsonb,p_days integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE tx_day date; incoming_day date; v_shift interval; v_offset integer;
BEGIN
 IF p_tx.ingest_source IN ('legacy','legacy_api','fio_api')
   AND p_data->>'date_offset_min' ~ '^-?[0-9]{1,3}$' THEN
  v_offset:=(p_data->>'date_offset_min')::integer;
 END IF;
 IF abs(v_offset)<=840 THEN
  v_shift:=make_interval(mins=>v_offset);
  tx_day:=(p_tx.date+v_shift)::date;
  incoming_day:=(((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+v_shift)::date;
 ELSE
  tx_day:=((p_tx.date AT TIME ZONE 'UTC') AT TIME ZONE 'Europe/Prague')::date;
  incoming_day:=((p_data->>'date')::timestamptz AT TIME ZONE 'Europe/Prague')::date;
 END IF;
 RETURN abs(tx_day-incoming_day)<=p_days;
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_fact_dates_match_internal(eshop.transactions,jsonb,integer) FROM PUBLIC,anon,authenticated,service_role;

-- Legacy Fio stored offset midnight as UTC; BankSync date-only statements use
-- noon UTC to retain the original bank date. Compare historical facts in the
-- bank's supplied offset, without rewriting either representation.
CREATE OR REPLACE FUNCTION public.bank_sync_existing_facts_match(p_tx eshop.transactions,p_data jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE v_shift interval:=interval '0'; v_offset integer;
BEGIN
  IF p_tx.ingest_source IN ('legacy','legacy_api','fio_api')
    AND p_data->>'date_offset_min' ~ '^-?[0-9]{1,3}$' THEN
    v_offset:=(p_data->>'date_offset_min')::integer;
    IF abs(v_offset)<=840 THEN v_shift:=make_interval(mins=>v_offset); END IF;
  END IF;
  RETURN p_tx.amount IS NOT DISTINCT FROM (p_data->>'amount_cents')::numeric/100
    AND trim(p_tx.currency) IS NOT DISTINCT FROM p_data->>'currency'
    AND (p_tx.date+v_shift)::date IS NOT DISTINCT FROM
      (((p_data->>'date')::timestamptz AT TIME ZONE 'UTC')+v_shift)::date
    AND nullif(trim(p_tx.vs),'') IS NOT DISTINCT FROM nullif(p_data->>'raw_vs','')
    AND (p_tx.payer_reference IS NULL OR p_tx.payer_reference IS NOT DISTINCT FROM p_data->>'payer_reference');
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.bank_sync_existing_facts_match(eshop.transactions,jsonb) TO service_role;
