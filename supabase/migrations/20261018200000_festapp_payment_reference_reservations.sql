-- Festapp-owned payment references; activation is a separate scoped operation.

-- Source: database/functions/eshop_payment_references/schema.sql
-- Festapp-only registry. A migration installs dormant schema, never activates a tenant.
CREATE TABLE IF NOT EXISTS eshop.payment_reference_scopes (
 organization_id bigint PRIMARY KEY REFERENCES public.organizations(id),
 phase text NOT NULL CHECK(phase IN ('inactive','active','paused')),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_namespaces (
 id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{64}$'),
 canonical_account text NOT NULL UNIQUE,
 allocation_enabled boolean NOT NULL DEFAULT false,
 manifest_sha256 text CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Alias tombstones survive bank-account deletion; IDs are never namespace identity.
CREATE TABLE IF NOT EXISTS eshop.payment_reference_accounts (
 bank_account_id bigint PRIMARY KEY,
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 account_number_snapshot text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_reservations (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 variable_symbol bigint NOT NULL CHECK(variable_symbol BETWEEN 0 AND 9999999999),
 source_ref text NOT NULL CHECK(length(source_ref) BETWEEN 1 AND 255),
 policy jsonb NOT NULL,
 payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[a-f0-9]{64}$'),
 payment_info_id bigint REFERENCES eshop.payment_info(id) ON DELETE SET NULL,
 original_payment_info_id bigint,
 form_id bigint,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(namespace_id,variable_symbol),UNIQUE(namespace_id,source_ref)
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_sequences (
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 form_id bigint NOT NULL,
 high_water bigint NOT NULL CHECK(high_water BETWEEN 1 AND 9999999999),
 PRIMARY KEY(namespace_id,form_id)
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_form_watermarks (
 form_id bigint PRIMARY KEY,
 high_water bigint NOT NULL CHECK(high_water BETWEEN 0 AND 9999999999)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['payment_reference_scopes','payment_reference_namespaces','payment_reference_accounts',
  'payment_reference_reservations','payment_reference_sequences','payment_reference_form_watermarks'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I OWNER TO postgres',t);
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON eshop.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT ON eshop.%I TO service_role',t);
 END LOOP;
END $$;


-- Source: database/functions/eshop_payment_references/identity.sql
CREATE OR REPLACE FUNCTION public.canonical_payment_reference_account_internal(p_account text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE account text:=upper(regexp_replace(coalesce(p_account,''),'[[:space:]]','','g'));
 parts text[]; bban text; digits text; checksum integer;
BEGIN
 parts:=regexp_match(account,'^(?:([0-9]{1,6})-)?([0-9]{1,10})/([0-9]{4})$');
 IF parts IS NOT NULL THEN
  bban:=parts[3]||lpad(coalesce(parts[1],'0'),6,'0')||lpad(parts[2],10,'0');
  checksum:=98-mod((bban||'123500')::numeric,97)::integer;
  account:='CZ'||lpad(checksum::text,2,'0')||bban;
 END IF;
 IF account='' OR NOT public.is_valid_iban(account) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_INVALID'; END IF;
 RETURN account;
END $$;
CREATE OR REPLACE FUNCTION public.payment_reference_scope_enabled_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.payment_reference_scopes s JOIN public.occasions o ON o.organization=s.organization_id
 JOIN public.forms f ON f.occasion=o.id WHERE f.id=p_form AND s.phase IN ('active','paused'));
$$;
CREATE OR REPLACE FUNCTION public.enroll_payment_reference_account(p_bank_account bigint)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE account text; namespace text; existing text;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.check_bank_account_writable(p_bank_account);
 SELECT account_number INTO STRICT account FROM eshop.bank_accounts WHERE id=p_bank_account AND type IS DISTINCT FROM 'CASH' FOR UPDATE;
 namespace:=encode(extensions.digest(public.canonical_payment_reference_account_internal(account),'sha256'),'hex');
 INSERT INTO eshop.payment_reference_namespaces(id,canonical_account)
 VALUES(namespace,public.canonical_payment_reference_account_internal(account)) ON CONFLICT DO NOTHING;
 INSERT INTO eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot)
 VALUES(p_bank_account,namespace,account) ON CONFLICT DO NOTHING;
 SELECT namespace_id INTO existing FROM eshop.payment_reference_accounts WHERE bank_account_id=p_bank_account;
 IF existing<>namespace THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
 RETURN namespace;
END $$;
REVOKE ALL ON FUNCTION public.canonical_payment_reference_account_internal(text),public.payment_reference_scope_enabled_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.enroll_payment_reference_account(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enroll_payment_reference_account(bigint) TO service_role;

-- Inventory only: malformed unrelated accounts must not break grouping. Issuing
-- always calls the strict validator above and never falls back to an ID/string.
CREATE OR REPLACE FUNCTION public.try_payment_reference_account_internal(p_account text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN RETURN public.canonical_payment_reference_account_internal(p_account);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.try_payment_reference_account_internal(text) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_payment_references/allocation.sql
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


-- Source: database/functions/eshop_payment_references/operations.sql
CREATE OR REPLACE FUNCTION public.import_payment_reference(
 p_bank_account bigint,p_source text,p_symbol bigint,p_payload_sha256 text,
 p_payment bigint DEFAULT NULL,p_form bigint DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ns eshop.payment_reference_namespaces; old eshop.payment_reference_reservations; result uuid;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.check_bank_account_writable(p_bank_account);
 IF p_symbol IS NULL OR p_symbol NOT BETWEEN 0 AND 9999999999 OR p_source IS NULL OR length(p_source) NOT BETWEEN 1 AND 255
 OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_INVALID'; END IF;
 SELECT n.* INTO STRICT ns FROM eshop.payment_reference_namespaces n JOIN eshop.payment_reference_accounts a ON a.namespace_id=n.id
 WHERE a.bank_account_id=p_bank_account FOR UPDATE OF n;
 IF ns.allocation_enabled THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_REQUIRES_LOCK'; END IF;
 IF p_payment IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=p_payment AND bank_account=p_bank_account AND variable_symbol=p_symbol) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_PAYMENT_MISMATCH'; END IF;
 SELECT * INTO old FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND source_ref=p_source;
 IF old.id IS NOT NULL THEN
  IF old.variable_symbol<>p_symbol OR old.payload_sha256<>p_payload_sha256 OR old.original_payment_info_id IS DISTINCT FROM p_payment OR old.form_id IS DISTINCT FROM p_form THEN
   RAISE EXCEPTION 'PAYMENT_REFERENCE_SOURCE_CONFLICT'; END IF;
  RETURN old.id;
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND variable_symbol=p_symbol) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_HISTORICAL_CONFLICT'; END IF;
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
 VALUES(ns.id,p_symbol,p_source,'{"mode":"historical"}',p_payload_sha256,p_payment,p_payment,p_form) RETURNING id INTO result;
 IF p_form IS NOT NULL THEN
  INSERT INTO eshop.payment_reference_form_watermarks(form_id,high_water) VALUES(p_form,p_symbol)
  ON CONFLICT(form_id) DO UPDATE SET high_water=greatest(eshop.payment_reference_form_watermarks.high_water,excluded.high_water);
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.import_payment_reference(bigint,text,bigint,text,bigint,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.import_payment_reference(bigint,text,bigint,text,bigint,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.activate_payment_reference_scope(p_organization bigint,p_manifest_sha256 text,p_history_reviewed boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE namespace text; namespaces text[];
BEGIN
 PERFORM public.require_service_role();
 IF p_history_reviewed IS DISTINCT FROM true OR p_manifest_sha256 IS NULL OR p_manifest_sha256 !~ '^[a-f0-9]{64}$'
  OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACTIVATION_REVIEW_REQUIRED'; END IF;
 -- Drain old order writers at their existing form locks before enabling the scope.
 PERFORM 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE o.organization=p_organization ORDER BY f.id FOR UPDATE OF f;
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
  JOIN eshop.bank_accounts b ON b.id=u.bank_account
  LEFT JOIN eshop.payment_reference_accounts a ON a.bank_account_id=b.id
  WHERE o.organization=p_organization AND b.type IS DISTINCT FROM 'CASH' AND NOT public.is_demo_occasion(o.id) AND a.bank_account_id IS NULL) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_NOT_ENROLLED'; END IF;
 SELECT array_agg(DISTINCT a.namespace_id ORDER BY a.namespace_id) INTO namespaces FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
 JOIN eshop.payment_reference_accounts a ON a.bank_account_id=u.bank_account WHERE o.organization=p_organization AND NOT public.is_demo_occasion(o.id);
 IF namespaces IS NULL THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_NO_ENROLLED_DESTINATION'; END IF;
 FOREACH namespace IN ARRAY namespaces LOOP
  PERFORM 1 FROM eshop.payment_reference_namespaces WHERE id=namespace FOR UPDATE;
 END LOOP;
 -- Conservative: all configured destination candidates sharing a physical account
 -- must participate. An unenrolled alias cannot evade the writer inventory.
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
 JOIN eshop.bank_accounts b ON b.id=u.bank_account JOIN eshop.payment_reference_namespaces n ON n.id=ANY(namespaces)
  AND public.try_payment_reference_account_internal(b.account_number)=n.canonical_account
 WHERE o.organization<>p_organization AND b.type IS DISTINCT FROM 'CASH' AND NOT public.is_demo_occasion(o.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.payment_reference_scopes s WHERE s.organization_id=o.organization AND s.phase='active')) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_UNMIGRATED_SHARED_WRITER'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_info p JOIN eshop.bank_accounts b ON b.id=p.bank_account
 JOIN eshop.payment_reference_namespaces n ON n.id=ANY(namespaces) AND public.try_payment_reference_account_internal(b.account_number)=n.canonical_account
 WHERE p.amount>0 AND p.variable_symbol IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM eshop.payment_reference_reservations r WHERE r.namespace_id=n.id AND r.variable_symbol=p.variable_symbol AND r.original_payment_info_id=p.id)) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_HISTORY_NOT_IMPORTED'; END IF;
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true,manifest_sha256=p_manifest_sha256 WHERE id=ANY(namespaces);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES(p_organization,'active',p_manifest_sha256)
 ON CONFLICT(organization_id) DO UPDATE SET phase='active',manifest_sha256=excluded.manifest_sha256,updated_at=clock_timestamp();
END $$;
REVOKE ALL ON FUNCTION public.activate_payment_reference_scope(bigint,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_payment_reference_scope(bigint,text,boolean) TO service_role;


-- Source: database/functions/eshop_payment_references/replay.sql
-- Called only after the originating receipt's actor/hash checks. No new public
-- order-ID lookup or capability is introduced; the receipt itself stays immutable.
CREATE OR REPLACE FUNCTION public.project_local_payment_reference_order_internal(p_response jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=CASE WHEN p_response ? 'data' THEN p_response->'data' ELSE p_response END;
 target eshop.orders; payment eshop.payment_info; details jsonb;
BEGIN
 IF payload#>>'{order,id}' IS NULL THEN RETURN p_response; END IF;
 SELECT * INTO target FROM eshop.orders WHERE id=(payload#>>'{order,id}')::bigint;
 IF target.id IS NULL OR target.state='storno' THEN
  payload:=jsonb_set(payload,'{order,payment_info}','null')||jsonb_build_object('code',409,'errorCode','ORDER_NOT_PAYABLE');
 ELSE
  SELECT * INTO payment FROM eshop.payment_info WHERE id=target.payment_info;
  IF payment.id IS NOT NULL THEN
   details:=coalesce(payload#>'{order,payment_info}','{}')||jsonb_build_object('id',payment.id,'variable_symbol',payment.variable_symbol,
    'creditor_reference',payment.creditor_reference,'amount',payment.amount,'deposit_amount',payment.deposit_amount,
    'deadline',payment.deadline,'deposit_deadline',payment.deposit_deadline,'currency_code',payment.currency_code);
   payload:=jsonb_set(payload,'{order,payment_info}',details);
  END IF;
 END IF;
 IF p_response ? 'data' THEN RETURN jsonb_set(p_response,'{data}',payload); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.project_local_payment_reference_order_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop/generate_payment_variable_symbol.sql
CREATE OR REPLACE FUNCTION generate_payment_variable_symbol(p_bank_account_id BIGINT, p_form_id BIGINT)
RETURNS BIGINT
SET search_path = public, extensions AS $$
DECLARE
    -- Variables for form configuration
    v_form_data JSONB;
    v_vs_config JSONB;
    v_vs_type TEXT;
    v_starting_number BIGINT;
    v_max_symbol_for_form BIGINT;

    -- General variable for the symbol to be returned
    v_candidate_symbol BIGINT;

    -- Variables for the random generation fallback
    v_digit_count INT := 4;
    v_attempt_count INT := 0;
    v_max_attempts INT := 1;
    v_safety_counter INT := 0; -- Safety break for the sequential loop
BEGIN
    IF public.payment_reference_scope_enabled_internal(p_form_id) THEN
      RAISE EXCEPTION 'PAYMENT_REFERENCE_RESERVATION_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM eshop.payment_reference_namespaces n
      WHERE n.canonical_account=public.try_payment_reference_account_internal((SELECT account_number FROM eshop.bank_accounts WHERE id=p_bank_account_id))
      AND (n.allocation_enabled OR EXISTS(SELECT 1 FROM eshop.payment_reference_reservations r WHERE r.namespace_id=n.id))) THEN
      RAISE EXCEPTION 'PAYMENT_REFERENCE_SHARED_ACCOUNT_REQUIRES_ENROLLMENT'; END IF;
    -- 1. Fetch the configuration data for the given form
    SELECT data INTO v_form_data FROM public.forms WHERE id = p_form_id;

    -- Raise an error if the form does not exist
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Form with ID % not found.', p_form_id;
    END IF;

    -- 2. Check for custom variable symbol configuration within the JSONB data
    -- We use COALESCE to default to 'random' if the setting is missing, making the function robust.
    v_vs_config := v_form_data -> 'variable_symbol';
    v_vs_type := COALESCE(v_vs_config ->> 'type', 'random');

    -- 3. Main logic: Choose between 'sequence' and 'random' generation
    IF v_vs_type = 'sequence' THEN
        ----------------------------------------------------
        -- LOGIC FOR SEQUENTIAL VARIABLE SYMBOL GENERATION --
        ----------------------------------------------------

        -- Get the defined starting number from the form's configuration
        v_starting_number := (v_vs_config ->> 'starting_number')::BIGINT;
        IF v_starting_number IS NULL THEN
            RAISE EXCEPTION 'Form with ID % is configured for sequential variable symbols, but "starting_number" is missing in its data.', p_form_id;
        END IF;

        -- Find the highest existing variable symbol used for this specific form.
        -- We must join through the orders table to link payments to a form.
        SELECT MAX(pi.variable_symbol)
        INTO v_max_symbol_for_form
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON pi.id = o.payment_info
        WHERE o.form = p_form_id;

        -- Determine the first candidate for our new variable symbol.
        -- If no previous symbol exists for this form, use the starting number.
        -- Otherwise, take the highest existing symbol and add 1.
        -- The GREATEST function handles the edge case where the starting_number was increased after symbols were already generated.
        IF v_max_symbol_for_form IS NULL THEN
            v_candidate_symbol := v_starting_number;
        ELSE
            v_candidate_symbol := GREATEST(v_max_symbol_for_form + 1, v_starting_number);
        END IF;

        -- Loop to ensure the candidate symbol is unique for the target bank account.
        -- If the symbol is already taken, increment and check again.
        LOOP
            IF NOT EXISTS (
                SELECT 1
                FROM eshop.payment_info
                WHERE variable_symbol = v_candidate_symbol AND bank_account = p_bank_account_id
            ) THEN
                RETURN v_candidate_symbol; -- The symbol is unique, return it.
            END IF;

            -- The symbol was taken, so we increment and try the next one.
            v_candidate_symbol := v_candidate_symbol + 1;

            -- Add a safety break to prevent an infinite loop in unusual circumstances.
            v_safety_counter := v_safety_counter + 1;
            IF v_safety_counter > 1000 THEN
                RAISE EXCEPTION 'Could not find a unique sequential variable symbol for bank account % after 1000 attempts.', p_bank_account_id;
            END IF;
        END LOOP;

    ELSE
        ------------------------------------------------
        -- LOGIC FOR RANDOM VARIABLE SYMBOL GENERATION --
        ------------------------------------------------

        LOOP
            -- Generate a random number with the current digit count
            v_candidate_symbol := FLOOR(RANDOM() * (POWER(10, v_digit_count) - POWER(10, v_digit_count - 1))) + POWER(10, v_digit_count - 1);

            -- Ensure uniqueness within the bank_account
            IF NOT EXISTS (
                SELECT 1
                FROM eshop.payment_info
                WHERE variable_symbol = v_candidate_symbol AND bank_account = p_bank_account_id
            ) THEN
                RETURN v_candidate_symbol; -- Return the unique variable symbol
            END IF;

            -- Increment attempt count and adjust digit count after each failure
            v_attempt_count := v_attempt_count + 1;

            -- Extend digit count after reaching max attempts
            IF v_attempt_count >= v_max_attempts THEN
                v_digit_count := v_digit_count + 1;
                v_attempt_count := 0; -- Reset attempt count for the extended digit count
            END IF;

            -- Fail entirely if the system cannot generate a unique symbol after too many attempts
            IF v_digit_count > 10 THEN -- Arbitrary upper limit for digit count
                RAISE EXCEPTION 'Failed to generate a unique random variable symbol after too many attempts.';
            END IF;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.generate_payment_variable_symbol(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=order_id AND x.ticket=ticket_id) THEN
              INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,NULL);
            END IF;
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', v_ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        IF calculated_price>0 AND NOT public.payment_reference_scope_enabled_internal(form_id) THEN
          generated_variable_symbol := public.generate_payment_variable_symbol(bank_account_id, form_id);
        END IF;
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;
        IF calculated_price>0 AND public.payment_reference_scope_enabled_internal(form_id) THEN
          UPDATE eshop.orders SET payment_info=payment_info_id WHERE id=order_id;
          generated_variable_symbol:=public.reserve_order_payment_reference_internal(payment_info_id,form_id);
          UPDATE eshop.payment_info SET variable_symbol=generated_variable_symbol WHERE id=payment_info_id;
        END IF;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders(occasion_id,0);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop/confirm_blueprint_order_change.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(
  p_spot_ids BIGINT[],
  p_input_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_analysis JSONB;
  v_ticket_ids_to_cancel BIGINT[];
  v_occasion_id BIGINT;
  v_form_key UUID;
  v_ticket_payloads JSONB := '[]'::JSONB;
  v_order_details JSONB;
  v_new_spot_rec RECORD;
  v_email TEXT;
BEGIN
  -- Extract Email for validation
  v_email := p_input_data->>'email';

  IF v_email IS NULL OR v_email = '' THEN
      RAISE EXCEPTION 'Email is required in input data.';
  END IF;

  -- 1. Analyze impacts
  v_analysis := public.analyze_new_order_spots(p_spot_ids);

  -- 2. Extract Ticket IDs for Storno
  SELECT ARRAY_AGG((elem->>'ticket_id')::BIGINT)
  INTO v_ticket_ids_to_cancel
  FROM jsonb_array_elements(v_analysis->'conflicts') elem
  WHERE elem->>'ticket_id' IS NOT NULL;

  -- 3. Perform Storno (if any conflicts exist)
  IF v_ticket_ids_to_cancel IS NOT NULL AND array_length(v_ticket_ids_to_cancel, 1) > 0 THEN
      PERFORM public.storno_tickets_bulk_internal_v1(v_ticket_ids_to_cancel);
  END IF;

  -- 4. Clean up Secrets on selected spots
  UPDATE eshop.spots
  SET secret = NULL, secret_expiration_time = NULL
  WHERE id = ANY(p_spot_ids);

  -- 5. Prepare Data for New Order

  -- Get occasion ID
  SELECT occasion INTO v_occasion_id FROM eshop.spots WHERE id = p_spot_ids[1];

  -- Security Check: User must be editor
  IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
      RAISE EXCEPTION 'Permission denied. User is not an editor for occasion %', v_occasion_id;
  END IF;

  -- Validation: All spots must be on same occasion
  PERFORM 1 FROM eshop.spots
  WHERE id = ANY(p_spot_ids) AND occasion != v_occasion_id;

  IF FOUND THEN
      RAISE EXCEPTION 'All selected spots must belong to the same occasion.';
  END IF;

  -- Find a suitable Form
  SELECT key INTO v_form_key
  FROM public.forms
  WHERE occasion = v_occasion_id AND is_open = true
  ORDER BY type = 'ticket' DESC, id DESC
  LIMIT 1;

  IF v_form_key IS NULL THEN
      RAISE EXCEPTION 'No open form found for this occasion to create the new order.';
  END IF;

  -- Build "ticket" array for the payload
  FOR v_new_spot_rec IN
      SELECT s.id, s.product
      FROM eshop.spots s
      WHERE s.id = ANY(p_spot_ids)
  LOOP
      v_ticket_payloads := v_ticket_payloads || JSONB_BUILD_OBJECT(
          'spot', v_new_spot_rec.id,
          'fields', '[]'::JSONB
      );
  END LOOP;

  -- Construct payload for Edge Function
  -- We start with basic fields, then MERGE (||) the p_input_data
  -- This allows passing 'name', 'surname', 'note' in input_data automatically.
  v_order_details := JSONB_BUILD_OBJECT(
      'form', v_form_key,
      'ticket', v_ticket_payloads,
      'lang', 'cs'
  ) || p_input_data;

  -- Return Success + Payload
  RETURN JSONB_BUILD_OBJECT(
      'success', true,
      'message', 'Storno performed. Ready to create new order.',
      'orderDetails', v_order_details
  );

EXCEPTION WHEN OTHERS THEN
  RETURN JSONB_BUILD_OBJECT('success', false, 'message', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_orders/replace_blueprint_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before_users uuid[];
BEGIN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF public.payment_reference_scope_enabled_internal((SELECT id FROM public.forms WHERE occasion=v_occasion ORDER BY id LIMIT 1)) THEN
    RETURN jsonb_build_object('status','rejected','code',409,'data',jsonb_build_object('errorCode','ATOMIC_REPLACEMENT_REQUIRED')); END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.prepare_replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN public.project_local_payment_reference_order_internal(v_begin->'response'); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.confirm_blueprint_order_change_internal_v1(
    p_spot_ids,p_input_data);
  IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,v_result); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.prepare_replace',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',NULL,
      'operation','update','safeLabel','Blueprint order replacement',
      'changedFields',jsonb_build_array('cancellations','allocations'))),
    v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_blueprint_order_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_prepare jsonb; v_result jsonb; v_before_users uuid[];
BEGIN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN public.project_local_payment_reference_order_internal(v_begin->'response'); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  BEGIN
    v_prepare:=public.confirm_blueprint_order_change_internal_v1(
      p_spot_ids,p_input_data);
    IF COALESCE((v_prepare->>'success')::boolean,false) IS NOT TRUE THEN
      RAISE check_violation USING MESSAGE='replacement preparation rejected',
        DETAIL=v_prepare::text; END IF;
    v_result:=public.create_ticket_order_internal_v1(v_prepare->'orderDetails');
    IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
      RAISE check_violation USING MESSAGE='replacement order rejected',
        DETAIL=v_result::text; END IF;
  EXCEPTION WHEN check_violation THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,COALESCE(v_result,v_prepare,
        jsonb_build_object('message','order replacement rejected')));
  END;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,
    COALESCE(p_input_data->>'lang',v_prepare#>>'{orderDetails,lang}'));
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.replace',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Blueprint order replacement','changedFields',jsonb_build_array(
        'cancellations','tickets','products','allocations','membership'))),
    v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.replace_blueprint_order_client_sync_v1(
  bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_blueprint_order_client_sync_v1(
  bigint[],jsonb,uuid) TO authenticated;


-- Source: database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(
  p_order jsonb,p_command_id uuid,p_client_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'order',p_order)::text,'UTF8'),'sha256'),'hex');
  IF v_actor IS NULL THEN
    v_begin:=public.begin_anonymous_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,p_client_id,v_hash);
    v_actor_kind:='unknown';
  ELSE
    v_begin:=public.begin_client_mutation_v1(p_command_id,
      'inventory.order.create',v_occasion,v_actor,v_hash);
    v_actor_kind:='user';
  END IF;
  IF v_begin->>'disposition'='replay' THEN
    v_result := v_begin->'response';
    IF v_result#>'{data,order}' IS NOT NULL AND v_result#>>'{data,order,order_symbol}' IS NULL THEN
      v_symbol := public.read_order_identity((v_result#>>'{data,order,id}')::bigint,
        v_occasion, (SELECT organization FROM public.occasions WHERE id=v_occasion));
      IF v_symbol IS NOT NULL THEN
        v_result := jsonb_set(v_result, '{data,order,order_symbol}', to_jsonb(v_symbol));
      END IF;
    END IF;
    RETURN public.project_local_payment_reference_order_internal(v_result);
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1(p_order);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(
  jsonb,uuid,uuid) TO anon,authenticated;


-- Source: database/functions/eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash');
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_tickets_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)||jsonb_build_object('answers',p.data,'lifecycle',public.get_effective_waitlist_ticket_lifecycle_internal(p.id))) ORDER BY created_at,id),'[]')
 FROM public.get_order_tickets_internal(p_order) p;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_tickets_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected bigint[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; created_ticket bigint; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
 previous_sub text; actor_kind text; o eshop.orders; entity_changes jsonb:='[]';
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation NOT IN ('register','send','accept','decline','cancel','withdraw') OR p_command_id IS NULL OR p_client_id IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4194304 THEN RAISE EXCEPTION 'Invalid waitlist command'; END IF;
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSIF p_operation='withdraw' THEN oid:=(p_payload->>'orderId')::bigint; SELECT form INTO fid FROM eshop.orders WHERE id=oid;
 ELSE offer:=(p_payload->>'offerId')::uuid; SELECT order_id,form_id INTO oid,fid FROM eshop.waitlist_offers WHERE id=offer; END IF;
 SELECT * INTO f FROM public.forms WHERE id=fid; occ:=f.occasion;
 PERFORM public.check_occasion_writable(occ);
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_operation IN ('send','cancel') AND NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',p_payload,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN public.project_local_payment_reference_order_internal(claim->'response'); END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO before_users FROM public.occasion_users WHERE occasion=occ;
 BEGIN
  PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF p_operation IN ('accept','decline','cancel','withdraw') THEN
  PERFORM public.check_waitlist_scope_internal(oid,offer,p_payload->>'token',p_actor,p_operation); END IF;

  PERFORM public.expire_waitlist_form_internal(fid);
  c:=public.get_form_capacity_snapshot_internal(fid);
  IF p_operation='register' THEN
   mode:=public.get_form_registration_mode_internal(fid);
   IF mode<>'waitlist' THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   people:=public.normalize_form_ticket_answers_internal(fid,p_payload->'tickets');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'tickets'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.tickets(occasion,state,ticket_symbol,data,waitlist_queue_at)
     VALUES(occ,'waitlisted',NULL,public.extract_ticket_answers_internal(fid,person),clock_timestamp()) RETURNING id INTO created_ticket;
    INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(oid,created_ticket,NULL); END LOOP;
   result:=jsonb_build_object('code',200,'order',jsonb_build_object('id',oid,'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'state','waitlisted','payment_info',NULL,'price',NULL),
    'waitlistSummary',public.get_waitlist_summary_internal(oid),'email',public.enqueue_waitlist_email_internal(oid,NULL,p_command_id,p_deliveries->0));
  ELSIF p_operation='send' THEN
   SELECT * INTO f FROM public.forms WHERE id=fid;
   IF NOT f.waitlist_enabled THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   IF f.capacity_revision<>(p_payload->>'revision')::bigint THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','OFFER_CHANGED','capacity',c)::text; END IF;
   expiry:=(p_payload->>'expiresAt')::timestamptz;
   IF expiry IS NULL OR expiry<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
   recipients:=p_payload->'recipients';
   IF jsonb_typeof(recipients)<>'array' OR jsonb_array_length(recipients)<1 OR
    jsonb_array_length(recipients)<>(SELECT count(DISTINCT x->>'orderId') FROM jsonb_array_elements(recipients) x) THEN RAISE EXCEPTION 'Invalid recipients'; END IF;
   SELECT sum((x->>'count')::integer) INTO n FROM jsonb_array_elements(recipients) x;
   IF n>(c->>'offerablePlaces')::integer THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
   PERFORM 1 FROM eshop.orders WHERE id IN(SELECT (x->>'orderId')::bigint FROM jsonb_array_elements(recipients) x) ORDER BY id FOR UPDATE;
   result:=jsonb_build_object('code',200,'offers','[]'::jsonb);
   FOR r IN SELECT * FROM jsonb_array_elements(recipients) ORDER BY (value->>'orderId')::bigint LOOP
    oid:=(r->>'orderId')::bigint; n:=(r->>'count')::integer;
    IF n<1 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=fid AND state='waitlisted') THEN RAISE EXCEPTION 'Invalid recipient scope'; END IF;
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.tickets p WHERE p.state='waitlisted'
     AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=p.id AND x."order"=oid)
     AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE ticket_id=p.id AND outcome='pending')
     ORDER BY waitlist_queue_at,created_at,id LIMIT n FOR UPDATE) tickets;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,ticket_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
    SELECT x INTO delivery FROM jsonb_array_elements(p_deliveries) x WHERE (x->>'orderId')::bigint=oid;
    result:=jsonb_set(result,'{offers}',result->'offers'||jsonb_build_array(jsonb_build_object('orderId',oid,'offerId',offer,'count',n,'expiresAt',expiry,
     'email',public.enqueue_waitlist_email_internal(oid,offer,p_command_id,delivery))));
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,'waitlisted',jsonb_build_object('action','offer_sent','offerId',offer,'count',n,'expiresAt',expiry));
    entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist offer','changedFields',jsonb_build_array('waitlistSummary')));
   END LOOP;
  ELSIF p_operation='accept' THEN
   result:=public.accept_waitlist_offer_internal(p_payload,p_command_id,p_actor);
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','update','safeLabel','Accepted order','changedFields',jsonb_build_array('state','tickets','products','allocations')));
  ELSE
   PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
   IF (SELECT state FROM eshop.orders WHERE id=oid)<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   SELECT array_agg(x::bigint) INTO selected FROM jsonb_array_elements_text(p_payload->'ticketIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE id=ANY(selected) AND state='waitlisted') THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND ticket_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE ticket_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.tickets SET state=CASE WHEN p_operation='withdraw' THEN 'storno' ELSE state END,
    waitlist_queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
   UPDATE eshop.waitlist_capabilities cap SET revoked_at=clock_timestamp() WHERE cap.order_id=oid AND kind='offer' AND NOT EXISTS
    (SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=cap.offer_id AND outcome='pending');
   result:=jsonb_build_object('code',200,'orderId',oid,'waitlistSummary',public.get_waitlist_summary_internal(oid));
  END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=fid;
  IF p_operation<>'send' THEN
   -- Acceptance owns its richer before/after snapshot at the same transaction
   -- boundary; avoid a second action-only row hiding that record in the detail.
   IF p_operation<>'accept' THEN
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,(SELECT state FROM eshop.orders WHERE id=oid),
     jsonb_build_object('action','waitlist_'||p_operation,'commandId',p_command_id,
     'ticketIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY created_at,id) FROM public.get_order_tickets_internal(oid))
       ELSE to_jsonb(selected) END,
     'tickets',public.snapshot_waitlist_tickets_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','tickets')));
  END IF;
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;


-- Source: database/functions/eshop_payment_references/legacy_boundaries.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF public.payment_reference_scope_enabled_internal((SELECT id FROM public.forms WHERE key=(input_data->>'form')::uuid)) THEN
    RETURN jsonb_build_object('code',409,'errorCode','COMMAND_IDENTITY_REQUIRED'); END IF;
  RETURN public.create_ticket_order_client_sync_v1(input_data,
    extensions.gen_random_uuid(),COALESCE(auth.uid(),extensions.gen_random_uuid()))->'data';
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order(jsonb) TO anon,authenticated;


CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change(
  p_spot_ids bigint[],p_input_data jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  RETURN public.confirm_blueprint_order_change_client_sync_v1(
    p_spot_ids,p_input_data,extensions.gen_random_uuid())->'data';
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change(bigint[],jsonb)
  TO authenticated;


-- Source: database/functions/eshop/update_payment_info_variable_symbol.sql
-- Raw mutation is retired. There is no post-publication renumbering UI/contract.
CREATE OR REPLACE FUNCTION public.update_payment_info_variable_symbol(p_payment_info_id bigint,p_variable_symbol bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RAISE EXCEPTION 'PAYMENT_REFERENCE_COMMAND_REQUIRED';
END $$;
REVOKE ALL ON FUNCTION public.update_payment_info_variable_symbol(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


-- Source: database/functions/eshop_payment_references/manual.sql
CREATE OR REPLACE FUNCTION public.reserve_draft_payment_reference(p_payment_info_id bigint,p_variable_symbol bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target eshop.orders; pi eshop.payment_info; claim jsonb; result jsonb; policy jsonb; symbol bigint; users uuid[];
BEGIN
 IF auth.uid() IS NULL OR p_command_id IS NULL OR p_variable_symbol IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
  RAISE insufficient_privilege USING MESSAGE='Invalid payment reference command'; END IF;
 SELECT * INTO STRICT target FROM eshop.orders WHERE payment_info=p_payment_info_id;
 PERFORM public.check_is_editor_order_on_occasion(target.occasion);
 PERFORM public.check_occasion_writable(target.occasion);
 claim:=public.begin_client_mutation_v1(p_command_id,'inventory.payment.reference',target.occasion,auth.uid(),
  encode(extensions.digest(jsonb_build_object('payment',p_payment_info_id,'symbol',p_variable_symbol)::text,'sha256'),'hex'));
 IF claim->>'disposition'='replay' THEN RETURN claim->'response'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[target.id]);
 SELECT * INTO STRICT target FROM eshop.orders WHERE id=target.id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=p_payment_info_id FOR UPDATE;
 IF target.state<>'created' OR pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL
 OR EXISTS(SELECT 1 FROM eshop.transactions WHERE payment_info=pi.id)
 OR EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=target.id) THEN
  RAISE EXCEPTION 'PUBLISHED_PAYMENT_REFERENCE_IMMUTABLE'; END IF;
 policy:=jsonb_build_object('mode','exact','value',p_variable_symbol::text);
 symbol:=public.reserve_payment_reference_internal(pi.id,target.form,'manual:'||p_command_id,policy,
  encode(extensions.digest(jsonb_build_object('payment',pi.id,'symbol',p_variable_symbol)::text,'sha256'),'hex'));
 UPDATE eshop.payment_info SET variable_symbol=symbol,
 creditor_reference=CASE WHEN upper(trim(currency_code))='EUR' THEN public.generate_creditor_reference(symbol) ELSE NULL END WHERE id=pi.id;
 SELECT coalesce(array_agg(ou."user"),'{}') INTO users FROM public.occasion_users ou WHERE ou.occasion=target.occasion;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,target.occasion,'inventory.payment.reference',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',target.id,'operation','update','safeLabel','Payment reference',
  'changedFields',jsonb_build_array('payment_info'))),users,jsonb_build_object('code',200,'variable_symbol',symbol));
END $$;
REVOKE ALL ON FUNCTION public.reserve_draft_payment_reference(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reserve_draft_payment_reference(bigint,bigint,uuid) TO authenticated;


-- Source: database/functions/eshop_bank_accounts/update_bank_account.sql
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[]);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint,text);

CREATE OR REPLACE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL,
    p_creditor_name text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
    v_operation_id uuid;
    v_request jsonb;
BEGIN
    PERFORM public.check_bank_account_writable(p_id);
    -- Prevent manual manipulation of CASH accounts
    IF p_type = 'CASH' THEN
        RAISE EXCEPTION 'CASH_ACCOUNT_MANUAL_UPDATE_FORBIDDEN';
    END IF;

    IF char_length(p_title)>120 THEN RAISE EXCEPTION 'BANK_ACCOUNT_TITLE_TOO_LONG'; END IF;

    -- Input normalization
    v_account_number := TRIM(p_account_number);

    IF p_id IS NULL THEN
        -- Creation: If p_unit_id is provided, enforce that creator is Manager of that unit
        IF p_unit_id IS NOT NULL THEN
             PERFORM check_is_manager_on_unit(p_unit_id);
        END IF;

        -- Check for duplicate account number on insert
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable, creditor_name)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable, nullif(trim(p_creditor_name), ''))
        RETURNING id INTO v_id;

        -- Automatically make the creator an Admin
        INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
        VALUES (v_id, auth.uid(), true);

        -- Automatically link to unit if provided
        IF p_unit_id IS NOT NULL THEN
             INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
             VALUES (p_unit_id, v_id, 0);
        END IF;
    ELSE
        -- Check for duplicate account number on update (exclude current id)
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number AND id != p_id) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        -- Security Check: Caller must be an Admin of the bank account
        IF NOT EXISTS (
            SELECT 1 FROM eshop.bank_account_users
            WHERE bank_account = p_id AND "user" = auth.uid() AND is_admin = true
        ) THEN
            RAISE EXCEPTION 'Permission denied: Only bank account admins can update details.';
        END IF;

        PERFORM 1 FROM eshop.bank_accounts WHERE id=p_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=p_id)
          AND EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE id=p_id
            AND (account_number IS DISTINCT FROM v_account_number OR type IS DISTINCT FROM p_type)) THEN
          RAISE EXCEPTION 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE';
        END IF;
        IF EXISTS(SELECT 1 FROM eshop.payment_reference_accounts a JOIN eshop.payment_reference_namespaces n ON n.id=a.namespace_id
          WHERE a.bank_account_id=p_id AND (n.canonical_account IS DISTINCT FROM public.canonical_payment_reference_account_internal(v_account_number)
           OR p_type='CASH')) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            creditor_name = nullif(trim(p_creditor_name), ''),
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    -- Local details and the durable remote update intent commit together.
    IF p_id IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=v_id) THEN
      v_operation_id := gen_random_uuid();
      v_request := jsonb_build_object('operation','update_details','operation_id',v_operation_id,'account_id',v_id);
      INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state,request)
        VALUES(v_operation_id,v_id,auth.uid(),'update_details',encode(extensions.digest(v_request::text,'sha256'),'hex'),'pending',v_request);
    END IF;
    RETURN v_id;
END;
$$;


-- Source: database/functions/emails/fakturoid_email_gate.sql
-- A Fakturoid checkout is not an accepted order until its proforma exists.
-- Keep its confirmation out of the email worker until checkout finalizes it.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  PERFORM public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'command_id',p_command_id,'ticket_order',p_order_payload,'lang',coalesce(nullif(p_language,''),'cs'),
    'fakturoid_pending',v_await_fakturoid),v_organization,p_occasion,v_unit,
    CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END);

END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_fakturoid_ticket_order_state_v1(p_order_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state INTO v_state FROM eshop.orders o WHERE o.id=p_order_id;
  IF v_state IS NULL THEN
    RAISE no_data_found USING MESSAGE='ticket order not found';
  END IF;
  RETURN v_state;
END;
$$;
REVOKE ALL ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid, p_variable_symbol bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_currency text;
  v_payment_id bigint;
  v_existing_vs bigint;
  v_occasion bigint;
  v_queue_id bigint;
  v_impacts jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='aborted') THEN
    RAISE EXCEPTION 'Acceptance attempt aborted'; END IF;
  SELECT o.state,trim(o.currency_code),o.payment_info,o.occasion,pi.variable_symbol
  INTO v_state,v_currency,v_payment_id,v_occasion,v_existing_vs
  FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
  WHERE o.id=p_order_id FOR UPDATE OF o,pi;
  IF v_state IS NULL OR p_command_id IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid Fakturoid completion';
  END IF;
  IF v_state IN ('ordered','paid') THEN
    RETURN v_existing_vs;
  END IF;
  IF v_state<>'preparing_payment' THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  IF v_currency NOT IN ('CZK','EUR') OR v_existing_vs IS DISTINCT FROM p_variable_symbol THEN
    RAISE check_violation USING MESSAGE='Fakturoid symbol differs from application payment reference';
  END IF;
  UPDATE eshop.waitlist_acceptance_attempts SET state='completed',updated_at=clock_timestamp()
   WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='preparing';
  UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
  UPDATE public.email_messages SET target_time=now(),workflow_state='pending',
    data=jsonb_set(data-'fakturoid_pending','{ticket_order,order,payment_info,variable_symbol}',to_jsonb(p_variable_symbol))
  WHERE id=v_queue_id;
  PERFORM public.wake_email_worker();
  SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
  FROM public.occasion_users ou CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component
  WHERE ou.occasion=v_occasion;
  PERFORM public.record_client_sync_commit_v1(v_occasion,
    'fakturoid.order.complete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order_id,'operation','update',
      'safeLabel','Order payment ready','changedFields',
      jsonb_build_array('state','payment_info'))),'{}',v_impacts,'[]',
    'service',NULL);
  RETURN p_variable_symbol;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_occasion bigint;
  v_queue_id bigint;
  v_before_users uuid[];
  v_abort_command uuid := extensions.gen_random_uuid();
  v_hash text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command_id AND target_order_id=p_order_id AND state='aborted') THEN RETURN; END IF;
  SELECT o.state,o.occasion INTO v_state,v_occasion
  FROM eshop.orders o WHERE o.id=p_order_id FOR UPDATE;
  IF v_state='storno' THEN RETURN; END IF;
  IF v_state IS DISTINCT FROM 'preparing_payment' OR p_command_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
  FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order_id,'reason','fakturoid_failed')::text,'UTF8'),'sha256'),'hex');
  PERFORM public.begin_anonymous_client_mutation_v1(v_abort_command,
    'inventory.order.fakturoid_abort',v_occasion,extensions.gen_random_uuid(),v_hash);
  UPDATE public.email_messages SET workflow_state='cancelled',last_error='fakturoid_aborted' WHERE id=v_queue_id;
  IF NOT public.abort_waitlist_acceptance_internal(p_order_id,p_command_id) THEN
    UPDATE eshop.orders SET state='ordered' WHERE id=p_order_id;
    PERFORM public.update_order_and_tickets_to_storno_221(p_order_id);
  END IF;
  PERFORM public.complete_profile_inventory_membership_mutation_v1(
    v_abort_command,v_occasion,'inventory.order.fakturoid_abort',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',p_order_id,'operation','update','safeLabel','Failed order',
      'changedFields',jsonb_build_array('state','tickets','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order_id),'service');
END;
$$;
REVOKE ALL ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  TO service_role;


-- Direct payment writes cannot publish an unreserved symbol. Domain RPC owners
-- keep their internal access. Legacy helper exports are not a second API.
REVOKE INSERT,UPDATE,DELETE ON eshop.payment_info FROM anon,authenticated;
REVOKE UPDATE(variable_symbol,creditor_reference,bank_account) ON eshop.payment_info FROM anon,authenticated;
REVOKE INSERT,UPDATE ON eshop.bank_accounts FROM anon,authenticated;
REVOKE UPDATE(account_number,type) ON eshop.bank_accounts FROM anon,authenticated;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='generate_variable_symbol' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $$;
