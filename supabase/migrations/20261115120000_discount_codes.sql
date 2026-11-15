-- Discount codes: additive schema, canonical SQL price allocation, atomic order consumption. Feature defaults off.

-- SOURCE: eshop_discounts/schema.sql
-- Additive only. Historical amounts come from sold JSON, never today's catalogue.
CREATE TABLE IF NOT EXISTS eshop.discount_codes (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 occasion bigint NOT NULL, -- retained scope identity, including after occasion deletion
 normalized_code text NOT NULL CHECK (normalized_code COLLATE "C" ~ '^[A-Z0-9-]{4,32}$'),
 kind text NOT NULL CHECK(kind IN ('percent','fixed')),
 value numeric NOT NULL CHECK(value>0 AND value::text NOT IN ('NaN','Infinity','-Infinity')),
 currency_code text,
 form_ids bigint[] NOT NULL DEFAULT '{}', product_ids bigint[] NOT NULL DEFAULT '{}',
 valid_from timestamptz, valid_until timestamptz,
 usage_limit bigint CHECK(usage_limit>0), is_active boolean NOT NULL DEFAULT false,
 revision bigint NOT NULL DEFAULT 1,
 created_by uuid NOT NULL, updated_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(occasion,normalized_code),
 CHECK(valid_until IS NULL OR valid_from IS NULL OR valid_until>valid_from),
 CHECK((kind='percent' AND value=trunc(value) AND value<=10000 AND currency_code IS NULL)
 OR (kind='fixed' AND currency_code ~ '^[A-Z]{3}$'))
);
-- No cascading FK to orders/items/products: the receipt survives deletion/storno.
CREATE TABLE IF NOT EXISTS eshop.order_discounts (
 order_id bigint PRIMARY KEY, code_id bigint NOT NULL REFERENCES eshop.discount_codes(id),
 command_id uuid NOT NULL UNIQUE, snapshot jsonb NOT NULL,
 base_amount numeric(10,2) NOT NULL, discount_amount numeric(10,2) NOT NULL,
 net_amount numeric(10,2) NOT NULL, currency_code text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(base_amount>=discount_amount AND discount_amount>0 AND net_amount=base_amount-discount_amount)
);
CREATE INDEX IF NOT EXISTS order_discounts_code_idx ON eshop.order_discounts(code_id);
CREATE TABLE IF NOT EXISTS eshop.discount_code_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, code_id bigint NOT NULL REFERENCES eshop.discount_codes(id),
 actor uuid NOT NULL, revision bigint NOT NULL, definition jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(code_id,revision)
);
ALTER TABLE eshop.discount_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.order_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.discount_code_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.discount_codes,eshop.order_discounts,eshop.discount_code_audit FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE eshop.discount_codes_id_seq,eshop.discount_code_audit_id_seq FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS base_price numeric(10,2);
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS discount_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS net_price numeric(10,2);
UPDATE eshop.order_product_ticket x SET base_price=(p->>'price')::numeric,net_price=(p->>'price')::numeric
 FROM eshop.orders o CROSS JOIN LATERAL jsonb_array_elements(coalesce(o.data->'tickets','[]')) t
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
 WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint AND x.base_price IS NULL;
COMMENT ON COLUMN eshop.order_product_ticket.net_price IS 'Sold net price; orders.data.tickets.products.price has the same net meaning. Unknown historical prices remain NULL.';
-- Reuse central bounded abuse accounting, including unsuccessful lookups.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
 VALUES('discount.quote.form.minute','discount.quote','recipient','rolling',60,60,120,120),
 ('discount.quote.organization.minute','discount.quote','organization','rolling',60,60,1000,1000)
 ON CONFLICT(rule_key) DO NOTHING;

-- SOURCE: abuse/policy.sql
-- One statement snapshot per domain admission. Scoped overrides cannot alter an actor rule.
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'barion.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'discount.quote' THEN 2 WHEN 'order.mutation' THEN 4 WHEN 'batch-create' THEN 1 WHEN 'batch-document' THEN 2
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.notification' THEN 3 WHEN 'email.notification.backlog' THEN 4 WHEN 'email.notification.prepare' THEN 2 WHEN 'email.send.notification' THEN 3
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- All families in one admission phase share a PostgreSQL STABLE statement
-- snapshot, including overrides and revision; no config lock or HTTP hop.
CREATE OR REPLACE FUNCTION public.abuse_policy_bundle_v1(p_budgets text[],p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_object_agg(b,public.abuse_effective_rules_v1(b,p_unit,p_org)) FROM unnest(p_budgets) b;
$$;
REVOKE ALL ON FUNCTION public.abuse_policy_bundle_v1(text[],bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only numeric limits may be changed here. Algorithm/window/identity changes need a migration.
-- A batch is one audited optimistic revision; no writes to usage.
CREATE OR REPLACE FUNCTION public.set_abuse_policy_v1(p_expected_revision bigint,p_reason text,p_changes jsonb)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_revision bigint; c jsonb; r public.abuse_policy_rules; v_old jsonb; v_author text;
BEGIN
 PERFORM public.require_service_role();
 IF length(btrim(p_reason)) NOT BETWEEN 8 AND 1000 OR p_reason IS NULL OR jsonb_typeof(p_changes) IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_changes) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy batch'; END IF;
 SELECT revision INTO v_revision FROM public.abuse_policy_revision FOR UPDATE;
 IF p_expected_revision IS DISTINCT FROM v_revision THEN RAISE serialization_failure USING MESSAGE='abuse policy revision conflict'; END IF;
 v_author:=coalesce(auth.uid()::text,session_user::text);
 SELECT jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
 'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x)) INTO v_old;
 FOR c IN SELECT value FROM jsonb_array_elements(p_changes) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(c) k WHERE k NOT IN ('rule_key','base_limit','target_kind','target_id','expires_at')) THEN
   RAISE invalid_parameter_value USING MESSAGE='unsupported abuse policy parameter'; END IF;
  SELECT * INTO r FROM public.abuse_policy_rules WHERE rule_key=c->>'rule_key';
  IF NOT FOUND OR (c->>'base_limit')::bigint IS NULL OR (c->>'base_limit')::bigint NOT BETWEEN 1 AND r.hard_cap THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid abuse policy limit'; END IF;
  IF c ? 'target_kind' THEN
   IF (c->>'target_kind'='unit' AND r.scope_kind<>'unit') OR
    (c->>'target_kind'='organization' AND r.scope_kind NOT IN ('unit','organization')) OR
    c->>'target_kind' NOT IN ('unit','organization') OR (c->>'target_id')::bigint IS NULL OR
    (c->>'expires_at')::timestamptz IS NULL OR (c->>'expires_at')::timestamptz<=statement_timestamp() OR
    (c->>'expires_at')::timestamptz>statement_timestamp()+interval '90 days' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid abuse override scope or expiry'; END IF;
   IF NOT (CASE WHEN c->>'target_kind'='unit' THEN EXISTS(SELECT 1 FROM public.units WHERE id=(c->>'target_id')::bigint)
    ELSE EXISTS(SELECT 1 FROM public.organizations WHERE id=(c->>'target_id')::bigint) END) THEN
    RAISE invalid_parameter_value USING MESSAGE='unknown abuse override target'; END IF;
   INSERT INTO public.abuse_policy_overrides VALUES(r.rule_key,c->>'target_kind',(c->>'target_id')::bigint,
    (c->>'base_limit')::bigint,(c->>'expires_at')::timestamptz,p_reason,v_author)
   ON CONFLICT(rule_key,target_kind,target_id) DO UPDATE SET base_limit=excluded.base_limit,expires_at=excluded.expires_at,reason=excluded.reason,author=excluded.author;
  ELSE
   IF c ? 'target_id' OR c ? 'expires_at' THEN RAISE invalid_parameter_value USING MESSAGE='override target required'; END IF;
   UPDATE public.abuse_policy_rules SET base_limit=(c->>'base_limit')::bigint WHERE rule_key=r.rule_key;
  END IF;
 END LOOP;
 UPDATE public.abuse_policy_revision SET revision=revision+1 RETURNING revision INTO v_revision;
 INSERT INTO public.abuse_policy_audit SELECT v_revision,clock_timestamp(),v_author,p_reason,v_old,
  jsonb_build_object('rules',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_rules x),
   'overrides',(SELECT jsonb_agg(to_jsonb(x)) FROM public.abuse_policy_overrides x));
 RETURN v_revision;
END $$;
REVOKE ALL ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.set_abuse_policy_v1(bigint,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.abuse_effective_rules_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_abuse_policy_v1(p_unit bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_read_unit_abuse_policy(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT organization INTO v_org FROM public.units WHERE id=p_unit;
 RETURN jsonb_build_object('creation',public.abuse_effective_rules_v1('occasion.creation',p_unit,v_org),
 'draft',public.abuse_effective_rules_v1('occasion.draft',p_unit,v_org),
 'usage',coalesce((SELECT jsonb_agg(jsonb_build_object('rule',u.rule_key,'amount',u.amount,'bucketAt',u.bucket_at,'expiresAt',u.expires_at))
 FROM public.abuse_budget_usage u JOIN public.abuse_policy_rules r USING(rule_key)
 WHERE u.expires_at>statement_timestamp() AND ((r.scope_kind='unit' AND u.scope_id=p_unit::text)
 OR (r.scope_kind='actor' AND u.scope_id=auth.uid()::text))),'[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.get_unit_abuse_policy_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_abuse_policy_v1(bigint) TO authenticated;

-- SOURCE: user_permissions/discount_operations.sql
CREATE OR REPLACE FUNCTION public.can_manage_discount_codes(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_write_orders(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_manage_discount_codes(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_discount_codes(bigint) TO authenticated,service_role;

-- SOURCE: eshop_discounts/calculation.sql
-- Pure decimal owner. The input order is the normalized ticket/product order.
CREATE OR REPLACE FUNCTION public.calculate_order_discount_internal(p_lines jsonb,p_kind text,p_value numeric,p_digits integer)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE eligible numeric; target numeric; scale numeric:=power(10,p_digits); result jsonb;
BEGIN
 IF p_digits NOT BETWEEN 0 AND 2 OR p_kind NOT IN ('percent','fixed') OR p_value IS NULL OR p_value<=0
  OR p_value::text IN ('NaN','Infinity','-Infinity') OR (p_kind='percent' AND (p_value>10000 OR p_value<>trunc(p_value)))
  OR (p_kind='fixed' AND p_value<>round(p_value,p_digits)) OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array'
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_lines) l WHERE l->>'base' IS NULL OR (l->>'base')::numeric::text IN ('NaN','Infinity','-Infinity') OR (l->>'base')::numeric<0
   OR (l->>'base')::numeric<>round((l->>'base')::numeric,p_digits)) THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 SELECT coalesce(sum((l->>'base')::numeric) FILTER(WHERE l->'eligible'='true'::jsonb),0) INTO eligible FROM jsonb_array_elements(p_lines) l;
 IF eligible<=0 THEN RAISE EXCEPTION 'DISCOUNT_PRODUCT_SCOPE'; END IF;
 target:=least(eligible,CASE WHEN p_kind='percent' THEN round(eligible*p_value/10000,p_digits) ELSE p_value END)*scale;
 IF target<=0 THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 WITH source AS (SELECT l,n,(l->>'base')::numeric base,CASE WHEN l->'eligible'='true'::jsonb THEN (l->>'base')::numeric*target/eligible ELSE 0 END exact
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY s(l,n)),
 ranked AS (SELECT *,floor(exact) units,row_number() OVER(ORDER BY exact-floor(exact) DESC,n) rank,
  target-sum(floor(exact)) OVER() remaining FROM source),
 allocated AS (SELECT *, (units+CASE WHEN rank<=remaining THEN 1 ELSE 0 END)/scale discount FROM ranked)
 SELECT jsonb_build_object('base',sum(base),'discount',sum(discount),'net',sum(base-discount),'lines',
  jsonb_agg(l||jsonb_build_object('discount',discount,'net',base-discount) ORDER BY n)) INTO result FROM allocated;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'lines') l WHERE (l->>'deposit')::numeric>0 AND (l->>'net')::numeric<=(l->>'deposit')::numeric) THEN
  RAISE EXCEPTION 'DISCOUNT_DEPOSIT_CONFLICT'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.calculate_order_discount_internal(jsonb,text,numeric,integer) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_discounts/management.sql
CREATE OR REPLACE FUNCTION public.save_discount_code(p_occasion bigint,p_definition jsonb,p_id bigint DEFAULT NULL,p_expected_revision bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.discount_codes; old eshop.discount_codes; forms bigint[]; products bigint[]; code text;
BEGIN
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_definition IS NULL OR jsonb_typeof(p_definition)<>'object' OR octet_length(p_definition::text)>16384 THEN RAISE invalid_parameter_value; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 PERFORM public.check_occasion_writable(p_occasion);
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 IF coalesce(btrim(p_definition->>'code'),'') COLLATE "C" !~ '^[A-Za-z0-9-]{4,32}$' THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 code:=upper(btrim(p_definition->>'code') COLLATE "C");
 SELECT coalesce(array_agg(DISTINCT value::bigint ORDER BY value::bigint),'{}') INTO forms FROM jsonb_array_elements_text(coalesce(p_definition->'formIds','[]'));
 SELECT coalesce(array_agg(DISTINCT value::bigint ORDER BY value::bigint),'{}') INTO products FROM jsonb_array_elements_text(coalesce(p_definition->'productIds','[]'));
 IF EXISTS(SELECT 1 FROM unnest(forms) id WHERE NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=id AND f.occasion=p_occasion))
 OR EXISTS(SELECT 1 FROM unnest(products) id WHERE NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.id=id AND p.occasion=p_occasion)) THEN RAISE EXCEPTION 'DISCOUNT_SCOPE_INVALID'; END IF;
 IF p_id IS NOT NULL THEN
  SELECT * INTO old FROM eshop.discount_codes WHERE id=p_id AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE insufficient_privilege; END IF;
  IF old.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'DISCOUNT_REVISION_CONFLICT'; END IF;
  IF code IS DISTINCT FROM old.normalized_code AND EXISTS(SELECT 1 FROM eshop.order_discounts WHERE code_id=p_id) THEN RAISE EXCEPTION 'DISCOUNT_IDENTITY_IMMUTABLE'; END IF;
 END IF;
 c.occasion:=p_occasion; c.normalized_code:=code; c.kind:=p_definition->>'kind'; c.value:=(p_definition->>'value')::numeric;
 c.currency_code:=CASE WHEN c.kind='fixed' THEN upper(p_definition->>'currency') END;
 IF c.kind='fixed' THEN PERFORM public.validate_product_price(c.value,'{}',c.currency_code); END IF;
 c.form_ids:=forms; c.product_ids:=products; c.valid_from:=nullif(p_definition->>'validFrom','')::timestamptz;
 c.valid_until:=nullif(p_definition->>'validUntil','')::timestamptz; c.usage_limit:=(p_definition->>'usageLimit')::bigint;
 c.is_active:=coalesce((p_definition->>'isActive')::boolean,false);
 IF p_id IS NULL THEN
  INSERT INTO eshop.discount_codes(occasion,normalized_code,kind,value,currency_code,form_ids,product_ids,valid_from,valid_until,usage_limit,is_active,created_by,updated_by)
   VALUES(c.occasion,c.normalized_code,c.kind,c.value,c.currency_code,c.form_ids,c.product_ids,c.valid_from,c.valid_until,c.usage_limit,c.is_active,auth.uid(),auth.uid()) RETURNING * INTO c;
 ELSE
  UPDATE eshop.discount_codes SET normalized_code=c.normalized_code,kind=c.kind,value=c.value,currency_code=c.currency_code,
   form_ids=c.form_ids,product_ids=c.product_ids,valid_from=c.valid_from,valid_until=c.valid_until,usage_limit=c.usage_limit,is_active=c.is_active,
   revision=old.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=p_id RETURNING * INTO c;
 END IF;
 INSERT INTO eshop.discount_code_audit(code_id,actor,revision,definition) VALUES(c.id,auth.uid(),c.revision,to_jsonb(c));
 RETURN to_jsonb(c);
END $$;
CREATE OR REPLACE FUNCTION public.list_discount_codes(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('uses',CASE WHEN public.can_read_orders(p_occasion) THEN
  (SELECT count(*) FROM eshop.order_discounts d WHERE d.code_id=c.id) END,'discountTotals',CASE WHEN public.can_read_orders(p_occasion) THEN
  (SELECT coalesce(jsonb_object_agg(currency_code,amount),'{}') FROM (SELECT currency_code,sum(discount_amount) amount FROM eshop.order_discounts d WHERE d.code_id=c.id GROUP BY currency_code) totals) END) ORDER BY c.id),'[]') FROM eshop.discount_codes c WHERE c.occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.save_discount_code(bigint,jsonb,bigint,bigint),public.list_discount_codes(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.save_discount_code(bigint,jsonb,bigint,bigint),public.list_discount_codes(bigint) TO authenticated;

-- SOURCE: eshop_discounts/quote.sql
-- Private quote and commit share scope, prices, normalization and allocation.
-- The existing occasion blueprint fence also fences every feature writer.
CREATE OR REPLACE FUNCTION public.order_discount_quote_internal(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c eshop.discount_codes; lines jsonb; result jsonb; currency text; digits integer; policy jsonb;
BEGIN
 IF p_input IS NULL OR octet_length(p_input::text)>1048576 OR jsonb_typeof(p_input->'ticket') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_input->'ticket') NOT BETWEEN 1 AND public.ticket_order_limit()
  OR coalesce(length(p_input#>>'{discount,code}'),0) NOT BETWEEN 4 AND 64
  OR coalesce(btrim(p_input#>>'{discount,code}'),'') COLLATE "C" !~ '^[A-Za-z0-9-]{4,32}$' THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 SELECT * INTO f FROM public.forms WHERE key=(p_input->>'form')::uuid;
 IF f.id IS NULL THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 p_input:=jsonb_set(p_input,'{ticket}',public.normalize_form_ticket_answers_internal(f.id,p_input->'ticket'));
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 PERFORM public.payment_policy_fence_internal((SELECT organization FROM public.occasions WHERE id=f.occasion));
 SELECT jsonb_build_object('features',o.features,'updatedAt',o.updated_at,'aggregateVersion',(SELECT version FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text)) INTO policy FROM public.occasions o WHERE id=f.occasion;
 IF NOT coalesce(jsonb_path_exists(policy->'features','$[*] ? (@.code == "discount_codes" && @.is_enabled == true)'),false) THEN RAISE EXCEPTION 'DISCOUNT_FEATURE_OFF'; END IF;
 SELECT * INTO c FROM eshop.discount_codes WHERE occasion=f.occasion AND normalized_code=upper(btrim(p_input#>>'{discount,code}') COLLATE "C") FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 IF NOT c.is_active THEN RAISE EXCEPTION 'DISCOUNT_INACTIVE'; END IF;
 IF (c.valid_from IS NOT NULL AND clock_timestamp()<c.valid_from) OR (c.valid_until IS NOT NULL AND clock_timestamp()>=c.valid_until) THEN RAISE EXCEPTION 'DISCOUNT_OUTSIDE_VALIDITY'; END IF;
 IF cardinality(c.form_ids)>0 AND NOT f.id=ANY(c.form_ids) THEN RAISE EXCEPTION 'DISCOUNT_FORM_SCOPE'; END IF;
 IF c.usage_limit IS NOT NULL AND (SELECT count(*) FROM eshop.order_discounts WHERE code_id=c.id)>=c.usage_limit THEN RAISE EXCEPTION 'DISCOUNT_EXHAUSTED'; END IF;
 WITH tickets AS (SELECT t,n FROM jsonb_array_elements(public.normalize_form_ticket_answers_internal(f.id,p_input->'ticket')) WITH ORDINALITY s(t,n)),
 selection AS (
  SELECT n,m,p.id,p.title,p.price,p.currency_code,coalesce((p.data#>>'{deposit,amount}')::numeric,0) deposit,p.product_type,p.is_hidden
  FROM tickets CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) WITH ORDINALITY a(answer,m)
   JOIN eshop.products p ON p.id=(answer->>'product_type')::bigint WHERE answer ? 'product_type'
  UNION ALL SELECT n,2147483647,p.id,p.title,p.price,p.currency_code,coalesce((p.data#>>'{deposit,amount}')::numeric,0),p.product_type,p.is_hidden
  FROM tickets JOIN eshop.spots s ON s.id=(t->>'spot')::bigint JOIN eshop.products p ON p.id=s.product
  WHERE s.blueprint=f.blueprint),
 scoped AS (SELECT s.*,p.occasion FROM selection s JOIN eshop.product_types p ON p.id=s.product_type)
 SELECT jsonb_agg(jsonb_build_object('productId',id,'title',title,'base',price,'currency',currency_code,'deposit',deposit,
  'eligible',price>0 AND (cardinality(c.product_ids)=0 OR id=ANY(c.product_ids))) ORDER BY n,m),min(currency_code)
 INTO lines,currency FROM scoped WHERE occasion=f.occasion AND NOT is_hidden AND
 (EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=scoped.product_type AND NOT ff.is_hidden)
  OR EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(f.id) b WHERE b.product=scoped.id AND b.has_capacity));
 IF lines IS NULL OR currency IS NULL OR currency COLLATE "C" !~ '^[A-Z]{3}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'currency' IS DISTINCT FROM currency)
 THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 IF c.kind='fixed' AND c.currency_code IS DISTINCT FROM currency THEN RAISE EXCEPTION 'DISCOUNT_CURRENCY_MISMATCH'; END IF;
 digits:=CASE WHEN currency IN ('JPY','KRW','VND','CLP','ISK','BIF','DJF','GNF','KMF','PYG','RWF','UGX','VUV','XAF','XOF','XPF') THEN 0 ELSE 2 END;
 result:=public.calculate_order_discount_internal(lines,c.kind,c.value,digits)||jsonb_build_object('currency',currency,'code',c.normalized_code,'codeId',c.id,'revision',c.revision);
 RETURN result||jsonb_build_object('fingerprint',encode(extensions.digest(convert_to(jsonb_build_object('quote',result,'policy',policy,'form',f.id,'selection',p_input->'ticket')::text,'UTF8'),'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.quote_order_discount(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; un bigint; org bigint; result jsonb;
BEGIN
 IF p_input IS NULL OR octet_length(p_input::text)>1048576 THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
 SELECT * INTO f FROM public.forms WHERE key=(p_input->>'form')::uuid;
 SELECT unit,organization INTO un,org FROM public.occasions WHERE id=f.occasion;
 IF f.id IS NULL THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
 IF NOT public.abuse_charge_v1(public.abuse_effective_rules_v1('discount.quote',un,org),jsonb_build_object('recipient',f.id,'organization',org),'{}',true) THEN
  RETURN jsonb_build_object('code',429,'errorCode','ABUSE_LIMIT_EXCEEDED'); END IF;
 BEGIN
  result:=public.order_discount_quote_internal(p_input);
  -- No IDs, availability, customers or definitions leave this boundary.
  RETURN jsonb_build_object('code',200,'quote',(result-ARRAY['codeId','lines'])||jsonb_build_object('lines',(
   SELECT jsonb_agg(jsonb_build_object('productId',l->'productId','base',l->'base','discount',l->'discount','net',l->'net','currency',l->'currency') ORDER BY n)
   FROM jsonb_array_elements(result->'lines') WITH ORDINALITY rows(l,n))));
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID')||CASE WHEN public.can_manage_discount_codes(f.occasion) AND SQLERRM ~ '^DISCOUNT_[A-Z_]+$' THEN jsonb_build_object('reason',SQLERRM) ELSE '{}'::jsonb END; END;
END $$;
REVOKE ALL ON FUNCTION public.order_discount_quote_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.quote_order_discount(jsonb) FROM PUBLIC,service_role;
GRANT EXECUTE ON FUNCTION public.quote_order_discount(jsonb) TO anon,authenticated;

-- SOURCE: eshop_discounts/apply.sql
CREATE OR REPLACE FUNCTION public.apply_order_discount_internal(p_order bigint,p_input jsonb,p_tickets jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE q jsonb; tickets jsonb; snapshot jsonb; actual jsonb; item record; line jsonb; n integer:=0;
BEGIN
 -- This boundary runs after canonical admission/product locks and before payment.
 BEGIN
  q:=public.order_discount_quote_internal(p_input);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM ~ '^DISCOUNT_[A-Z_]+$' THEN RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','DISCOUNT_QUOTE_CHANGED')::text; END IF;
  RAISE;
 END;
 IF p_input#>>'{discount,fingerprint}' IS DISTINCT FROM q->>'fingerprint' THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','DISCOUNT_QUOTE_CHANGED')::text; END IF;
 IF nullif(p_input->>'discount_command_id','') IS NULL THEN RAISE EXCEPTION 'DISCOUNT_COMMAND_REQUIRED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('productId',p->'id','base',p->'price') ORDER BY tn,pn) INTO actual
  FROM jsonb_array_elements(p_tickets) WITH ORDINALITY ts(t,tn)
  CROSS JOIN LATERAL jsonb_array_elements(t->'products') WITH ORDINALITY ps(p,pn);
 IF actual IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_object('productId',l->'productId','base',l->'base') ORDER BY ls.n)
  FROM jsonb_array_elements(q->'lines') WITH ORDINALITY ls(l,n)) THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 tickets:='[]';
 FOR item IN SELECT t FROM jsonb_array_elements(p_tickets) t LOOP
  DECLARE products jsonb:='[]'; p jsonb;
  BEGIN
   FOR p IN SELECT value FROM jsonb_array_elements(item.t->'products') LOOP
    line:=q->'lines'->n; n:=n+1;
    UPDATE eshop.order_product_ticket SET base_price=(line->>'base')::numeric,discount_amount=(line->>'discount')::numeric,net_price=(line->>'net')::numeric
     WHERE id=(p->>'order_product_ticket_id')::bigint AND "order"=p_order;
    IF NOT FOUND THEN RAISE EXCEPTION 'DISCOUNT_LINE_MISSING'; END IF;
    products:=products||jsonb_build_array(p||jsonb_build_object('base_price',line->'base','discount_amount',line->'discount','price',line->'net'));
   END LOOP;
   tickets:=tickets||jsonb_build_array(jsonb_set(item.t,'{products}',products));
  END;
 END LOOP;
 snapshot:=q||jsonb_build_object('tickets',tickets,'definition',(SELECT to_jsonb(c) FROM eshop.discount_codes c WHERE c.id=(q->>'codeId')::bigint));
 INSERT INTO eshop.order_discounts(order_id,code_id,command_id,snapshot,base_amount,discount_amount,net_amount,currency_code)
 VALUES(p_order,(q->>'codeId')::bigint,(p_input->>'discount_command_id')::uuid,snapshot,(q->>'base')::numeric,(q->>'discount')::numeric,(q->>'net')::numeric,q->>'currency');
 RETURN jsonb_build_object('tickets',tickets,'discount',q-ARRAY['lines','codeId'],'price',q->'net');
END $$;
CREATE OR REPLACE FUNCTION public.assert_order_discount_unchanged_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.order_discounts WHERE order_id=p_order) THEN RAISE EXCEPTION 'DISCOUNTED_ORDER_PRICE_IMMUTABLE'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.apply_order_discount_internal(bigint,jsonb,jsonb),public.assert_order_discount_unchanged_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/product_selection_contract.sql
-- Shared admission/required-product validation for checkout and term moves.
CREATE OR REPLACE FUNCTION public.assert_ticket_required_products_internal(p_form bigint,p_products bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE missing_field bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=ANY(p_products) AND pt.type='spot') AND NOT coalesce((SELECT bool_and(is_hidden IS TRUE)
   FROM public.form_fields WHERE form=p_form AND type='ticket'),false) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',1015,'message','Spot product is missing in ticket fields')::text;
 END IF;
 SELECT ff.id INTO missing_field FROM public.form_fields ff WHERE ff.form=p_form AND ff.type='product_type'
  AND ff.is_ticket_field AND ff.is_required AND NOT ff.is_hidden AND NOT EXISTS(
   SELECT 1 FROM eshop.products p WHERE p.id=ANY(p_products) AND p.product_type=ff.product_type)
 ORDER BY ff.id LIMIT 1;
 IF FOUND THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',missing_field,'message','Required product selection missing')::text;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_ticket_required_products_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/materialize_ticket_products_internal_v1.sql
-- Private product materializer. Callers normalize selection, lock capacity/products,
-- and determine ticket identity first. It never creates an order or a ticket.
CREATE OR REPLACE FUNCTION public.materialize_ticket_products_internal_v1(
 order_id bigint,form_id bigint,ticket_id bigint,ticket_data jsonb,spot_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE
 is_editor boolean; occasion_id bigint; spot_data record; spot_product record; spot_id bigint;
 spot_product_id bigint;
 missing_required_product_field bigint;
 ticket_note text; product_id bigint; ordered_count bigint; field_item jsonb;
 products_array bigint[] := '{}'; product_data record; ticket_products jsonb;
 order_product_ticket_id bigint; first_currency_code text; calculated_price numeric := 0;
 v_product_deposit numeric; v_total_deposit numeric := 0; now timestamptz := clock_timestamp();
BEGIN
 SELECT occasion INTO STRICT occasion_id FROM public.forms WHERE id=form_id;
 is_editor:=coalesce(public.can_write_orders(occasion_id),false);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND form=form_id AND occasion=occasion_id)
 OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket_id AND occasion=occasion_id AND state='ordered') THEN
  RAISE EXCEPTION 'TICKET_MATERIALIZATION_SCOPE_MISMATCH'; END IF;
            spot_data := NULL;
            spot_product_id := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (spot_secret::text)::UUID;
                IF (NOT coalesce(is_editor,false) AND
                     (spot_secret IS NULL OR spot_data.secret IS NULL
                      OR spot_data.secret IS DISTINCT FROM spot_secret
                      OR spot_data.secret_expiration_time IS NULL
                      OR spot_data.secret_expiration_time <= clock_timestamp()))
                   OR (coalesce(is_editor,false) AND spot_data.secret IS NOT NULL
                       AND spot_data.secret_expiration_time > clock_timestamp()
                       AND spot_data.secret IS DISTINCT FROM spot_secret) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
                spot_product_id := spot_product.id;
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

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product_id;
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
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
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

                PERFORM public.assert_admission_seating_internal(form_id,product_id,spot_id);

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

                IF product_data.type = 'spot' AND spot_product_id IS NULL THEN
                    spot_product := product_data;
                    spot_product_id := product_data.id;
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

                INSERT INTO eshop.order_product_ticket ("order", product, ticket,base_price,net_price)
                VALUES (order_id, product_id, ticket_id,product_data.price,product_data.price)
                RETURNING id INTO order_product_ticket_id;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product_id IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product_id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'order_product_ticket_id',order_product_ticket_id,
                        'base_price',product_data.price,'discount_amount',0,
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

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product_id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, secret = NULL, secret_expiration_time = NULL, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- Active seat sales still require an actual admission entitlement.
            -- Hiding ticket issuance cannot turn an auxiliary fee into a
            -- seatless admission behind the published/legacy seating plan.
            IF spot_product_id IS NULL AND EXISTS(
                SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
                WHERE f.id=form_id AND f.blueprint IS NOT NULL
                  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
            ) THEN
                RAISE EXCEPTION '%',jsonb_build_object('code',409,
                  'errorCode','ADMISSION_SOURCE_REQUIRES_SEATING')::text;
            END IF;

            PERFORM public.assert_ticket_required_products_internal(form_id,products_array);

 RETURN jsonb_build_object('products',ticket_products,'price',calculated_price,
  'deposit',v_total_deposit,'currency_code',first_currency_code,'spot',spot_id,'note',ticket_note);
END $$;
REVOKE ALL ON FUNCTION public.materialize_ticket_products_internal_v1(bigint,bigint,bigint,jsonb,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
<<checkout>>
DECLARE
    result JSONB;
    selected_payment_options jsonb;
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
    form_blueprint BIGINT;
    selected_spots BIGINT[];
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
    v_payment_method text;
    v_payment_instructions jsonb;
    v_provider_payment jsonb;
    v_payment_policy jsonb;
    v_discount jsonb;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
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
        PERFORM public.payment_policy_fence_internal(oc.organization) FROM public.forms f
          JOIN public.occasions oc ON oc.id=f.occasion WHERE f.key=form_key;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open, blueprint
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val, form_blueprint
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.can_write_orders(occasion_id);

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF unit_id IS NULL THEN RAISE EXCEPTION 'PAYMENT_POLICY_SCOPE_MISMATCH'; END IF;
        PERFORM public.resolve_payment_method_policy_internal(organization_id,unit_id);

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
        SELECT coalesce(array_agg((t->>'spot')::bigint),'{}') INTO selected_spots
        FROM jsonb_array_elements(input_data->'ticket') t WHERE t->>'spot' IS NOT NULL;
        IF cardinality(selected_spots)<>(SELECT count(DISTINCT id) FROM unnest(selected_spots) id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1007,'message','Duplicate spot')::text; END IF;
        -- Admission locks product/inventory parents before any seat row. The
        -- occasion scope is acquired by every caller before form/order parents.
        PERFORM 1 FROM eshop.spots WHERE id=ANY(selected_spots) ORDER BY id FOR UPDATE;
        now:=clock_timestamp();
        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS NOT TRUE THEN
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

        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Identity is explicit: offers reuse the waiting ticket; checkout creates it.
        FOR ticket_data IN SELECT * FROM jsonb_array_elements(input_data->'ticket') LOOP
            SELECT value->>'note' INTO ticket_note FROM jsonb_array_elements(coalesce(ticket_data->'fields','[]'))
              WHERE value ? 'note' LIMIT 1;
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
            result:=public.materialize_ticket_products_internal_v1(order_id,form_id,ticket_id,ticket_data,(input_data->>'secret')::uuid);
            IF first_currency_code IS NULL THEN first_currency_code:=result->>'currency_code';
            ELSIF first_currency_code IS DISTINCT FROM result->>'currency_code' THEN
              RAISE EXCEPTION '%',jsonb_build_object('code',1014,'message','Products in the order must have the same currency',
                'expected_currency',first_currency_code,'actual_currency',result->>'currency_code')::text;
            END IF;
            calculated_price:=calculated_price+(result->>'price')::numeric;
            v_total_deposit:=v_total_deposit+(result->>'deposit')::numeric;
            IF result->>'spot' IS NOT NULL THEN used_spots:=used_spots||jsonb_build_array((result->>'spot')::bigint); END IF;
            ticket_details:=ticket_details||jsonb_build_object('id',ticket_id,'ticket_symbol',v_ticket_symbol,
              'note',ticket_note,'products',result->'products');
        END LOOP;

        IF input_data ? 'discount' THEN
          v_discount:=public.apply_order_discount_internal(order_id,input_data,ticket_details);
          calculated_price:=(v_discount->>'price')::numeric;
          ticket_details:=v_discount->'tickets';
        END IF;

        order_data := public.strip_payment_sources_internal(input_data) - ARRAY['ticket','discount','discount_command_id'] || JSONB_BUILD_OBJECT('tickets', public.order_tickets_with_seating_internal(order_id, ticket_details));

        IF v_discount IS NOT NULL THEN order_data:=order_data||jsonb_build_object('discount',v_discount->'discount'); END IF;

        v_payment_method:=input_data->>'payment_method';
        IF v_payment_method IS NULL THEN
          IF calculated_price=0 THEN
            -- Released no-money registration rows retain their bank-shaped storage
            -- identity only. No bank service, account, reference or action is issued.
            v_payment_method:=CASE WHEN form_data#>'{payments,cashEnabled}'='true'::jsonb THEN 'cash' ELSE 'bank' END;
          ELSE
            selected_payment_options:=public.form_payment_availability_internal(form_id)->'available';
            IF jsonb_array_length(selected_payment_options)<>1 THEN RAISE EXCEPTION 'PAYMENT_METHOD_REQUIRED'; END IF;
            v_payment_method:=selected_payment_options->>0;
          END IF;
        END IF;
        IF NOT public.payment_method_registered_internal(v_payment_method) THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        -- Selection exclusivity applies to free orders too; repricing must retain
        -- a method that the form actually offered. Online readiness and recipient
        -- changes remain owned by the provider's locked initialization below.
        IF coalesce(form_data#>'{payments,cashEnabled}'='true'::jsonb,false)
             IS DISTINCT FROM (v_payment_method='cash') THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        v_payment_policy:=public.resolve_form_payment_policy_internal(form_id,v_payment_method);
        PERFORM public.check_payment_client_capabilities_internal(v_payment_policy,v_payment_method,input_data->'client_capabilities');
        IF calculated_price>0 AND NOT public.payment_method_is_online_internal(v_payment_method)
          AND NOT (public.form_payment_availability_internal(form_id)->'available' ? v_payment_method) THEN
          RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
        IF v_payment_method='cash' THEN v_total_deposit:=0; END IF;
        IF calculated_price=0 THEN
          IF public.payment_method_is_online_internal(v_payment_method) THEN
            IF public.payment_provider_connection_internal(form_data->'payments',v_payment_method) IS NULL THEN RAISE EXCEPTION 'PAYMENT_METHOD_UNAVAILABLE'; END IF;
            -- A selected hosted method still needs no provider identity for a
            -- no-money registration. Reuse the bounded released storage shape.
            v_payment_method:='bank';
          END IF;
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method) VALUES(0,first_currency_code,now,v_payment_method) RETURNING id INTO payment_info_id;
        ELSE
          v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'initialize_payment',jsonb_build_object(
            'formId',form_id,'input',input_data,'amount',calculated_price,'currency',first_currency_code,'deposit',v_total_deposit,'createdAt',now));
          payment_info_id:=(v_provider_payment->>'paymentInfoId')::bigint;
          IF payment_info_id IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.payment_info provider_payment
            WHERE provider_payment.id=payment_info_id AND provider_payment.payment_method=v_payment_method
              AND provider_payment.amount=calculated_price AND provider_payment.currency_code=first_currency_code) THEN
            RAISE EXCEPTION 'PAYMENT_PROVIDER_PREPARATION_INVALID'; END IF;
          bank_account_id:=NULL;
        END IF;

        -- The locked connector first validates its original recipient identity,
        -- preserving the released stale-recipient rejection. Full configuration
        -- validation still runs before the order/attempt commits; failure rolls
        -- back the local preparation and never dispatches a remote request.
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        UPDATE eshop.payment_info SET data=coalesce(data,'{}')||jsonb_build_object('no_money_registration',calculated_price=0,'payment_policy',v_payment_policy-'durationSeconds') WHERE id=payment_info_id;
        PERFORM public.notification_center_prepared_invalidate_order(order_id);
        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        v_payment_instructions:=public.ensure_order_payment_instructions_internal(order_id);
        bank_account_id:=(v_payment_instructions->>'bank_account')::bigint;
        generated_variable_symbol:=(v_payment_instructions->>'variable_symbol')::bigint;
        generated_creditor_reference:=v_payment_instructions->>'creditor_reference';
        account_number:=v_payment_instructions->>'account_number';
        account_number_human_readable:=v_payment_instructions->>'account_number_human_readable';
        creditor_name:=v_payment_instructions->>'creditor_name';

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          IF public.payment_method_is_online_internal(v_payment_method) THEN
              v_provider_payment:=public.payment_provider_call_internal(v_payment_method,'create_attempt',jsonb_build_object('orderId',order_id));
              deadline:=(v_provider_payment->>'expiresAt')::timestamptz;
              IF deadline IS NULL THEN RAISE EXCEPTION 'PAYMENT_PROVIDER_DEADLINE_INVALID'; END IF;
          ELSIF v_payment_policy->>'mode'='custom' THEN
              deadline:=now+make_interval(secs=>(v_payment_policy->>'durationSeconds')::bigint);
              UPDATE eshop.payment_info SET deadline=checkout.deadline WHERE id=payment_info_id;
              PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 AND v_payment_policy->>'mode'<>'none' THEN
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
                    PERFORM public.queue_payment_reminders_internal(occasion_id,payment_info_id);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data-ARRAY['discount','discount_command_id'], 'discount',v_discount->'discount', 'tickets', ticket_details,'payment_policy',v_payment_policy-'durationSeconds'),
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
            'payment',public.customer_order_payment_internal(order_id),
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
                    'payment_method',v_payment_method,
                    'data',jsonb_build_object('payment_policy',v_payment_policy-'durationSeconds'),
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

        IF v_discount IS NOT NULL THEN result:=result||jsonb_build_object('paymentPreparationPolicy','leased_keep_pending'); END IF;

    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM='DISCOUNT_INVALID' THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN SQLERRM = 'STRIPE_RECIPIENT_CHANGED' THEN
                JSONB_BUILD_OBJECT('code',409,'errorCode','STRIPE_RECIPIENT_CHANGED',
                    'message','The payment recipient changed. Review the current form.')
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    PERFORM public.notification_center_order_capacity_internal(order_id);
    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_orders/create_ticket_order_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_command_internal(
  p_order jsonb,p_command_id uuid,p_client_id uuid,p_context jsonb DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_symbol text; v_before_users uuid[]; v_actor_kind text; v_origin jsonb; v_form bigint;
BEGIN
  IF p_order IS NULL OR jsonb_typeof(p_order)<>'object'
    OR octet_length(p_order::text)>4194304 OR p_command_id IS NULL
    OR (v_actor IS NULL AND p_client_id IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order command'; END IF;
  SELECT f.occasion INTO v_occasion FROM public.forms f
    WHERE f.key=NULLIF(p_order->>'form','')::uuid;
  IF v_occasion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket order form not found'; END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion',v_occasion,'order',public.strip_payment_sources_internal(p_order))
      ||CASE WHEN p_context IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('administration',p_context) END)::text,'UTF8'),'sha256'),'hex');
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
    IF v_actor IS NULL AND p_context IS NULL THEN
      v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,CASE WHEN (v_result#>>'{data,order,payment_info,amount}')::numeric=0 THEN 'free_registration' ELSE 'purchase' END),'null'::jsonb));
    END IF;
    RETURN public.project_local_payment_reference_order_internal(v_result);
  END IF;
  IF p_order ? 'checkoutOrigin' THEN
    SELECT id INTO v_form FROM public.forms WHERE key=(p_order->>'form')::uuid;
    v_origin:=public.read_checkout_origin_internal(p_order->>'checkoutOrigin',v_form);
    IF v_origin IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',400,
        jsonb_build_object('code',400,'errorCode','CHECKOUT_CONTEXT_EXPIRED'));
    END IF;
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.create_ticket_order_internal_v1((public.strip_payment_sources_internal(p_order)-ARRAY['checkoutOrigin','discount_command_id'])||CASE WHEN p_order ? 'discount' THEN jsonb_build_object('discount_command_id',p_command_id) ELSE '{}'::jsonb END);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  PERFORM public.attach_checkout_origin_internal((v_result#>>'{order,id}')::bigint,v_origin);
  PERFORM public.attach_provider_order_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order);
  PERFORM public.enqueue_ticket_order_confirmation_v1(
    p_command_id,v_occasion,v_result,p_order->>'lang');
  IF p_context IS NOT NULL THEN v_result:=v_result||jsonb_build_object('adminQuote',p_context->'quote','paymentPreparationPolicy','leased_keep_pending'); END IF;
  v_result:=public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.create',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',v_result#>>'{order,id}','operation','insert',
      'safeLabel','Ticket order','changedFields',jsonb_build_array(
        'tickets','products','allocations','membership'))),v_before_users,v_result,
    v_actor_kind);
  -- The receipt remains frozen; first response and authorized replay project the
  -- same immutable facts, filtered through current stored form policy.
  IF v_actor IS NULL AND p_context IS NULL THEN
    PERFORM public.record_form_conversion_internal((v_result#>>'{data,order,id}')::bigint);
    v_result:=jsonb_set(v_result,'{data,analytics}',coalesce(
      public.form_conversion_datalayer_internal((v_result#>>'{data,order,id}')::bigint,CASE WHEN (v_result#>>'{data,order,payment_info,amount}')::numeric=0 THEN 'free_registration' ELSE 'purchase' END),'null'::jsonb));
  END IF;
  RETURN v_result;
END; $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_command_internal(jsonb,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Released RPC signature and ordinary checkout hashes remain unchanged.
CREATE OR REPLACE FUNCTION public.create_ticket_order_client_sync_v1(p_order jsonb,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.create_ticket_order_command_internal(p_order,p_command_id,p_client_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ticket_order_client_sync_v1(jsonb,uuid,uuid) TO anon,authenticated;

-- SOURCE: eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer; email text;
BEGIN
 IF nullif(p_input->>'email','') IS NOT NULL AND NOT public.email_address_is_valid(p_input->>'email') THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL')::text; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND type='email' AND NOT is_hidden
 AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  FOR email IN
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE NOT f.is_ticket_field AND answer ? k
   UNION ALL
   SELECT answer->>k FROM jsonb_array_elements(coalesce(p_people,'[]')) participant(value),
    LATERAL jsonb_array_elements(coalesce(participant.value->'fields','[]')) answer WHERE f.is_ticket_field AND answer ? k
  LOOP
   IF nullif(email,'') IS NOT NULL AND NOT public.email_address_is_valid(email) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','INVALID_EMAIL','fieldId',f.id)::text; END IF;
  END LOOP;
 END LOOP;
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    -- Selected seats use the ticket's top-level spot transport. The finalizer
    -- checks occasion ownership, availability and reservation secret afterward.
    IF f.type='spot' AND (p_waitlist OR nullif(person->>'spot','') IS NOT NULL) THEN
     CONTINUE;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.accept_waitlist_offer_internal(p_payload jsonb,p_command uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE w eshop.waitlist_offers; o eshop.orders; fid bigint; target bigint; ids bigint[]; selected_slots uuid[];
 n integer; remaining integer; result jsonb; input jsonb; old_tickets jsonb; old_slots jsonb; old_links jsonb; conversion text;
 original_group jsonb; remaining_group jsonb; accepted_group jsonb; history_snapshot jsonb;
BEGIN
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=(p_payload->>'offerId')::uuid;
 fid:=public.check_waitlist_scope_internal(w.order_id,w.id,p_payload->>'token',p_actor,'accept');
 PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=w.order_id)]);
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[w.order_id]);
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=w.id FOR UPDATE;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=w.order_id;
 PERFORM public.expire_waitlist_form_internal(fid);
 IF w.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 IF o.state<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 SELECT array_agg(x::bigint) INTO ids FROM jsonb_array_elements_text(p_payload->'ticketIds') x;
 n:=coalesce(cardinality(ids),0);
 IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Invalid selected persons'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id) ORDER BY id FOR UPDATE;
 original_group:=public.snapshot_waitlist_tickets_internal(o.id);
 IF n<>(SELECT count(*) FROM public.get_order_tickets_internal(o.id) p WHERE p.id=ANY(ids) AND state='waitlisted'
 AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.ticket_id=p.id AND s.outcome='pending' AND s.offer_id<>w.id)) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Preserve slots already attached to selected people, then exchange only the necessary unused bindings.
 SELECT array_agg(id ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id) INTO selected_slots
 FROM (SELECT * FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending'
 ORDER BY CASE WHEN ticket_id=ANY(ids) THEN 0 ELSE 1 END,id LIMIT n FOR UPDATE) s;
 IF coalesce(cardinality(selected_slots),0)<>n THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 -- Journal the exact pre-swap bindings, including displaced offered people.
 SELECT jsonb_agg(to_jsonb(p)) INTO old_tickets FROM eshop.tickets p
 WHERE id=ANY(ids) OR id IN(SELECT ticket_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots));
 SELECT jsonb_agg(to_jsonb(s)) INTO old_slots FROM eshop.waitlist_offer_slots s WHERE id=ANY(selected_slots);
 SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO old_links FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=ANY(ids);
 -- Release temporary bindings using a terminal outcome so the pending uniqueness invariant never needs deferral.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(selected_slots);
 WITH persons AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(ids) id), slots AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(selected_slots) id)
 UPDATE eshop.waitlist_offer_slots s SET ticket_id=p.id FROM persons p JOIN slots x USING(n) WHERE s.id=x.id;
 SELECT count(*) INTO remaining FROM public.get_order_tickets_internal(o.id) WHERE state='waitlisted';
 conversion:=CASE WHEN remaining=n THEN 'in_place' ELSE 'split' END;
 target:=CASE WHEN conversion='in_place' THEN o.id ELSE public.allocate_ticket_order_identity_internal(fid) END;
 IF conversion='split' THEN UPDATE eshop.orders SET source_waitlist_order_id=o.id WHERE id=target; END IF;
 input:=p_payload->'orderDetails';
 input:=jsonb_set(input,'{ticket}',public.normalize_form_ticket_answers_internal(fid,input->'ticket'));
 IF (input->>'form')::uuid IS DISTINCT FROM (SELECT key FROM public.forms WHERE id=fid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF jsonb_array_length(input->'ticket')<>n THEN RAISE EXCEPTION 'Selected people and tickets differ'; END IF;
 -- Each selected person must explicitly bind their stable ID to their submitted ticket.
 IF n<>(SELECT count(DISTINCT (t->>'ticketId')::bigint) FROM jsonb_array_elements(input->'ticket') t WHERE (t->>'ticketId')::bigint=ANY(ids)) THEN
  RAISE EXCEPTION 'Invalid participant ticket binding'; END IF;
 PERFORM public.validate_waitlist_answers_internal(fid,input,input->'ticket',false);
 UPDATE eshop.order_product_ticket SET "order"=target WHERE "order"=o.id AND ticket=ANY(ids);
 result:=public.finalize_ticket_order_internal_v1(target,(public.strip_payment_sources_internal(input)-'discount_command_id')||jsonb_build_object('discount_command_id',p_command),true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 PERFORM public.attach_provider_order_source_internal(target,p_command,input);
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,o.occasion,result,input->>'lang');
 IF (SELECT state='preparing_payment' FROM eshop.orders WHERE id=target) THEN
  INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,ticket_ids,slot_ids,previous_order_data,previous_tickets,previous_links,previous_slots)
  VALUES(p_command,o.id,target,w.id,conversion,ids,selected_slots,to_jsonb(o),old_tickets,old_links,old_slots);
 ELSE
  UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE offer_id=w.id
   AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending');
 END IF;
 remaining_group:=CASE WHEN conversion='split' THEN public.snapshot_waitlist_tickets_internal(o.id) ELSE '[]'::jsonb END;
 accepted_group:=public.snapshot_waitlist_tickets_internal(target);
 history_snapshot:=jsonb_build_object('action','waitlist_accept','commandId',p_command,'sourceOrderId',o.id,
  'targetOrderId',target,'ticketIds',ids,'conversion',conversion,'ticketsBefore',original_group,
  'ticketsAfter',remaining_group,'acceptedTickets',accepted_group);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,(SELECT state FROM eshop.orders WHERE id=o.id),history_snapshot);
 IF conversion='split' THEN
  INSERT INTO eshop.orders_history("order",state,data) VALUES(target,(SELECT state FROM eshop.orders WHERE id=target),history_snapshot);
 END IF;
 RETURN result||jsonb_build_object('sourceOrderId',o.id,'conversion',conversion,'waitlistSummary',public.get_waitlist_summary_internal(o.id));
END $$;
REVOKE ALL ON FUNCTION public.validate_waitlist_answers_internal(bigint,jsonb,jsonb,boolean),public.accept_waitlist_offer_internal(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_price            numeric;
  v_reconciliation   jsonb;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_current_products_for_compare jsonb;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT public.can_write_orders(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);
  PERFORM public.assert_order_discount_unchanged_internal(v_order_id);
  PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[p_ticket_id]);
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND public.payment_method_is_online_internal(payment_method)) THEN
    RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  PERFORM public.lock_ticket_order_products_internal(v_order_id,jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',x->'id')),'[]') FROM jsonb_array_elements(p_products) x)))));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) the shared owner decides eligibility and owns one invalidation. */
  v_reconciliation := public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  SELECT price INTO v_price FROM eshop.orders WHERE id=v_order_id;

  PERFORM public.refresh_order_payment_deadline_internal(v_order_id);

  PERFORM public.apply_allocations(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_reconciliation->>'final_state',
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket_id]);
  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'currency_code', product_data.currency_code
    )) || coalesce(public.order_spot_metadata_internal(p_spot_id), '{}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;

    price_delta NUMERIC;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[opt.ticket]);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    PERFORM public.assert_order_discount_unchanged_internal(ord.id);
    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the order_ids.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id);
    new_price := (new_product_json->>'price')::numeric;
    IF new_product_json->>'currency_code' IS DISTINCT FROM ord.currency_code THEN
      RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate the final price delta
    price_delta := new_price - original_price;
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- 6. Build the new order_ids.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- The aggregate swap reconciles each affected order once, after all seat
    -- pairs have their final products and totals, and appends one final snapshot.

END;
$$;


-- Only the aggregate applier calls this worker, after locking the complete
-- assignment graph and checking scope, holds and atomic-unit eligibility.
-- The pair helper updates purchased prices; the aggregate owns reconciliation.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_pair_locked_internal(p_first bigint,p_second bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE first_spot eshop.spots;second_spot eshop.spots;
BEGIN
 SELECT * INTO STRICT first_spot FROM eshop.spots WHERE id=p_first;
 SELECT * INTO STRICT second_spot FROM eshop.spots WHERE id=p_second;
 IF first_spot.order_product_ticket IS NOT NULL AND second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSIF first_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
 ELSIF second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSE RETURN;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=CASE WHEN id=p_first THEN second_spot.order_product_ticket ELSE first_spot.order_product_ticket END
 WHERE id IN(p_first,p_second);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE id IN(first_spot.order_product_ticket,second_spot.order_product_ticket) ORDER BY ticket));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_pair_locked_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets(bigint,bigint) TO authenticated;

REVOKE ALL ON FUNCTION public._swap_spots_generate_product_json(bigint,bigint),public._swap_spots_update_ticket(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/confirm_blueprint_order_change.sql
CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_internal_v1(p_spot_ids bigint[],p_input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE analysis jsonb;details jsonb;tickets bigint[];occ bigint;
BEGIN
 PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
 PERFORM public.check_blueprint_selection_units_internal(p_spot_ids);
 SELECT occasion INTO occ FROM eshop.spots WHERE id=p_spot_ids[1];
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 IF EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) AND secret IS NOT NULL
  AND secret_expiration_time>clock_timestamp() AND secret IS DISTINCT FROM (p_input_data->>'secret')::uuid) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
 PERFORM public.assert_order_discount_unchanged_internal(x."order") FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids);
 IF p_input_data ? 'discount' THEN RAISE EXCEPTION 'DISCOUNT_REPLACEMENT_UNSUPPORTED'; END IF;
 analysis:=public.analyze_new_order_spots(p_spot_ids);
 details:=public.blueprint_order_input_internal(p_spot_ids,p_input_data,analysis);
 IF public.payment_method_is_online_internal(p_input_data->>'payment_method') OR EXISTS(
  SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
  JOIN eshop.orders o ON o.id=i."order" JOIN eshop.payment_info p ON p.id=o.payment_info
  WHERE s.id=ANY(p_spot_ids) AND public.payment_method_is_online_internal(p.payment_method)) THEN RAISE EXCEPTION 'STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT x."order" FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spot_ids) ORDER BY id FOR UPDATE;
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT x.ticket FROM eshop.spots s
  JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE s.id=ANY(p_spot_ids)));
 SELECT array_agg((e->>'ticket_id')::bigint) INTO tickets FROM jsonb_array_elements(analysis->'conflicts') e
 WHERE e->>'ticket_id' IS NOT NULL;
 IF coalesce(cardinality(tickets),0)>0 THEN PERFORM public.storno_tickets_bulk_internal_v1(tickets); END IF;
 UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=ANY(p_spot_ids);
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 RETURN jsonb_build_object('success',true,'message','Storno performed. Ready to create new order.','orderDetails',details);
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('success',false,'message',SQLERRM);
END $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/admin_form_orders.sql
-- Administrative entrypoints delegate the same checkout and single receipt as
-- public/UI creation. No ticket/payment shadow writer or second intent exists.
CREATE OR REPLACE FUNCTION public.check_form_order_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_write boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,p_write);
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.form_order_input_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>1048576
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_input) k WHERE k NOT IN ('email','fields','ticket','lang','form','payment_method','client_capabilities','discount'))
  OR jsonb_typeof(p_input->'ticket') IS DISTINCT FROM 'array' OR jsonb_array_length(p_input->'ticket') NOT BETWEEN 1 AND 1000
  OR nullif(p_input->>'email','') IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid administrative order'; END IF;
 IF p_input ? 'form' AND p_input->>'form' IS DISTINCT FROM (SELECT key::text FROM public.forms WHERE id=p_form) THEN
  RAISE insufficient_privilege USING MESSAGE='foreign order form key'; END IF;
 IF p_input ? 'payment_method' AND public.payment_method_is_online_internal(p_input->>'payment_method') THEN
  RAISE invalid_parameter_value USING MESSAGE='administrative card payment unsupported'; END IF;
 RETURN p_input||jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=p_form),'client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb);
END $$;
CREATE OR REPLACE FUNCTION public.form_order_quote_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('newOrder',jsonb_build_object('amount',o.price::text,'currencyCode',o.currency_code,
  'state',o.state,'paymentMethod',p.payment_method,'paymentPolicy',p.data->'payment_policy','bankAccountId',p.bank_account,
  'bankAccountNumber',ba.account_number,'bankAccountDisplay',ba.account_number_human_readable,
  'ticketCount',(SELECT count(DISTINCT ticket) FROM eshop.order_product_ticket WHERE "order"=o.id)))
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info LEFT JOIN eshop.bank_accounts ba ON ba.id=p.bank_account WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.form_order_facts_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('form',(SELECT to_jsonb(f)-ARRAY['key','link','created_at'] FROM public.forms f WHERE id=p_form),
  'fields',snap->'fields','products',snap->'products','productTypes',snap->'productTypes')
 FROM (SELECT public.get_form_authoring_snapshot_internal(p_form) snap) s;
$$;
CREATE OR REPLACE FUNCTION public.preview_form_order_internal(p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE result jsonb; quote jsonb; facts jsonb; snap jsonb;
BEGIN
 facts:=public.form_order_facts_internal(p_form);
 BEGIN
  result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),extensions.gen_random_uuid(),extensions.gen_random_uuid(),NULL);
  IF (result->>'code')::int=200 THEN quote:=public.form_order_quote_internal((result#>>'{data,order,id}')::bigint); END IF;
  RAISE SQLSTATE 'P0F90' USING MESSAGE='rollback administrative order quote';
 EXCEPTION WHEN SQLSTATE 'P0F90' THEN NULL; END;
 IF (result->>'code')::int<>200 THEN RETURN jsonb_build_object('code',422,'reason','ORDER_NOT_CREATABLE'); END IF;
 RETURN jsonb_build_object('code',200,'quote',quote,'confirmationHash',encode(extensions.digest(
  jsonb_build_object('actor',auth.uid(),'form',p_form,'input',p_input,'facts',facts,'quote',quote)::text,'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.lock_form_order_internal(p_occasion bigint,p_form bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 -- Same parent order as actual checkout and the administration seat flow.
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 PERFORM 1 FROM eshop.product_types WHERE id IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.products WHERE product_type IN(SELECT product_type FROM public.form_fields WHERE form=p_form) ORDER BY id FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.preview_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 RETURN public.preview_form_order_internal(p_form,p_input)||jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid());
END $$;
CREATE OR REPLACE FUNCTION public.create_admin_form_order(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,p_input jsonb,
 p_confirmation_hash text,p_expected_actor uuid,p_command_id uuid,p_client_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior jsonb; receipt_status text; preview jsonb; quote jsonb; result jsonb; context jsonb;
BEGIN
 IF p_expected_actor IS DISTINCT FROM auth.uid() OR auth.uid() IS NULL OR p_confirmation_hash IS NULL OR p_confirmation_hash !~ '^[a-f0-9]{64}$' THEN
  RAISE insufficient_privilege USING MESSAGE='confirmed order actor required'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 PERFORM public.lock_form_order_internal(p_occasion,p_form);
 SELECT response,status INTO prior,receipt_status FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid()
  AND occasion=p_occasion AND command_name='inventory.order.create';
 IF receipt_status='expired' THEN RETURN jsonb_build_object('code',410,'errorCode','COMMAND_EXPIRED_DO_NOT_REPLAY'); END IF;
 IF prior IS NOT NULL THEN quote:=prior#>'{data,adminQuote}';
 ELSE
  preview:=public.preview_form_order_internal(p_form,p_input);
  IF preview->>'confirmationHash' IS DISTINCT FROM p_confirmation_hash THEN
   RETURN jsonb_build_object('code',409,'errorCode','ORDER_CHANGED_REPREVIEW_REQUIRED'); END IF;
  quote:=preview->'quote';
 END IF;
 context:=jsonb_build_object('occasion',p_occasion,'organization',p_organization,'unit',p_unit,'form',p_form,
  'actor',auth.uid(),'confirmationHash',p_confirmation_hash,'quote',quote);
 result:=public.create_ticket_order_command_internal(public.form_order_input_internal(p_form,p_input),p_command_id,p_client_id,context);
 IF prior IS NULL AND (result->>'code')::int=200 AND
   public.form_order_quote_internal((result#>>'{data,order,id}')::bigint) IS DISTINCT FROM quote THEN
  RAISE serialization_failure USING MESSAGE='order quote changed during creation'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form);
 RETURN result||jsonb_build_object('data',(result->'data')||jsonb_build_object('quote',result#>'{data,adminQuote}',
  'adminScope',jsonb_build_object('occasionId',p_occasion,'formId',p_form,'actorId',auth.uid())));
END $$;
REVOKE ALL ON FUNCTION public.check_form_order_scope_internal(bigint,bigint,bigint,bigint,boolean),
 public.form_order_input_internal(bigint,jsonb),public.form_order_quote_internal(bigint),public.preview_form_order_internal(bigint,jsonb),
 public.form_order_facts_internal(bigint),public.lock_form_order_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_admin_form_order(bigint,bigint,bigint,bigint,jsonb),
 public.create_admin_form_order(bigint,bigint,bigint,bigint,jsonb,text,uuid,uuid,uuid) TO authenticated;

-- SOURCE: eshop/get_report_ws.sql
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
    SELECT o.* FROM eshop.orders o JOIN scope s ON s.id = o.occasion WHERE o.state IS DISTINCT FROM 'stock'
  ), payments AS MATERIALIZED (
    SELECT p.* FROM eshop.payment_info p
    WHERE p.id IN (SELECT payment_info FROM orders_scope)
  ), invalid AS (
    SELECT EXISTS (SELECT 1 FROM payments p JOIN eshop.orders o ON o.payment_info = p.id
      WHERE o.occasion IS DISTINCT FROM (SELECT id FROM scope)
         OR o.currency_code IS DISTINCT FROM p.currency_code) AS value
  ), transactions_scope AS MATERIALIZED (
    SELECT t.* FROM payments p CROSS JOIN LATERAL public.payment_transaction_movements_internal(p.id) t
    WHERE t.currency=p.currency_code AND NOT t.voided
  ), stripe_movements AS MATERIALIZED (
    SELECT m.*,p.id AS payment_info_id FROM payments p
    CROSS JOIN LATERAL public.provider_payment_movements_internal(p.id) m WHERE m.currency=p.currency_code::text
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
     SELECT occurred_at::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE NOT is_refund),0) AS received,
      coalesce(-sum(amount) FILTER (WHERE is_refund),0) AS returned
      FROM transactions_scope GROUP BY 1,2
     UNION ALL
     SELECT (occurred_at AT TIME ZONE 'Europe/Prague')::date,currency,
      (coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100)::numeric(30,2),
      (coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100)::numeric(30,2) FROM stripe_movements GROUP BY 1,2
    ) facts GROUP BY day,currency
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual') AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    JOIN LATERAL public.payment_transaction_movements_internal(p.id) m ON m.transaction_id=t.id
    WHERE NOT m.voided AND NOT m.is_refund GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(ft.gross_received,0)) AS received,
      sum(coalesce(ft.refunded,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      sum(coalesce(sm.received,0)) AS stripe_received,sum(coalesce(sm.returned,0)) AS stripe_refunded,
      sum(coalesce(ft.disputed,0)) AS disputed,sum(coalesce(p.paid_externally,0)) AS external_unattributed,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(ft.gross_received,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(ft.gross_received,0)-p.deposit_amount,0) ELSE 0 END) AS beyond,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(ft.net_received,0),p.deposit_amount) ELSE 0 END) AS deposit_net,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(ft.net_received,0)-p.deposit_amount,0) ELSE 0 END) AS beyond_net
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id LEFT JOIN stripe_money sm ON sm.payment_info_id=p.id
     LEFT JOIN financial_totals ft ON ft.id=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.stripe_received,0) AS stripe_received,coalesce(p.stripe_refunded,0) AS stripe_refunded,
      coalesce(p.disputed,0) AS disputed,coalesce(p.external_unattributed,0) AS external_unattributed,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond,
      coalesce(p.deposit_net,0) AS deposit_net,coalesce(p.beyond_net,0) AS beyond_net
    FROM order_money o FULL JOIN payment_money p USING(currency)
  ), ticket_scope AS (
    SELECT t.* FROM eshop.tickets t JOIN scope s ON s.id=t.occasion
    WHERE EXISTS (SELECT 1 FROM eshop.order_product_ticket i JOIN orders_scope o ON o.id=i."order" WHERE i.ticket=t.id)
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
    SELECT DISTINCT ON (t.id) t.id,CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items b WHERE b.ticket_id=t.id AND b.sale_order_id=o.id) THEN o.created_at ELSE t.created_at END AS created_at,o.currency_code
    FROM ticket_scope t JOIN eshop.order_product_ticket i ON i.ticket=t.id
    JOIN orders_scope o ON o.id=i."order"
    ORDER BY t.id,o.created_at,o.id
  ), valid_ticket_order_dates AS (
    SELECT DISTINCT ON (t.id) t.id,CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items b WHERE b.ticket_id=t.id AND b.sale_order_id=o.id) THEN o.created_at ELSE t.created_at END AS created_at,o.currency_code
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
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text,
      'deposit_received_net',deposit_net::text,'beyond_deposit_received_net',beyond_net::text
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
    'discounts_by_currency',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY currency_code) FROM (
      SELECT d.currency_code,count(*) uses,sum(d.base_amount)::text base_amount,sum(d.discount_amount)::text discount_amount,sum(d.net_amount)::text net_amount
      FROM eshop.order_discounts d JOIN eshop.discount_codes c ON c.id=d.code_id WHERE c.occasion IN (SELECT id FROM scope) GROUP BY d.currency_code
    ) d),'[]'::jsonb),
    'products',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY type_id,product_id) FROM products p),'[]'::jsonb),
     'ticket_batches', (SELECT jsonb_build_object('total',count(*),'available',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state<>'storno'),
      'sold_active',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state<>'storno'),
      'voided_unsold',count(*) FILTER(WHERE i.sale_order_id IS NULL AND t.state='storno'),
      'cancelled_after_sale',count(*) FILTER(WHERE i.sale_order_id IS NOT NULL AND t.state='storno'))
      FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id JOIN eshop.tickets t ON t.id=i.ticket_id
      WHERE b.occasion IN(SELECT id FROM scope)),
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

-- SOURCE: eshop_orders/replacement_invoice_preparation.sql
-- Confirmed seat replacements and administrative form orders share this owner.
-- Their order allocation is already committed. Provider
-- preparation retries keep the new allocation and fence invoice POST separately.
CREATE TABLE IF NOT EXISTS eshop.replacement_invoice_preparations(
 command_id uuid PRIMARY KEY,
 order_id bigint NOT NULL UNIQUE REFERENCES eshop.orders(id) ON DELETE CASCADE,
 state text NOT NULL CHECK(state IN('claimed','retryable','unknown','complete')),
 dispatch_started boolean NOT NULL DEFAULT false,
 lease_token uuid,
 lease_until timestamptz,
 attempts integer NOT NULL DEFAULT 0,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((lease_token IS NULL)=(lease_until IS NULL))
);
ALTER TABLE eshop.replacement_invoice_preparations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE eshop.replacement_invoice_preparations FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.claim_replacement_invoice_preparation(p_order bigint,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE attempt eshop.replacement_invoice_preparations;receipt jsonb;token uuid:=extensions.gen_random_uuid();state text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT o.state INTO state FROM eshop.orders o WHERE o.id=p_order FOR UPDATE;
 SELECT r.response INTO receipt FROM public.client_mutation_receipts r
  WHERE r.command_id=p_command AND (r.command_name='inventory.order.replace' OR (r.command_name IN('inventory.order.create','inventory.waitlist.accept') AND (r.response#>'{data,adminQuote}' IS NOT NULL OR (r.response#>>'{data,paymentPreparationPolicy}'='leased_keep_pending' AND EXISTS(SELECT 1 FROM eshop.order_discounts d WHERE d.order_id=p_order AND d.command_id=p_command))))) AND r.status='completed'
  AND r.response->>'status'='applied' AND (r.response#>>'{data,order,id}')::bigint=p_order;
 IF receipt IS NULL AND NOT EXISTS(SELECT 1 FROM eshop.replacement_invoice_preparations a
  WHERE a.command_id=p_command AND a.order_id=p_order) THEN
  RAISE insufficient_privilege USING MESSAGE='replacement receipt unavailable'; END IF;
 IF state IN('ordered','paid') THEN RETURN jsonb_build_object('status','complete'); END IF;
 IF state IS DISTINCT FROM 'preparing_payment' THEN RETURN jsonb_build_object('status','closed'); END IF;
 PERFORM 1 FROM public.email_messages q WHERE q.code='TICKET_ORDER_CONFIRMATION'
  AND q.data->>'command_id'=p_command::text AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order
  AND q.data->>'fakturoid_pending'='true' FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='invoice preparation claim unavailable'; END IF;
 SELECT * INTO attempt FROM eshop.replacement_invoice_preparations WHERE command_id=p_command FOR UPDATE;
 IF NOT FOUND THEN
  -- Legacy pending receipts may already have dispatched an invoice. They are
  -- lookup-only; absence in one GET is not proof that a POST never executed.
  INSERT INTO eshop.replacement_invoice_preparations(command_id,order_id,state,dispatch_started)
   VALUES(p_command,p_order,'retryable',receipt#>>'{data,paymentPreparationPolicy}' IS DISTINCT FROM 'leased_keep_pending');
  SELECT * INTO STRICT attempt FROM eshop.replacement_invoice_preparations WHERE command_id=p_command FOR UPDATE;
 END IF;
 IF attempt.order_id<>p_order THEN RAISE insufficient_privilege USING MESSAGE='invoice order mismatch'; END IF;
 IF attempt.state='complete' THEN RETURN jsonb_build_object('status','complete'); END IF;
 IF attempt.lease_until>clock_timestamp() THEN RETURN jsonb_build_object('status','busy'); END IF;
 UPDATE eshop.replacement_invoice_preparations SET state='claimed',lease_token=token,
  lease_until=clock_timestamp()+interval '180 seconds',attempts=attempts+1,updated_at=clock_timestamp()
 WHERE command_id=p_command;
 RETURN jsonb_build_object('status','claimed','token',token,'allowCreate',NOT attempt.dispatch_started);
END $$;
REVOKE ALL ON FUNCTION public.claim_replacement_invoice_preparation(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_replacement_invoice_preparation(bigint,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.mark_replacement_invoice_dispatch(p_order bigint,p_command uuid,p_token uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 UPDATE eshop.replacement_invoice_preparations SET dispatch_started=true,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order AND lease_token=p_token AND lease_until>clock_timestamp()
  AND state='claimed' AND NOT dispatch_started;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='invoice dispatch lease unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.mark_replacement_invoice_dispatch(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_replacement_invoice_dispatch(bigint,uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.release_replacement_invoice_preparation(p_order bigint,p_command uuid,p_token uuid,p_not_created boolean DEFAULT false)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_not_created IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invoice outcome required'; END IF;
 UPDATE eshop.replacement_invoice_preparations SET
  dispatch_started=dispatch_started AND NOT p_not_created,
  state=CASE WHEN dispatch_started AND NOT p_not_created THEN 'unknown' ELSE 'retryable' END,
  lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order AND lease_token=p_token AND state='claimed';
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.release_replacement_invoice_preparation(bigint,uuid,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.release_replacement_invoice_preparation(bigint,uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.complete_replacement_invoice_preparation(p_order bigint,p_command uuid,p_token uuid,p_variable_symbol bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE symbol bigint;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.email_messages q WHERE q.code='TICKET_ORDER_CONFIRMATION'
  AND q.data->>'command_id'=p_command::text AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order FOR UPDATE;
 PERFORM 1 FROM eshop.replacement_invoice_preparations WHERE command_id=p_command AND order_id=p_order
  AND lease_token=p_token AND lease_until>clock_timestamp() AND state='claimed' FOR UPDATE;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='invoice completion lease unavailable'; END IF;
 symbol:=public.complete_fakturoid_ticket_order_v1(p_order,p_command,p_variable_symbol);
 UPDATE eshop.replacement_invoice_preparations SET state='complete',lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp()
 WHERE command_id=p_command AND order_id=p_order;
 RETURN symbol;
END $$;
REVOKE ALL ON FUNCTION public.complete_replacement_invoice_preparation(bigint,uuid,uuid,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_replacement_invoice_preparation(bigint,uuid,uuid,bigint) TO service_role;
