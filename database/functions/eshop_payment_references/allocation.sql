CREATE OR REPLACE FUNCTION public.random_payment_reference_digits_internal(p_digits integer)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE value text:=''; bytes bytea; n integer; i integer;
BEGIN
 IF p_digits NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
 WHILE length(value)<p_digits LOOP
  bytes:=extensions.gen_random_bytes(32);
  FOR i IN 0..31 LOOP
   n:=get_byte(bytes,i);
   IF n>=250 OR (value='' AND mod(n,10)=0) THEN CONTINUE; END IF;
   value:=value||mod(n,10)::text;
   EXIT WHEN length(value)=p_digits;
  END LOOP;
 END LOOP;
 RETURN value::bigint;
END $$;

CREATE OR REPLACE FUNCTION public.reserve_payment_reference_internal(
 p_payment bigint,p_form bigint,p_source text,p_policy jsonb,p_payload_sha256 text)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE pi eshop.payment_info; account text; ns eshop.payment_reference_namespaces; previous eshop.payment_reference_reservations;
 phase text; mode text:=p_policy->>'mode'; value bigint; floor bigint; cursor bigint; digits integer; preferred integer; maximum integer; attempt integer;
 high bigint; normalized jsonb;
BEGIN
 SELECT s.phase INTO phase FROM eshop.payment_reference_scopes s JOIN public.occasions o ON o.organization=s.organization_id
 JOIN public.forms f ON f.occasion=o.id WHERE f.id=p_form;
 IF phase IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_SCOPE_NOT_ACTIVE'; END IF;
 PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE id=p_form));
 IF p_source IS NULL OR length(p_source) NOT BETWEEN 1 AND 255 OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[a-f0-9]{64}$'
 OR p_policy IS NULL OR jsonb_typeof(p_policy)<>'object' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
 IF mode='exact' THEN
  IF (p_policy-'mode'-'value')<>'{}'::jsonb OR jsonb_typeof(p_policy->'value') IS DISTINCT FROM 'string' OR coalesce(p_policy->>'value','') !~ '^[0-9]{1,10}$' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  value:=(p_policy->>'value')::bigint;
  IF value=0 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  normalized:=jsonb_build_object('mode',mode,'value',value::text);
 ELSIF mode='sequence' THEN
  IF (p_policy-'mode'-'from')<>'{}'::jsonb OR jsonb_typeof(p_policy->'from') IS DISTINCT FROM 'string' OR coalesce(p_policy->>'from','') !~ '^[0-9]{1,10}$'
   OR (p_policy->>'from')::bigint<1 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  normalized:=jsonb_build_object('mode',mode,'from',((p_policy->>'from')::bigint)::text);
 ELSIF mode='random' THEN
  IF (p_policy-'mode'-'preferred_digits'-'max_digits')<>'{}'::jsonb OR jsonb_typeof(p_policy->'preferred_digits') IS DISTINCT FROM 'number'
   OR (p_policy ? 'max_digits' AND jsonb_typeof(p_policy->'max_digits') IS DISTINCT FROM 'number')
   OR coalesce(p_policy->>'preferred_digits','') !~ '^[0-9]{1,2}$' OR coalesce(p_policy->>'max_digits','10') !~ '^[0-9]{1,2}$' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  digits:=(p_policy->>'preferred_digits')::integer;maximum:=coalesce((p_policy->>'max_digits')::integer,10);
  IF digits NOT BETWEEN 1 AND 10 OR maximum NOT BETWEEN digits AND 10 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  normalized:=jsonb_build_object('mode',mode,'preferred_digits',digits,'max_digits',maximum);
 ELSE RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
 -- Same lock order as the finalizer: form, namespace, then new payment. The
 -- namespace lock serializes aliases and separate forms inside this database.
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=p_payment;
 IF pi.amount<=0 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE payment_info=p_payment AND form=p_form) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_PAYMENT_SCOPE_INVALID'; END IF;
 SELECT n.* INTO ns FROM eshop.payment_reference_namespaces n JOIN eshop.payment_reference_accounts a ON a.namespace_id=n.id
 WHERE a.bank_account_id=pi.bank_account FOR UPDATE OF n;
 IF ns.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_NOT_ENROLLED'; END IF;
 SELECT public.canonical_payment_reference_account_internal(b.account_number) INTO account FROM eshop.bank_accounts b WHERE b.id=pi.bank_account AND b.type IS DISTINCT FROM 'CASH';
 IF account IS DISTINCT FROM ns.canonical_account THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
 SELECT * INTO previous FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND source_ref=p_source;
 IF previous.id IS NOT NULL THEN
  IF previous.payload_sha256<>p_payload_sha256 OR previous.policy<>normalized OR previous.original_payment_info_id IS DISTINCT FROM p_payment THEN
   RAISE EXCEPTION 'PAYMENT_REFERENCE_SOURCE_CONFLICT'; END IF;
  RETURN previous.variable_symbol;
 END IF;
 IF NOT ns.allocation_enabled THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_REGISTRY_LOCKED'; END IF;
 IF mode='sequence' THEN
  SELECT greatest(coalesce(max(p.variable_symbol),0),coalesce((SELECT high_water FROM eshop.payment_reference_form_watermarks WHERE form_id=p_form),0)) INTO high
   FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.form=p_form;
  SELECT high_water INTO cursor FROM eshop.payment_reference_sequences WHERE namespace_id=ns.id AND form_id=p_form;
  floor:=greatest((normalized->>'from')::bigint,high+1,coalesce(cursor+1,1));
  IF floor>9999999999 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_SEQUENCE_EXHAUSTED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND variable_symbol=floor) THEN value:=floor;
  ELSE
   SELECT r.variable_symbol+1 INTO value FROM eshop.payment_reference_reservations r
    WHERE r.namespace_id=ns.id AND r.variable_symbol>=floor AND r.variable_symbol<9999999999
    AND NOT EXISTS(SELECT 1 FROM eshop.payment_reference_reservations used WHERE used.namespace_id=ns.id AND used.variable_symbol=r.variable_symbol+1)
    ORDER BY r.variable_symbol LIMIT 1;
  END IF;
  IF value IS NULL THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_SEQUENCE_EXHAUSTED'; END IF;
 ELSIF mode='random' THEN
  preferred:=digits;
  <<find_random>>
  FOR digits IN preferred..maximum LOOP
   FOR attempt IN 1..16 LOOP
    value:=public.random_payment_reference_digits_internal(digits);
    EXIT find_random WHEN NOT EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND variable_symbol=value);
    value:=NULL;
   END LOOP;
  END LOOP;
  IF value IS NULL THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_RETRY_REQUIRED'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND variable_symbol=value) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_CONFLICT'; END IF;
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
 VALUES(ns.id,value,p_source,normalized,p_payload_sha256,p_payment,p_payment,p_form);
 IF mode='sequence' THEN
  INSERT INTO eshop.payment_reference_sequences(namespace_id,form_id,high_water) VALUES(ns.id,p_form,value)
  ON CONFLICT(namespace_id,form_id) DO UPDATE SET high_water=greatest(eshop.payment_reference_sequences.high_water,excluded.high_water);
 END IF;
 INSERT INTO eshop.payment_reference_form_watermarks(form_id,high_water) VALUES(p_form,value)
 ON CONFLICT(form_id) DO UPDATE SET high_water=greatest(eshop.payment_reference_form_watermarks.high_water,excluded.high_water);
 RETURN value;
END $$;

CREATE OR REPLACE FUNCTION public.reserve_order_payment_reference_internal(p_payment bigint,p_form bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE cfg jsonb; policy jsonb;
BEGIN
 SELECT coalesce(data->'variable_symbol','{}') INTO STRICT cfg FROM public.forms WHERE id=p_form;
 IF coalesce(cfg->>'type','random')='sequence' THEN
  IF coalesce(cfg->>'starting_number','') !~ '^[0-9]{1,10}$' OR (cfg->>'starting_number')::bigint<1 THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
  policy:=jsonb_build_object('mode','sequence','from',cfg->>'starting_number');
 ELSIF coalesce(cfg->>'type','random')='random' THEN
  policy:=jsonb_build_object('mode','random','preferred_digits',coalesce(cfg->'preferred_digits','4'), 'max_digits',coalesce(cfg->'max_digits','10'));
 ELSE RAISE EXCEPTION 'PAYMENT_REFERENCE_POLICY_INVALID'; END IF;
 RETURN public.reserve_payment_reference_internal(p_payment,p_form,'payment:'||p_payment,policy,
  encode(extensions.digest(jsonb_build_object('payment',p_payment,'form',p_form,'policy',policy)::text,'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.random_payment_reference_digits_internal(integer),
 public.reserve_payment_reference_internal(bigint,bigint,text,jsonb,text),public.reserve_order_payment_reference_internal(bigint,bigint)
 FROM PUBLIC,anon,authenticated,service_role;
