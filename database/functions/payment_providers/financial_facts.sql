CREATE OR REPLACE FUNCTION public.provider_financial_totals_internal(p_provider text,p_payment bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE facts jsonb; k text;
BEGIN
 facts:=public.payment_provider_call_internal(p_provider,'totals',jsonb_build_object('paymentId',p_payment));
 IF facts IS NULL OR jsonb_typeof(facts)<>'object' OR NOT facts ?& ARRAY['received','returned','held','invalid']
  OR jsonb_typeof(facts->'invalid') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INCOMPLETE'; END IF;
 FOREACH k IN ARRAY ARRAY['received','returned','held'] LOOP
  IF jsonb_typeof(facts->k) IS DISTINCT FROM 'number' OR (facts->>k)::numeric<0
   OR (facts->>k)::numeric*100<>trunc((facts->>k)::numeric*100) THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INVALID'; END IF;
 END LOOP;
 IF (facts->>'returned')::numeric>(facts->>'received')::numeric THEN RAISE EXCEPTION 'PAYMENT_FINANCIAL_FACTS_INVALID'; END IF;
 RETURN facts;
END $$;
REVOKE ALL ON FUNCTION public.provider_financial_totals_internal(text,bigint) FROM PUBLIC,anon,authenticated,service_role;
