-- Stripe checkout, atomic provider facts and domain guards. Unpublished; no pilot activation.

-- SOURCE: public_links/reserved_paths.sql
-- Shared roots must never become occasion slugs.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug='stripe' AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.legacy_occasion_link_bindings WHERE slug='stripe' AND occasion IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.occasions WHERE link='stripe') THEN
  RAISE EXCEPTION 'Stripe route conflicts with an existing occasion slug';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.occasion_reserved_public_paths_internal()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = public, extensions AS $$
 SELECT ARRAY['resetPassword','forgotPassword','reset-password','forgot-password','login','signup','settings','install','unit','admin','form','scan','transfer','app','privacy','terms','support','delete-account','google-auth','stripe','assets','icons','flutter','index.html','flutter.html','favicon.ico','manifest.json','robots.txt','version.json','backend-activation.json'];
$$;

REVOKE ALL ON FUNCTION public.occasion_reserved_public_paths_internal() FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/checkout_schema.sql
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN return_base_url text;
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN refund_cursor text CHECK(refund_cursor IS NULL OR refund_cursor ~ '^re_[A-Za-z0-9]+$');
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN session_lookup_cursor text CHECK(session_lookup_cursor IS NULL OR session_lookup_cursor ~ '^cs_[A-Za-z0-9_]+$');
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN session_lookup_found text CHECK(session_lookup_found IS NULL OR session_lookup_found ~ '^cs_[A-Za-z0-9_]+$');

-- SOURCE: eshop_stripe/checkout_abuse.sql
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('stripe.checkout.token.minute','stripe.checkout','actor','rolling',60,60,5,10),
 ('stripe.checkout.unit.minute','stripe.checkout','unit','rolling',60,60,100,200),
 ('stripe.checkout.organization.day','stripe.checkout','organization','rolling',86400,3600,5000,10000);

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
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'order.mutation' THEN 4
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
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
 IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(p_unit) OR public.get_is_editor_on_unit(p_unit)) THEN
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

-- SOURCE: eshop_stripe/form_availability.sql
-- Private form projection. Configuration survives temporary provider restrictions.
CREATE OR REPLACE FUNCTION public.stripe_form_compatibility_internal(p_form bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE u bigint; currencies text[]; d jsonb; sale_end timestamptz; site text;
BEGIN
 SELECT o.unit,public.get_effective_form_data(f.id) INTO u,d
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 IF u IS NULL THEN RETURN 'organizer_unavailable'; END IF;
 SELECT org.data->>'DEFAULT_URL' INTO site FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN public.organizations org ON org.id=o.organization WHERE f.id=p_form;
 IF site IS NULL OR site !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9/_-]*)?$' THEN RETURN 'return_origin_unavailable'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=u AND type='FAKTUROID') THEN RETURN 'fakturoid_unsupported'; END IF;
 SELECT array_agg(DISTINCT p.currency_code::text) INTO currencies FROM public.form_fields ff
 JOIN eshop.products p ON p.product_type=ff.product_type WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false);
 IF cardinality(currencies) IS DISTINCT FROM 1 OR currencies[1] IS NULL OR NOT currencies[1]=ANY(ARRAY['CZK','EUR','PLN','USD','GBP']) THEN RETURN 'currency_unsupported'; END IF;
 IF EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
  WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
  AND coalesce((p.data#>>'{deposit,amount}')::numeric,0)>0) THEN RETURN 'deposit_unsupported'; END IF;
 IF EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
  WHERE ff.form=p_form AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
  AND coalesce(p.data->'meta_surcharge','{}'::jsonb)<>'{}'::jsonb) THEN RETURN 'surcharge_unsupported'; END IF;
 sale_end:=nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz;
 IF sale_end IS NOT NULL AND sale_end<=clock_timestamp()+interval '31 minutes' THEN RETURN 'sale_ending'; END IF;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.stripe_form_compatibility_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.validate_form_payment_configuration_internal(p_form bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; org bigint; u bigint; reason text;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 IF config IS NULL THEN RETURN; END IF;
 IF jsonb_typeof(config)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(config) k WHERE k NOT IN ('bankEnabled','stripeConnectionId'))
  OR (config ? 'bankEnabled' AND jsonb_typeof(config->'bankEnabled')<>'boolean') THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
 IF nullif(config->>'stripeConnectionId','') IS NULL THEN
  IF config->'bankEnabled'='false'::jsonb THEN RAISE EXCEPTION 'PAYMENT_CONFIGURATION_INVALID'; END IF;
  RETURN;
 END IF;
 -- Serialize editor selection with a verified account replacement.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 SELECT * INTO c FROM eshop.stripe_connections WHERE id=(config->>'stripeConnectionId')::uuid;
 IF c.id IS NULL OR c.organization_id<>org OR c.unit_id<>u OR NOT c.model_verified OR c.state NOT IN ('connected','restricted') THEN
  RAISE EXCEPTION 'STRIPE_RECIPIENT_UNAVAILABLE'; END IF;
 reason:=public.stripe_form_compatibility_internal(p_form);
 IF reason IS NOT NULL THEN RAISE EXCEPTION 'STRIPE_CONFIGURATION_UNSUPPORTED: %',reason; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_form_payment_configuration_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.form_payment_availability_internal(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE config jsonb; c eshop.stripe_connections; policy eshop.stripe_runtime_policy; org bigint; u bigint;
 bank boolean; card boolean; reason text; methods jsonb:='[]'::jsonb;
BEGIN
 SELECT f.data->'payments',o.organization,o.unit INTO config,org,u FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form;
 bank:=coalesce(config->'bankEnabled','true'::jsonb)='true'::jsonb;
 card:=nullif(config->>'stripeConnectionId','') IS NOT NULL;
 IF bank THEN methods:=methods||jsonb_build_array('bank'); END IF;
 IF card THEN
  SELECT * INTO c FROM eshop.stripe_connections WHERE id=(config->>'stripeConnectionId')::uuid AND organization_id=org AND unit_id=u;
  SELECT * INTO policy FROM eshop.stripe_runtime_policy WHERE organization_id=org AND livemode=c.livemode;
  reason:=CASE WHEN c.id IS NULL OR c.state NOT IN ('connected','restricted') THEN 'recipient_changed'
   WHEN NOT c.model_verified THEN 'model_unverified'
   WHEN c.paused THEN 'paused'
   WHEN NOT c.charges_enabled OR NOT c.card_payments_active OR c.state<>'connected' THEN 'stripe_restricted'
   WHEN NOT coalesce(policy.new_payments_enabled,false) THEN 'payments_disabled'
   ELSE public.stripe_form_compatibility_internal(p_form) END;
  IF reason IS NULL THEN methods:=jsonb_build_array('stripe')||methods; END IF;
 ELSE reason:='not_configured'; END IF;
 RETURN jsonb_build_object('configured',jsonb_build_object('bank',bank,'stripe',card),
  'available',methods,'stripeUnavailableReason',reason,'reservationSeconds',1860,
  'supportedSurfaces',coalesce(to_jsonb(policy.supported_surfaces),'[]'::jsonb),
  'recipient',CASE WHEN c.id IS NOT NULL THEN jsonb_build_object('connectionId',c.id,
   'name',coalesce(nullif(btrim(c.business_name),''),(SELECT title FROM public.units WHERE id=c.unit_id AND organization=c.organization_id))) END);
END $$;
REVOKE ALL ON FUNCTION public.form_payment_availability_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assert_stripe_form_payable_internal(p_form bigint,p_expected_connection uuid,p_surface text)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.stripe_connections; org bigint; u bigint; selected uuid; availability jsonb;
BEGIN
 SELECT (f.data#>>'{payments,stripeConnectionId}')::uuid,o.organization,o.unit INTO selected,org,u
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form FOR UPDATE OF f;
 IF selected IS NULL OR selected IS DISTINCT FROM p_expected_connection THEN RAISE EXCEPTION 'STRIPE_RECIPIENT_CHANGED'; END IF;
 -- Same locks are taken by pause/replacement and the kill switch. Submit rechecks availability under them.
 PERFORM 1 FROM public.units WHERE id=u AND organization=org FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_connections WHERE id=selected FOR UPDATE;
 PERFORM 1 FROM eshop.stripe_runtime_policy WHERE organization_id=org AND livemode=(SELECT livemode FROM eshop.stripe_connections WHERE id=selected) FOR UPDATE;
 availability:=public.form_payment_availability_internal(p_form);
 IF NOT (availability->'available' ? 'stripe') THEN RAISE EXCEPTION 'STRIPE_UNAVAILABLE: %',availability->>'stripeUnavailableReason'; END IF;
 IF p_surface IS NULL OR NOT (availability->'supportedSurfaces' ? p_surface) THEN RAISE EXCEPTION 'STRIPE_SURFACE_UNVERIFIED'; END IF;
 RETURN selected;
END $$;
REVOKE ALL ON FUNCTION public.assert_stripe_form_payable_internal(bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/form_recipient.sql
CREATE OR REPLACE FUNCTION public.get_form_stripe_recipient(p_unit bigint,p_occasion bigint,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.get_is_editor_order_on_occasion(p_occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.units u ON u.id=o.unit AND u.organization=o.organization
    JOIN public.user_info actor ON actor.organization=o.organization AND actor.id=auth.uid()
    WHERE o.id=p_occasion AND u.id=p_unit) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 SELECT jsonb_build_object('connectionId',id,'name',business_name,'state',state,'paused',paused,
  'modelVerified',model_verified,'chargesEnabled',charges_enabled,'payoutsEnabled',payouts_enabled,
  'cardPaymentsActive',card_payments_active,'checkedAt',checked_at,
  'unsupportedReason',CASE WHEN EXISTS(SELECT 1 FROM eshop.external_services WHERE unit=p_unit AND type='FAKTUROID') THEN 'fakturoid_unsupported' END) INTO result
 FROM eshop.stripe_connections WHERE unit_id=p_unit AND livemode=p_livemode AND state IN ('connected','restricted');
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_stripe_recipient(bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_stripe_recipient(bigint,bigint,boolean) TO authenticated;

-- SOURCE: eshop_stripe/order_creation.sql
-- A fixed 31-minute reservation leaves one minute to dispatch Stripe's minimum
-- 30-minute Session. Retries never extend it. Product acceptance is a pilot gate.
CREATE OR REPLACE FUNCTION public.create_stripe_order_attempt_internal(p_order bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c eshop.stripe_connections; attempt uuid:=extensions.gen_random_uuid(); stamp timestamptz:=date_trunc('second',clock_timestamp());
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=pi.stripe_connection_id;
 IF pi.payment_method<>'stripe' OR pi.amount<=0 OR pi.amount<>o.price OR pi.currency_code<>o.currency_code
  OR pi.amount*100<>trunc(pi.amount*100) OR o.state<>'ordered' OR o.form IS NULL OR EXISTS(
   SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=o.id) THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 INSERT INTO eshop.stripe_checkout_attempts(id,order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,
  amount_minor,currency,order_revision,idempotency_key,created_at,reservation_expires_at,return_base_url)
 VALUES(attempt,o.id,pi.id,c.organization_id,c.unit_id,c.id,c.livemode,
  (pi.amount*100)::bigint,pi.currency_code,1,'festapp:checkout:'||attempt,stamp,stamp+interval '31 minutes',
  (SELECT rtrim(data->>'DEFAULT_URL','/')||'/stripe/return' FROM public.organizations WHERE id=c.organization_id));
 UPDATE eshop.payment_info SET deadline=stamp+interval '31 minutes' WHERE id=pi.id;
 RETURN attempt;
END $$;
REVOKE ALL ON FUNCTION public.create_stripe_order_attempt_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Edge prepares random tokens and AES-GCM source using the existing email key.
-- Only hashes and the sealed source commit, in the same transaction as the order.
CREATE OR REPLACE FUNCTION public.attach_stripe_order_pay_source_internal(p_order bigint,p_command uuid,p_source jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; expiry timestamptz:=clock_timestamp()+interval '30 days';
BEGIN
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order FOR UPDATE;
 IF p_command IS NULL OR p_source->>'tokenHash' IS NULL OR p_source->>'tokenHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'returnHash' IS NULL OR p_source->>'returnHash' !~ '^[a-f0-9]{64}$'
  OR p_source->>'tokenHash'=p_source->>'returnHash'
  OR p_source->>'contentHash' IS NULL OR p_source->>'contentHash' !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_source->'sealed') IS DISTINCT FROM 'object'
  OR p_source#>>'{sealed,v}' IS DISTINCT FROM '1'
  OR nullif(p_source#>>'{sealed,ciphertext}','') IS NULL OR nullif(p_source#>>'{sealed,iv}','') IS NULL THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_REQUIRED'; END IF;
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(p_source->>'tokenHash','order_pay',p_order,NULL,expiry),
  (p_source->>'returnHash','return_read',p_order,a.id,a.reservation_expires_at+interval '1 day');
 INSERT INTO eshop.stripe_payment_link_sources(token_hash,sealed,content_hash,expires_at,command_id)
 VALUES(p_source->>'tokenHash',p_source->'sealed',p_source->>'contentHash',expiry,p_command);
END $$;
REVOKE ALL ON FUNCTION public.attach_stripe_order_pay_source_internal(bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.stripe_order_payment_projection_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; a eshop.stripe_checkout_attempts; totals record; status text; admission text; delivery text; card_refunded numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info AND payment_method='stripe';
 IF pi.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1;
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor),0)/100 INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 status:=CASE WHEN totals.disputed>0 THEN 'disputed'
  WHEN card_refunded>=a.amount_minor/100.0 THEN 'refunded'
  WHEN a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL THEN 'pending'
  WHEN a.state='action_required' OR (totals.gross_received>=pi.amount AND o.state NOT IN ('paid','sent')) THEN 'action_required'
  WHEN card_refunded>0 THEN 'partially_refunded'
  WHEN totals.gross_received>=pi.amount AND o.state IN ('paid','sent') THEN 'paid'
  WHEN a.state='expired' OR a.reservation_expires_at<=clock_timestamp() OR o.state IN ('expired','storno') THEN 'expired'
  WHEN a.state IN ('uncertain','preparing') THEN 'preparing' ELSE 'open' END;
 admission:=CASE WHEN totals.disputed>0 OR status IN ('refunded','action_required') THEN 'hold'
  WHEN status IN ('paid','partially_refunded') AND o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END;
 SELECT CASE workflow_state WHEN 'accepted' THEN 'accepted' WHEN 'failed' THEN 'failed' WHEN 'suppressed' THEN 'suppressed' WHEN 'cancelled' THEN 'suppressed' ELSE 'pending' END INTO delivery
 FROM public.email_messages WHERE order_id=o.id AND message_kind='order_tickets' ORDER BY created_at DESC,id DESC LIMIT 1;
 RETURN jsonb_build_object('method','stripe','status',status,'amount',pi.amount::text,'received',totals.gross_received::numeric(30,2)::text,
  'returned',totals.refunded::numeric(30,2)::text,'currency',trim(pi.currency_code),'admissionState',admission,'deliveryState',coalesce(delivery,'not_requested'),
  'orderState',o.state,'reservationExpiresAt',a.reservation_expires_at,'serverNow',clock_timestamp(),
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,'reconciliationFailures',a.reconcile_failures,
  'allowedActions',CASE WHEN status IN ('open','preparing') AND NOT coalesce(a.lease_expires_at>clock_timestamp(),false) THEN jsonb_build_array('refresh','pay') ELSE jsonb_build_array('refresh') END);
END $$;
REVOKE ALL ON FUNCTION public.stripe_order_payment_projection_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_stripe_order_pay_source_internal(p_order bigint,p_command uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,
  'payment',public.stripe_order_payment_projection_internal(c.order_id),
  'payBaseUrl',(SELECT regexp_replace(return_base_url,'/stripe/return$','/stripe/pay') FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id ORDER BY created_at DESC LIMIT 1))
 INTO result FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities c USING(token_hash)
 WHERE s.command_id=p_command AND c.order_id=p_order AND c.scope='order_pay'
  AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp() AND s.expires_at=c.expires_at;
 IF result IS NULL THEN
  result:=jsonb_build_object('payment',public.stripe_order_payment_projection_internal(p_order));
  IF result#>>'{payment,method}' IS DISTINCT FROM 'stripe' OR result#>>'{payment,status}' IN ('open','preparing') THEN
   RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_stripe_order_pay_source_internal(bigint,uuid) TO service_role;

-- SOURCE: eshop_stripe/checkout.sql
CREATE OR REPLACE FUNCTION public.claim_stripe_checkout_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities; a eshop.stripe_checkout_attempts; o eshop.orders; pi eshop.payment_info;
 c eshop.stripe_connections; source jsonb; lease uuid; projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND scope='order_pay' AND revoked_at IS NULL AND expires_at>clock_timestamp();
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 PERFORM public.authorize_stripe_capability_internal(p_token,'order_pay',cap.order_id);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=cap.order_id;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF a.livemode IS DISTINCT FROM p_livemode OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>a.connection_id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency OR o.currency_code<>a.currency
  OR coalesce(pi.paid_externally,0)<>0 THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 projection:=public.stripe_order_payment_projection_internal(o.id);
 IF projection->>'status' NOT IN ('open','preparing') THEN RETURN jsonb_build_object('disposition','read','payment',projection); END IF;
 IF o.price*100<>a.amount_minor THEN RAISE EXCEPTION 'STRIPE_ORDER_SNAPSHOT_INVALID'; END IF;
 IF a.lease_expires_at>clock_timestamp() OR a.reservation_expires_at<=clock_timestamp() THEN
  RETURN jsonb_build_object('disposition','busy','payment',projection); END IF;
 -- Admission precedes any provider work, keyed by the hashed pay capability.
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('stripe.checkout',a.unit_id,a.organization_id),
  jsonb_build_object('actor',cap.token_hash,'unit',a.unit_id,'organization',a.organization_id));
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' AND pc.revoked_at IS NULL AND pc.expires_at>clock_timestamp()
 ORDER BY s.created_at DESC LIMIT 1;
 IF source IS NULL OR a.return_base_url IS NULL THEN RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds',
  state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,'payment',projection,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'returnBaseUrl',a.return_base_url,'sessionId',a.session_id,'refundCursor',a.refund_cursor));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_checkout_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.commit_stripe_checkout_session_internal(p_attempt uuid,p_lease uuid,p_session text,p_url text,p_expires bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 -- Form/order first, then attempt, as in the claim and payment ingest.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT order_id FROM eshop.stripe_checkout_attempts WHERE id=p_attempt));
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR p_session IS NULL OR p_session !~ '^cs_[A-Za-z0-9_]+$'
  OR p_url IS NULL OR p_url !~ '^https://checkout[.]stripe[.]com/[^[:space:]]+$'
  OR p_expires IS DISTINCT FROM extract(epoch FROM a.reservation_expires_at)::bigint
  OR (a.session_id IS NOT NULL AND a.session_id<>p_session) THEN RAISE EXCEPTION 'STRIPE_CHECKOUT_RECEIPT_INVALID'; END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_session,checkout_url=p_url,
  state=CASE WHEN state IN ('preparing','uncertain') THEN 'open' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=least(reservation_expires_at,clock_timestamp()+interval '2 minutes')
 WHERE id=a.id;
 RETURN jsonb_build_object('committed',true,'payment',public.stripe_order_payment_projection_internal(a.order_id));
END $$;
REVOKE ALL ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.commit_stripe_checkout_session_internal(uuid,uuid,text,text,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_checkout_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE eshop.stripe_checkout_attempts SET state=CASE WHEN session_id IS NULL THEN 'uncertain' ELSE state END,
  lease_token=NULL,lease_expires_at=NULL,next_reconcile_at=clock_timestamp()+interval '1 minute'
 WHERE id=p_attempt AND lease_token=p_lease;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_checkout_internal(uuid,uuid) TO service_role;

-- Minimal read only. Knowledge of this handle cannot start Checkout or reveal PII.
CREATE OR REPLACE FUNCTION public.read_stripe_return_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='return_read' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE id=c.attempt_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.stripe_order_payment_projection_internal(cap.order_id)-'allowedActions'||jsonb_build_object('allowedActions',jsonb_build_array('refresh'));
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_return_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_return_internal(text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.read_stripe_pay_status_internal(p_token text,p_livemode boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='order_pay' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE order_id=c.order_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 RETURN public.stripe_order_payment_projection_internal(cap.order_id);
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_pay_status_internal(text,boolean) TO service_role;

-- Shared by signed webhook delivery and bounded recovery, including retired
-- connections. Pausing new sales must not stop money/refund reconciliation.
CREATE OR REPLACE FUNCTION public.claim_stripe_sync_internal(p_account text,p_livemode boolean,
 p_attempt uuid DEFAULT NULL,p_session text DEFAULT NULL,p_intent text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; lease uuid; source jsonb;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM eshop.stripe_connections WHERE account_id=p_account AND livemode=p_livemode;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 SELECT * INTO a FROM eshop.stripe_checkout_attempts WHERE connection_id=c.id AND
  ((p_attempt IS NOT NULL AND id=p_attempt) OR (p_session IS NOT NULL AND session_id=p_session) OR (p_intent IS NOT NULL AND payment_intent_id=p_intent))
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('disposition','unrelated'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=a.id FOR UPDATE;
 IF a.lease_expires_at>clock_timestamp() THEN RETURN jsonb_build_object('disposition','busy'); END IF;
 IF (p_session IS NOT NULL AND a.session_id IS NOT NULL AND p_session<>a.session_id)
  OR (p_intent IS NOT NULL AND a.payment_intent_id IS NOT NULL AND p_intent<>a.payment_intent_id) THEN RAISE EXCEPTION 'STRIPE_SYNC_IDENTITY_MISMATCH'; END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id;
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=o.id AND pc.scope='order_pay' ORDER BY s.created_at DESC LIMIT 1;
 -- Historical reads need no bearer secret. Creation still requires its source.
 IF a.return_base_url IS NULL OR (source IS NULL AND coalesce(a.session_id,p_session) IS NULL AND a.reservation_expires_at>clock_timestamp()) THEN
  RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 lease:=extensions.gen_random_uuid();
 UPDATE eshop.stripe_checkout_attempts SET lease_token=lease,lease_expires_at=clock_timestamp()+interval '120 seconds' WHERE id=a.id;
 RETURN jsonb_build_object('disposition','dispatch','lease',lease,'source',source,
  'snapshot',jsonb_build_object('attemptId',a.id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'orderReference','Order '||o.order_symbol,
   'createdAt',extract(epoch FROM a.created_at)::bigint,'expiresAt',extract(epoch FROM a.reservation_expires_at)::bigint,
   'idempotencyKey',a.idempotency_key,'returnBaseUrl',a.return_base_url,'sessionId',coalesce(a.session_id,p_session),'refundCursor',a.refund_cursor,
   'sessionLookupCursor',a.session_lookup_cursor,'sessionLookupFound',a.session_lookup_found));
END $$;
REVOKE ALL ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_stripe_sync_internal(text,boolean,uuid,text,text) TO service_role;

-- SOURCE: eshop_stripe/handoff.sql
-- Issued only from the independently authenticated order-creation result. A
-- deterministic Edge derivation makes replay retain the same one-use bearer.
CREATE OR REPLACE FUNCTION public.attach_stripe_handoff_internal(p_order bigint,p_command uuid,p_token_hash text,p_livemode boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; cap eshop.stripe_capabilities;
BEGIN
 PERFORM public.require_service_role();
 IF p_token_hash IS NULL OR p_token_hash !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF a.livemode IS DISTINCT FROM p_livemode OR NOT EXISTS(SELECT 1 FROM eshop.stripe_payment_link_sources s
  JOIN eshop.stripe_capabilities pc USING(token_hash) WHERE s.command_id=p_command AND pc.order_id=p_order AND pc.scope='order_pay'
   AND pc.revoked_at IS NULL AND pc.expires_at>clock_timestamp() AND s.expires_at>clock_timestamp()) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 INSERT INTO eshop.stripe_capabilities(token_hash,scope,order_id,attempt_id,expires_at)
 VALUES(p_token_hash,'handoff',p_order,a.id,least(a.reservation_expires_at,a.created_at+interval '30 minutes'))
 ON CONFLICT(token_hash) DO NOTHING;
 SELECT * INTO STRICT cap FROM eshop.stripe_capabilities WHERE token_hash=p_token_hash;
 IF cap.scope<>'handoff' OR cap.order_id<>p_order OR cap.attempt_id<>a.id THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Replaying creation must never renew, unconsume or un-revoke a handoff.
END $$;
REVOKE ALL ON FUNCTION public.attach_stripe_handoff_internal(bigint,uuid,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.attach_stripe_handoff_internal(bigint,uuid,text,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.read_stripe_handoff_internal(p_token text,p_livemode boolean,p_consume boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cap eshop.stripe_capabilities; source jsonb; projection jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_consume IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO cap FROM eshop.stripe_capabilities c WHERE c.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
  AND c.scope='handoff' AND c.revoked_at IS NULL AND c.expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.stripe_checkout_attempts WHERE id=c.attempt_id AND order_id=c.order_id AND livemode=p_livemode);
 IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[cap.order_id]);
 SELECT * INTO STRICT cap FROM eshop.stripe_capabilities WHERE token_hash=cap.token_hash FOR UPDATE;
 IF cap.revoked_at IS NOT NULL OR cap.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 projection:=public.stripe_order_payment_projection_internal(cap.order_id);
 IF NOT p_consume THEN
  IF cap.consumed_at IS NOT NULL THEN projection:=projection||jsonb_build_object('allowedActions',jsonb_build_array('refresh')); END IF;
  RETURN jsonb_build_object('payment',projection);
 END IF;
 PERFORM public.authorize_stripe_capability_internal(p_token,'handoff',cap.order_id,cap.attempt_id);
 SELECT jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash) INTO source
 FROM eshop.stripe_payment_link_sources s JOIN eshop.stripe_capabilities pc USING(token_hash)
 WHERE pc.order_id=cap.order_id AND pc.scope='order_pay' AND pc.revoked_at IS NULL
  AND pc.expires_at>clock_timestamp() AND s.expires_at>clock_timestamp() ORDER BY s.created_at DESC LIMIT 1;
 IF source IS NULL THEN RAISE EXCEPTION 'STRIPE_PAYMENT_SOURCE_UNAVAILABLE'; END IF;
 -- This source never crosses the Edge boundary to the handoff browser.
 RETURN jsonb_build_object('source',source,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.read_stripe_handoff_internal(text,boolean,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_stripe_handoff_internal(text,boolean,boolean) TO service_role;

-- SOURCE: eshop_stripe/ingest.sql
-- Sole provider-to-domain write boundary. Raw signature verification and current
-- account-scoped provider reads happen in Edge; every effect below commits once.
CREATE OR REPLACE FUNCTION public.ingest_stripe_payment_internal(
 p_attempt uuid,p_lease uuid,p_event jsonb,p_facts jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; pi eshop.payment_info;
 existing eshop.stripe_event_inbox; movement eshop.stripe_payment_movements; d eshop.stripe_disputes;
 fact jsonb; totals record; before_projection jsonb; projection jsonb; v_receipt jsonb; transition jsonb;
 command uuid; input_hash text; mutation_claim jsonb; before_users uuid[]; cancelled bigint[]; payment_time timestamptz;
 card_received numeric; card_refunded numeric; financial_conflict boolean;
 changed boolean:=false; observed timestamptz:=(p_facts->>'observedAt')::timestamptz;
 no_session boolean:=coalesce(p_facts->'noSessionVerified'='true'::jsonb,false);
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF p_event->>'id' IS NULL OR p_event->>'id' !~ '^evt_[A-Za-z0-9]+$'
  OR p_event->>'bodyHash' IS NULL OR p_event->>'bodyHash' !~ '^[a-f0-9]{64}$'
  OR p_event->>'accountId' IS DISTINCT FROM c.account_id OR (p_event->>'livemode')::boolean IS DISTINCT FROM a.livemode
  OR nullif(p_event->>'type','') IS NULL OR length(p_event->>'type')>100 THEN RAISE EXCEPTION 'STRIPE_EVENT_IDENTITY_INVALID'; END IF;
 SELECT * INTO existing FROM eshop.stripe_event_inbox WHERE connection_id=c.id AND event_id=p_event->>'id';
 IF FOUND THEN
  IF existing.body_sha256<>p_event->>'bodyHash' OR existing.receipt IS NULL THEN RAISE EXCEPTION 'STRIPE_EVENT_RECEIPT_INVALID'; END IF;
  RETURN existing.receipt;
 END IF;
 command:=(substr(encode(extensions.digest(c.id::text||':'||(p_event->>'id'),'sha256'),'hex'),1,32))::uuid;
 -- Event body identity is immutable; a replay may have newer provider reads.
 input_hash:=encode(extensions.digest(p_event::text,'sha256'),'hex');
 mutation_claim:=public.begin_anonymous_client_mutation_v1(command,'inventory.order.stripe_sync',
  (SELECT occasion FROM eshop.orders WHERE id=a.order_id),command,input_hash);
 IF mutation_claim->>'disposition'='replay' THEN RETURN mutation_claim->'response'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR observed IS NULL OR observed>clock_timestamp()+interval '1 minute'
  OR observed<coalesce(a.last_synced_at,'-infinity') THEN RAISE EXCEPTION 'STRIPE_SYNC_LEASE_INVALID'; END IF;
 IF pi.id<>o.payment_info OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>c.id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=a.organization_id AND unit=a.unit_id)
  OR (NOT no_session AND (p_facts->>'sessionId' IS NULL OR p_facts->>'sessionId' !~ '^cs_[A-Za-z0-9_]+$'))
  OR (no_session AND (a.session_id IS NOT NULL OR a.session_lookup_found IS NOT NULL OR p_facts->>'sessionId' IS NOT NULL
   OR p_facts->>'paymentIntentId' IS NOT NULL OR p_facts->>'sessionStatus' IS DISTINCT FROM 'expired'
   OR a.reservation_expires_at>clock_timestamp()
   OR p_event->>'type' IS DISTINCT FROM 'festapp.reconcile' OR p_facts->'movements'<>'[]'::jsonb OR p_facts->'disputes'<>'[]'::jsonb))
  OR (a.session_id IS NOT NULL AND a.session_id<>p_facts->>'sessionId')
  OR (a.payment_intent_id IS NOT NULL AND a.payment_intent_id IS DISTINCT FROM p_facts->>'paymentIntentId')
  OR jsonb_typeof(p_facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'movements')>501
  OR jsonb_typeof(p_facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'disputes')>100 THEN
  RAISE EXCEPTION 'STRIPE_FACT_IDENTITY_INVALID'; END IF;
 IF p_facts->>'refundCursor' IS NOT NULL AND (p_facts->>'refundCursor' !~ '^re_[A-Za-z0-9]+$'
  OR p_facts->>'refundCursor'=a.refund_cursor) THEN RAISE EXCEPTION 'STRIPE_REFUND_CURSOR_INVALID'; END IF;
 before_projection:=public.stripe_order_payment_projection_internal(o.id);
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=o.occasion;
 INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at)
 VALUES(c.id,p_event->>'id',p_event->>'bodyHash',p_event->>'type',to_timestamp((p_event->>'created')::bigint));
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'movements') LOOP
  IF fact->>'kind' IS NULL OR fact->>'kind' NOT IN ('payment','refund') OR fact->>'currency' IS DISTINCT FROM a.currency
   OR (fact->>'amountMinor')::numeric IS NULL OR (fact->>'amountMinor')::numeric<>trunc((fact->>'amountMinor')::numeric)
   OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor
   OR (fact->>'kind'='payment' AND (fact->>'providerId' IS DISTINCT FROM p_facts->>'paymentIntentId' OR fact->>'providerId' !~ '^pi_[A-Za-z0-9]+$' OR (fact->>'amountMinor')::bigint<>a.amount_minor))
   OR (fact->>'kind'='refund' AND (fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^re_[A-Za-z0-9]+$'))
   OR (fact->>'occurredAt')::bigint IS NULL OR (fact->>'occurredAt')::bigint<0 THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_INVALID'; END IF;
  SELECT * INTO movement FROM eshop.stripe_payment_movements WHERE connection_id=c.id AND provider_id=fact->>'providerId' AND kind=fact->>'kind';
  IF FOUND THEN
   IF movement.attempt_id<>a.id OR movement.amount_minor<>(fact->>'amountMinor')::bigint OR movement.currency<>a.currency
    OR movement.occurred_at<>to_timestamp((fact->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_CHANGED'; END IF;
  ELSE
   INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
   VALUES(c.id,fact->>'providerId',a.id,fact->>'kind',(fact->>'amountMinor')::bigint,a.currency,to_timestamp((fact->>'occurredAt')::bigint));
   changed:=true;
  END IF;
 END LOOP;
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'disputes') LOOP
  IF fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^(dp|du)_[A-Za-z0-9]+$'
   OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor OR fact->>'currency' IS DISTINCT FROM a.currency
   OR fact->>'status' IS NULL OR fact->>'status' NOT IN ('warning_needs_response','warning_under_review','warning_closed','needs_response','under_review','won','lost') THEN
   RAISE EXCEPTION 'STRIPE_DISPUTE_INVALID'; END IF;
  SELECT * INTO d FROM eshop.stripe_disputes WHERE connection_id=c.id AND provider_id=fact->>'providerId';
  IF FOUND AND (d.attempt_id<>a.id OR d.amount_minor<>(fact->>'amountMinor')::bigint) THEN RAISE EXCEPTION 'STRIPE_DISPUTE_CHANGED'; END IF;
  IF d.status IS DISTINCT FROM fact->>'status' THEN changed:=true; END IF;
  INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at)
  VALUES(c.id,fact->>'providerId',a.id,(fact->>'amountMinor')::bigint,fact->>'status',observed)
  ON CONFLICT(connection_id,provider_id) DO UPDATE SET status=excluded.status,observed_at=excluded.observed_at;
 END LOOP;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100.0,
  coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100.0 INTO card_received,card_refunded
 FROM eshop.stripe_payment_movements WHERE attempt_id=a.id;
 IF card_received*100>a.amount_minor OR card_refunded>card_received THEN RAISE EXCEPTION 'STRIPE_TOTALS_INVALID'; END IF;
 -- Actual provider money must survive a historical/manual overpayment. Hold
 -- admission and delivery for explicit resolution instead of rejecting the fact.
 financial_conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 IF financial_conflict AND NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='financial_conflict') THEN
  UPDATE eshop.stripe_checkout_attempts SET state='action_required' WHERE id=a.id;
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision) VALUES(a.id,'financial_conflict',p_event->>'id');
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);
  changed:=true;
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_facts->>'sessionId',payment_intent_id=p_facts->>'paymentIntentId',refund_cursor=p_facts->>'refundCursor',
  session_lookup_cursor=NULL,session_lookup_found=NULL
 WHERE id=a.id;
 SELECT min(occurred_at) INTO payment_time FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment';
 IF card_received>=pi.amount AND card_refunded<pi.amount AND NOT financial_conflict AND p_facts->>'refundCursor' IS NULL THEN
  IF o.state IN ('ordered','created') AND payment_time<=a.reservation_expires_at THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'STRIPE_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   UPDATE eshop.stripe_checkout_attempts SET state='action_required' WHERE id=a.id;
   IF NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='late_payment') THEN
    INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision) VALUES(a.id,'late_payment',p_event->>'id');
   END IF;
  END IF;
  UPDATE eshop.stripe_checkout_attempts SET state=CASE WHEN state='action_required' THEN state ELSE 'paid' END WHERE id=a.id;
 END IF;
 IF card_refunded>=pi.amount AND card_received>0 THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='full_refund') THEN
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id
    WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,ticket_ids,provider_revision) VALUES(a.id,'full_refund',coalesce(cancelled,'{}'),p_event->>'id');
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);
   changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND p_facts->>'sessionStatus'='expired' AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  UPDATE eshop.stripe_checkout_attempts SET state='expired' WHERE id=a.id;
  PERFORM public.cancel_order_email_intents(o.id);
  changed:=true;
 END IF;
 projection:=public.stripe_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM before_projection->>'admissionState' AND
  (projection->>'status'='disputed' OR before_projection->>'status'='disputed'
   OR projection->'reconciliationPending'='true'::jsonb OR before_projection->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision)
  VALUES(a.id,CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN before_projection->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END,p_event->>'id');
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET last_synced_at=observed,lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,
  next_reconcile_at=clock_timestamp()+CASE WHEN refund_cursor IS NOT NULL THEN interval '10 seconds' WHEN state IN ('paid','action_required') THEN interval '1 day' ELSE interval '2 minutes' END WHERE id=a.id;
 v_receipt:=public.complete_profile_inventory_membership_mutation_v1(command,o.occasion,'inventory.order.stripe_sync',
  CASE WHEN changed THEN jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
   'safeLabel','Card payment update','changedFields',jsonb_build_array('payment','state','tickets','admission','allocations'))) ELSE '[]'::jsonb END,
  before_users,jsonb_build_object('committed',true,'payment',projection),'service');
 UPDATE eshop.stripe_event_inbox SET committed_at=clock_timestamp(),receipt=v_receipt WHERE connection_id=c.id AND event_id=p_event->>'id';
 RETURN v_receipt;
END $$;
REVOKE ALL ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) TO service_role;

-- SOURCE: eshop_stripe/reconciliation.sql
-- Machine-only recovery remains available with new sales disabled or the
-- connection retired. Claiming each job uses the same lease as webhooks/pay.
CREATE OR REPLACE FUNCTION public.get_recoverable_stripe_attempts_internal(p_livemode boolean,p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_livemode IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('attemptId',x.id,'accountId',x.account_id) ORDER BY x.next_reconcile_at,x.id),'[]'::jsonb)
 INTO result FROM (
  SELECT a.id,c.account_id,a.next_reconcile_at FROM eshop.stripe_checkout_attempts a
   JOIN eshop.stripe_connections c ON c.id=a.connection_id
   WHERE a.livemode=p_livemode AND a.next_reconcile_at<=statement_timestamp()
    AND coalesce(a.lease_expires_at<=statement_timestamp(),true)
   ORDER BY a.next_reconcile_at,a.id LIMIT p_limit
 ) x;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_recoverable_stripe_attempts_internal(boolean,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fail_stripe_reconciliation_internal(p_attempt uuid,p_lease uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 -- A stale worker cannot clear another worker's lease or reset its cursor.
 UPDATE eshop.stripe_checkout_attempts SET reconcile_failures=least(reconcile_failures+1,1000),
  next_reconcile_at=clock_timestamp()+make_interval(secs=>least(3600,30*power(2,least(reconcile_failures,7)))::integer),
  lease_token=NULL,lease_expires_at=NULL WHERE id=p_attempt AND lease_token=p_lease AND p_lease IS NOT NULL;
END $$;
REVOKE ALL ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fail_stripe_reconciliation_internal(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.checkpoint_stripe_session_lookup_internal(p_attempt uuid,p_lease uuid,p_cursor text,p_found text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR p_lease IS DISTINCT FROM a.lease_token OR a.lease_expires_at<=clock_timestamp()
  OR a.session_id IS NOT NULL OR p_cursor IS NULL OR p_cursor !~ '^cs_[A-Za-z0-9_]+$' OR p_cursor=a.session_lookup_cursor
  OR (p_found IS NOT NULL AND p_found !~ '^cs_[A-Za-z0-9_]+$')
  OR (a.session_lookup_found IS NOT NULL AND a.session_lookup_found IS DISTINCT FROM p_found) THEN RAISE EXCEPTION 'STRIPE_SESSION_LOOKUP_INVALID'; END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_lookup_cursor=p_cursor,session_lookup_found=p_found,
  lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,next_reconcile_at=clock_timestamp()+interval '10 seconds' WHERE id=a.id;
END $$;
REVOKE ALL ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.checkpoint_stripe_session_lookup_internal(uuid,uuid,text,text) TO service_role;

-- Prepared for explicit pilot activation; migrations do not schedule network jobs.
CREATE OR REPLACE FUNCTION public.request_stripe_reconciliation(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_project_url IS NULL OR p_project_url !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$' THEN RAISE EXCEPTION 'STRIPE_RECOVERY_ORIGIN_INVALID'; END IF;
 PERFORM net.http_post(url:=p_project_url||'/functions/v1/stripe-reconcile',
  body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=90000);
END $$;
REVOKE ALL ON FUNCTION public.request_stripe_reconciliation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_stripe_reconciliation(text) TO service_role;

-- Retain economic facts and capability hashes; erase only expired bearer sources.
-- Historical account-scoped reads deliberately do not depend on these secrets.
CREATE OR REPLACE FUNCTION public.purge_expired_stripe_sources_internal(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE removed integer;
BEGIN
 PERFORM public.require_service_role();
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'STRIPE_RECOVERY_LIMIT_INVALID'; END IF;
 WITH expired AS (
  SELECT token_hash FROM eshop.stripe_payment_link_sources WHERE expires_at<=clock_timestamp()
   ORDER BY expires_at,token_hash LIMIT p_limit FOR UPDATE SKIP LOCKED
 ) DELETE FROM eshop.stripe_payment_link_sources s USING expired e WHERE s.token_hash=e.token_hash;
 GET DIAGNOSTICS removed=ROW_COUNT;
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.purge_expired_stripe_sources_internal(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.purge_expired_stripe_sources_internal(integer) TO service_role;

-- SOURCE: eshop_stripe/admission.sql
-- Used by every server-side admission writer. Bank tickets retain their current
-- configured online/offline policy; card tickets require a current SQL decision.
CREATE OR REPLACE FUNCTION public.stripe_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
  JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE x.ticket=p_ticket AND pi.payment_method='stripe');
$$;
CREATE OR REPLACE FUNCTION public.stripe_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
  JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE x.ticket=p_ticket AND pi.payment_method='stripe'
  AND public.stripe_order_payment_projection_internal(o.id)->>'admissionState' IS DISTINCT FROM 'valid');
$$;
REVOKE ALL ON FUNCTION public.stripe_ticket_requires_online_internal(bigint),public.stripe_ticket_admission_allowed_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_stripe/refund_decisions.sql
CREATE OR REPLACE FUNCTION public.decide_stripe_partial_refund_client_sync_v1(
 p_order bigint,p_action text,p_tickets bigint[],p_note text,p_expected_refunded_minor bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); o eshop.orders; a eshop.stripe_checkout_attempts; totals record; v_occasion bigint;
 hash text; claim jsonb; ids bigint[]; before_users uuid[]; revision text; decision uuid; card_refunded bigint;
BEGIN
 SELECT ord.occasion INTO v_occasion FROM eshop.orders ord WHERE ord.id=p_order;
 IF actor IS NULL OR v_occasion IS NULL OR NOT coalesce(public.get_is_editor_order_on_occasion(v_occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions occasion JOIN public.user_info viewer ON viewer.organization=occasion.organization AND viewer.id=actor WHERE occasion.id=v_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF p_action IS NULL OR p_action NOT IN ('keep','cancel_selected') OR p_command_id IS NULL
  OR nullif(trim(p_note),'') IS NULL OR length(trim(p_note)) NOT BETWEEN 3 AND 500
  OR p_expected_refunded_minor IS NULL THEN RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 ids:=ARRAY(SELECT DISTINCT id FROM unnest(coalesce(p_tickets,'{}'::bigint[])) id ORDER BY id);
 IF (p_action='keep' AND cardinality(ids)<>0) OR (p_action='cancel_selected' AND cardinality(ids) NOT BETWEEN 1 AND 1000) THEN
  RAISE EXCEPTION 'STRIPE_REFUND_DECISION_INVALID'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'action',p_action,'tickets',ids,
  'note',trim(p_note),'refundedMinor',p_expected_refunded_minor)::text,'sha256'),'hex');
 claim:=public.begin_client_mutation_v1(p_command_id,'inventory.order.stripe_refund_decision',v_occasion,actor,hash);
 IF claim->>'disposition'='replay' THEN RETURN claim->'response'; END IF;
 PERFORM public.admit_order_mutation_v1(v_occasion,greatest(cardinality(ids),1));
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=p_order ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 PERFORM 1 FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(a.payment_info_id);
 SELECT coalesce(sum(amount_minor),0) INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF card_refunded IS DISTINCT FROM p_expected_refunded_minor THEN RAISE EXCEPTION 'STRIPE_REFUND_REVISION_CHANGED'; END IF;
 IF card_refunded<=0 OR card_refunded>=a.amount_minor OR a.state<>'paid' OR o.state NOT IN ('paid','sent')
  OR totals.invalid_identity OR a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=o.payment_info AND id=a.payment_info_id AND payment_method='stripe' AND stripe_connection_id=a.connection_id) THEN
  RAISE EXCEPTION 'STRIPE_PARTIAL_REFUND_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(ids) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id
  WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'STRIPE_REFUND_TICKET_UNAVAILABLE'; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
 SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(provider_id,amount_minor) ORDER BY provider_id)::text,'[]'),'sha256'),'hex')
 INTO revision FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF p_action='cancel_selected' THEN
  PERFORM public.internal_storno_tickets_221(ids);
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN
   PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
 END IF;
 INSERT INTO eshop.stripe_admission_decisions(attempt_id,actor,reason,ticket_ids,provider_revision)
 VALUES(a.id,actor,CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,ids,revision) RETURNING id INTO decision;
 INSERT INTO eshop.orders_history("order",state,price,data) VALUES(o.id,o.state,o.price,jsonb_build_object('action','stripe_partial_refund_decision',
  'decisionId',decision,'actor',actor,'ticketIds',ids,'note',trim(p_note),'providerRevision',revision));
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,v_occasion,'inventory.order.stripe_refund_decision',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','safeLabel','Refund admission decision',
   'changedFields',jsonb_build_array('tickets','admission','allocations'))),before_users,
  jsonb_build_object('decisionId',decision,'payment',public.stripe_order_payment_projection_internal(o.id)));
END $$;
REVOKE ALL ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.decide_stripe_partial_refund_client_sync_v1(bigint,text,bigint[],text,bigint,uuid) TO authenticated;

-- SOURCE: eshop_stripe/admin_detail.sql
CREATE OR REPLACE FUNCTION public.get_stripe_order_admin_detail(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; a eshop.stripe_checkout_attempts; c eshop.stripe_connections; totals record;
 d eshop.stripe_admission_decisions; revision text; note text; tickets jsonb; card_refunded bigint;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.get_is_editor_order_on_occasion(o.occasion),false)
  OR NOT EXISTS(SELECT 1 FROM public.occasions occasion JOIN public.user_info viewer ON viewer.organization=occasion.organization AND viewer.id=auth.uid() WHERE occasion.id=o.occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.payment_method IS DISTINCT FROM 'stripe' THEN RETURN NULL; END IF;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE order_id=o.id ORDER BY created_at DESC LIMIT 1;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor),0) INTO card_refunded FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 SELECT * INTO d FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason IN ('partial_refund_keep','partial_refund_cancel') ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(provider_id,amount_minor) ORDER BY provider_id)::text,'[]'),'sha256'),'hex')
  INTO revision FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund';
 IF d.id IS NOT NULL THEN
  SELECT data->>'note' INTO note FROM eshop.orders_history WHERE "order"=o.id AND data->>'decisionId'=d.id::text ORDER BY created_at DESC LIMIT 1;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',coalesce(t.ticket_symbol,t.id::text),'state',t.state) ORDER BY t.id),'[]'::jsonb)
 INTO tickets FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id;
 RETURN jsonb_build_object('orderId',o.id,'currency',a.currency,'refundedMinor',card_refunded,'amountMinor',a.amount_minor,
  'canDecide',card_refunded>0 AND card_refunded<a.amount_minor AND a.state='paid' AND o.state IN ('paid','sent') AND NOT totals.invalid_identity
   AND a.refund_cursor IS NULL AND a.session_lookup_cursor IS NULL AND pi.id=a.payment_info_id AND pi.stripe_connection_id=a.connection_id,
  'lastSyncedAt',a.last_synced_at,'reconciliationPending',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,
  'decision',CASE WHEN d.id IS NOT NULL THEN jsonb_build_object('action',CASE WHEN d.reason='partial_refund_keep' THEN 'keep' ELSE 'cancel_selected' END,
   'ticketIds',d.ticket_ids,'note',note,'createdAt',d.created_at,'isCurrent',d.provider_revision=revision) END,
  'tickets',tickets,'dashboardUrl',CASE WHEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=a.unit_id AND "user"=auth.uid() AND is_manager)
   THEN 'https://dashboard.stripe.com/'||c.account_id||CASE WHEN a.livemode THEN '' ELSE '/test' END||'/dashboard' END);
END $$;
REVOKE ALL ON FUNCTION public.get_stripe_order_admin_detail(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_stripe_order_admin_detail(bigint) TO authenticated;

-- SOURCE: scanning/projection.sql
-- Set based, minimal projection shared by lookup, search and immutable snapshots.
CREATE OR REPLACE FUNCTION public.scanner_ticket_projection_internal(p_occasion bigint,p_config jsonb,p_ticket bigint DEFAULT NULL)
RETURNS TABLE(ticket_id bigint,dto jsonb) LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH base AS MATERIALIZED (
 SELECT t.*,o.id oid,o.form,o.state order_state,o.updated_at order_updated,o.data order_data,o.note_hidden order_note_hidden,
 pi.amount,pi.paid,public.stripe_ticket_requires_online_internal(t.id) online_required,
 coalesce(td.value,'{}'::jsonb) ticket_data,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders oz ON oz.id=z."order"
 WHERE z.ticket=t.id AND (oz.occasion IS DISTINCT FROM t.occasion OR oz.state IN ('storno','waitlisted','preparing_payment'))) bad_order
 FROM eshop.tickets t
 JOIN LATERAL (SELECT x."order" FROM eshop.order_product_ticket x WHERE x.ticket=t.id ORDER BY x."order" LIMIT 1) x ON true
 JOIN eshop.orders o ON o.id=x."order"
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN LATERAL (SELECT value FROM jsonb_array_elements(coalesce(o.data->'tickets','[]'::jsonb)) WHERE value->>'id'=t.id::text LIMIT 1) td ON true
 WHERE t.occasion=p_occasion AND (p_ticket IS NULL OR t.id=p_ticket)
 ), projected AS (
 SELECT b.*,coalesce(nullif(trim(concat_ws(' ',nullif(trim(b.order_data->>'name'),''),nullif(trim(b.order_data->>'surname'),''))),''),
 (SELECT string_agg(nullif(trim(a.value#>>'{}'),''),' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.order_data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND NOT ff.is_ticket_field WHERE ff.type IN ('name','surname'))) purchaser_name,
 coalesce((SELECT string_agg(a.value#>>'{}',' ' ORDER BY CASE ff.type WHEN 'name' THEN 0 ELSE 1 END)
 FROM jsonb_array_elements(coalesce(b.data->'fields','[]'::jsonb)) e CROSS JOIN LATERAL jsonb_each(e) a
 JOIN public.form_fields ff ON ff.id::text=a.key AND ff.form=b.form AND ff.is_ticket_field WHERE ff.type IN ('name','surname')),
 (SELECT string_agg(v.value#>>'{}',' ' ORDER BY v.key) FROM jsonb_each(b.ticket_data) v WHERE v.key IN ('name','surname')),
 (SELECT concat_ws(' ',u.name,u.surname) FROM public.occasion_users ou JOIN public.user_info u ON u.id=ou."user" WHERE ou.ticket=b.id AND ou.occasion=p_occasion LIMIT 1),b.ticket_symbol) holder_name,
 (b.state IN ('sent','paid','ordered') AND b.ticket_symbol IS NOT NULL AND NOT b.bad_order AND b.order_state NOT IN ('storno','waitlisted','preparing_payment') AND public.stripe_ticket_admission_allowed_internal(b.id)) eligible
 FROM base b)
 SELECT b.id,jsonb_strip_nulls(jsonb_build_object('ticket_id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated_at',b.updated_at,
 'order_id',b.oid,'purchaser_name',b.purchaser_name,'holder_name',b.holder_name,'admission_allowed',coalesce(b.eligible AND (b.state<>'ordered' OR (p_config#>>'{admission,allow_unpaid_online}')::boolean),false),
 'requires_unpaid_confirmation',b.state='ordered','online_required',b.online_required,
 'eligibility_fingerprint',encode(digest(jsonb_build_object('v',1,'id',b.id,'symbol',b.ticket_symbol,'state',b.state,'updated',b.updated_at,
 'parents',(SELECT jsonb_agg(CASE WHEN pi.payment_method='stripe' THEN jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid,pi.returned,pi.payment_method,o.email_payment_version) ELSE jsonb_build_array(o.id,o.state,o.updated_at,pi.amount,pi.paid) END ORDER BY o.id) FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE z.ticket=b.id))::text,'sha256'),'hex'),
 'remaining_amount',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN greatest(0,coalesce(b.amount,0)-coalesce(b.paid,0)) END,
 'order_note',nullif(trim(b.order_data->>'note'),''),'note',nullif(trim(b.note),''),
 'order_note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.order_note_hidden END,
 'note_hidden',CASE WHEN (p_config#>>'{sensitive,hidden_note}')::boolean THEN b.note_hidden END,
 'products',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',p.id,'title',p.title,'short_title',nullif(trim(p.data->>'short_title'),''),'type_id',p.product_type,'type',pt.type,'type_title',pt.title,
 'price',CASE WHEN (p_config#>>'{sensitive,price}')::boolean THEN p.price END)) ORDER BY array_position(ARRAY(SELECT value::text::bigint FROM jsonb_array_elements(p_config#>'{products,order}')),p.id) NULLS LAST,p."order",p.id)
 FROM eshop.products p LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE p.occasion=p_occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=b.id AND z.product=p.id)
 AND ((p_config#>>'{products,mode}')='all' OR ((p_config#>>'{products,mode}')='selected' AND (p_config#>'{products,ids}') @> to_jsonb(ARRAY[p.id])))),'[]'::jsonb),
 'spot',(SELECT s.title FROM eshop.spots s JOIN eshop.order_product_ticket z ON z.id=s.order_product_ticket WHERE z.ticket=b.id ORDER BY s.id LIMIT 1),
 'spot_group',(SELECT jsonb_build_object('blueprint_id',bp.id,'id',g->>'id','title',g->>'title')
 FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket
 JOIN eshop.blueprints bp ON bp.id=sp.blueprint
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(bp.objects,'[]'::jsonb)) obj
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(bp.groups,'[]'::jsonb)) g
 WHERE z.ticket=b.id AND sp.occasion=p_occasion AND obj->>'type'='spot' AND obj->>'id'=sp.id::text AND g->>'id'=obj->>'group'
 AND bp.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) ORDER BY sp.id LIMIT 1),
 'fields',coalesce((SELECT jsonb_agg(jsonb_build_object('key',f->>'key','label',f->>'label','value',
 CASE f->>'source' WHEN 'builtin' THEN CASE f->>'key' WHEN 'holder_name' THEN to_jsonb(b.holder_name) WHEN 'note' THEN to_jsonb(b.note)
 WHEN 'spot' THEN (SELECT to_jsonb(sp.title) FROM eshop.spots sp JOIN eshop.order_product_ticket z ON z.id=sp.order_product_ticket WHERE z.ticket=b.id ORDER BY sp.id LIMIT 1)
 WHEN 'groups' THEN (SELECT jsonb_agg(gi.title ORDER BY gi.id) FROM public.occasion_users ou JOIN public.user_groups ug ON ug."user"=ou."user" JOIN public.user_group_info gi ON gi.id=ug."group" WHERE ou.ticket=b.id AND ou.occasion=p_occasion AND gi.occasion=p_occasion) END
 ELSE (SELECT e->(f->>'field_id') FROM jsonb_array_elements(CASE WHEN f->>'source'='order_field' THEN coalesce(b.order_data->'fields','[]'::jsonb) ELSE coalesce(b.data->'fields','[]'::jsonb) END) e WHERE e ? (f->>'field_id') LIMIT 1) END,
 'missing',CASE WHEN f->>'source'='builtin' THEN false ELSE NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.id=(f->>'field_id')::bigint AND ff.form=b.form) END,
 'hide_empty',coalesce((f->>'hide_empty')::boolean,true),'default_visible',coalesce((f->>'default_visible')::boolean,true)) ORDER BY idx)
 FROM jsonb_array_elements(p_config->'fields') WITH ORDINALITY a(f,idx) WHERE f->>'source'='builtin' OR (f->>'form_id')::bigint=b.form),'[]'::jsonb)))
 FROM projected b;
$$;

-- SOURCE: scanning/admission.sql
-- Parents before ticket, shared by web and retained native/admin writers.
CREATE OR REPLACE FUNCTION public.scanner_lock_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE parents bigint[]; current_parents bigint[]; parent bigint;
BEGIN
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 PERFORM public.lock_order_capacity_scope_internal(parents);
 FOREACH parent IN ARRAY coalesce(parents,ARRAY[]::bigint[]) LOOP
  PERFORM 1 FROM eshop.orders WHERE id=parent FOR UPDATE;
 END LOOP;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO current_parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 IF parents IS DISTINCT FROM current_parents THEN RAISE serialization_failure USING MESSAGE='ticket_parent_changed'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.scanner_admit_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_ticket_is_mutable(p_ticket);
 IF NOT public.stripe_ticket_admission_allowed_internal(p_ticket) THEN RAISE EXCEPTION 'stripe_admission_hold'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket AND state='used') THEN RAISE EXCEPTION 'already_used'; END IF;
 UPDATE eshop.tickets SET state='used',updated_at=clock_timestamp() WHERE id=p_ticket;
END $$;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket(p_session uuid,p_token text,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; tid bigint; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol=p_symbol LIMIT 1;
 IF tid IS NULL AND p_symbol ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
  SELECT t.id INTO tid FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket WHERE ou.occasion=s.occasion_id AND ou."user"=p_symbol::uuid AND t.occasion=s.occasion_id LIMIT 1;
 END IF;
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid) WHERE ticket_id=tid;
 IF result IS NOT NULL THEN result:=result||jsonb_build_object('can_reset_password',public.scanner_can_reset_password_internal(s.occasion_id,tid)); END IF;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' ELSE 'found' END,
 'data',result,'settings_revision',cfg.revision,'server_time',now());
END $$;
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
 AND (strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.sync_scanner_operations(p_session uuid,p_token text,p_operations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; op jsonb; canonical jsonb; h text; prior public.scanner_operations;
 tid bigint; proj jsonb; receipt jsonb; outcome text; reason text; results jsonb:='[]'; existing boolean; snap public.scanner_snapshots;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF p_operations IS NULL OR jsonb_typeof(p_operations)<>'array' OR jsonb_array_length(p_operations) NOT BETWEEN 1 AND 50 OR octet_length(p_operations::text)>262144 THEN
  RETURN jsonb_build_object('code',400,'reason','invalid_batch','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 FOR op IN SELECT value FROM jsonb_array_elements(p_operations) LOOP
  IF op->>'action' IS DISTINCT FROM 'admit_ticket' OR op->>'origin_session_id' IS DISTINCT FROM p_session::text
   OR op->>'eligibility_fingerprint' IS NULL OR length(op->>'eligibility_fingerprint')<>64
   OR op->>'operation_id' IS NULL OR op->>'ticket_id' IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_operation'; END IF;
  tid:=(op->>'ticket_id')::bigint;
  canonical:=jsonb_build_object('operation_id',(op->>'operation_id')::uuid,'origin_session_id',p_session,'occasion_id',s.occasion_id,
   'ticket_id',tid,'action','admit_ticket','snapshot_id',op->'snapshot_id','settings_revision',op->'settings_revision',
   'eligibility_fingerprint',op->'eligibility_fingerprint','confirm_unpaid',coalesce((op->>'confirm_unpaid')::boolean,false),'captured_at',op->'captured_at');
  h:=encode(digest(canonical::text,'sha256'),'hex');
  -- Serializes global identity before any domain mutation. No incomplete receipt survives a transaction.
  PERFORM pg_advisory_xact_lock(hashtextextended(op->>'operation_id',5317));
  SELECT * INTO prior FROM public.scanner_operations WHERE operation_id=(op->>'operation_id')::uuid;
  IF FOUND THEN
   IF prior.session_id<>p_session OR prior.payload_hash<>h THEN
    results:=results||jsonb_build_array(jsonb_build_object('operation_id',op->>'operation_id','outcome','rejected','reason','operation_payload_mismatch'));
   ELSE results:=results||jsonb_build_array(prior.receipt||jsonb_build_object('replayed',true)); END IF;
   CONTINUE;
  END IF;
  IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN
   RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now());
  END IF;
  outcome:='rejected'; reason:='not_found'; proj:=NULL;
  IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid AND occasion=s.occasion_id) THEN
   PERFORM public.scanner_lock_ticket_internal(tid);
   PERFORM public.check_occasion_writable(s.occasion_id);
   SELECT dto INTO proj FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid);
   IF op->>'snapshot_id' IS NOT NULL AND coalesce((proj->>'online_required')::boolean,false) THEN reason:='online_required';
   ELSIF proj->>'state'='used' THEN outcome:='conflict'; reason:='already_used';
   ELSIF proj->>'state' IN ('storno','waitlisted') OR NOT coalesce((proj->>'admission_allowed')::boolean,false) THEN reason:='admission_not_allowed';
   ELSIF proj->>'eligibility_fingerprint' IS DISTINCT FROM op->>'eligibility_fingerprint' THEN outcome:='conflict'; reason:='eligibility_changed';
   ELSIF (proj->>'requires_unpaid_confirmation')::boolean AND (NOT coalesce((op->>'confirm_unpaid')::boolean,false) OR op->>'snapshot_id' IS NOT NULL) THEN reason:='unpaid_confirmation_required';
   ELSE
    reason:='admitted'; outcome:='accepted';
    IF op->>'snapshot_id' IS NOT NULL THEN
     SELECT * INTO snap FROM public.scanner_snapshots WHERE id=(op->>'snapshot_id')::uuid AND session_id=p_session;
     IF snap.id IS NULL OR snap.expires_at<=now() OR s.offline_until<=now() OR NOT EXISTS(
      SELECT 1 FROM public.scanner_snapshot_pages pg CROSS JOIN LATERAL jsonb_array_elements(pg.payload_text::jsonb) item
      WHERE pg.snapshot_id=snap.id AND item->>'ticket_id'=tid::text AND item->>'eligibility_fingerprint'=op->>'eligibility_fingerprint') THEN
      outcome:='conflict'; reason:='offline_grant_invalid'; END IF;
    END IF;
    IF outcome='accepted' THEN
     PERFORM public.scanner_admit_ticket_internal(tid);
    END IF;
   END IF;
  END IF;
  receipt:=jsonb_build_object('operation_id',op->>'operation_id','ticket_id',tid,'outcome',outcome,'reason',reason,
   'committed_at',clock_timestamp(),'eligibility_fingerprint',op->>'eligibility_fingerprint');
  INSERT INTO public.scanner_operations(operation_id,session_id,occasion_id,ticket_id,payload_hash,payload,receipt)
   VALUES((op->>'operation_id')::uuid,p_session,s.occasion_id,tid,h,canonical,receipt);
  results:=results||jsonb_build_array(receipt);
 END LOOP;
 RETURN jsonb_build_object('code',200,'data',results,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_receipts(p_session uuid,p_token text,p_operation_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token,true);
 IF coalesce(array_length(p_operation_ids,1),0)>50 THEN RAISE invalid_parameter_value; END IF;
 -- Expired/revoked devices can reconcile their immutable history, never perform a new write.
 SELECT coalesce(jsonb_agg(receipt),'[]'::jsonb) INTO result FROM public.scanner_operations WHERE session_id=p_session AND operation_id=ANY(p_operation_ids);
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_summary(p_session uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 WITH eligible AS MATERIALIZED (
 SELECT t.id,t.state FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol IS NOT NULL
 AND t.state IN ('used','paid','sent','ordered') AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=t.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id AND (o.state IN ('storno','waitlisted','preparing_payment') OR o.occasion<>s.occasion_id)))
 SELECT jsonb_build_object('used_current',count(*) FILTER(WHERE state='used'),'unused_eligible',count(*) FILTER(WHERE state IN ('paid','sent')),
 'eligible_total',count(*) FILTER(WHERE state IN ('used','paid','sent')),'unpaid_conditional',count(*) FILTER(WHERE state='ordered'),
 'definition_version',1,'definition','used + paid/sent; excludes conditional unpaid, cancelled and waitlisted',
 'server_time',now(),'settings_revision',(SELECT revision FROM public.scanner_settings WHERE occasion_id=s.occasion_id)) INTO result FROM eligible;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.resolve_scanner_conflict(p_operation uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE op public.scanner_operations;
BEGIN
 SELECT * INTO STRICT op FROM public.scanner_operations WHERE operation_id=p_operation;
 PERFORM public.check_is_editor_order_on_occasion(op.occasion_id);
 IF auth.uid() IS NULL OR op.receipt->>'outcome'<>'conflict' THEN RAISE insufficient_privilege; END IF;
 INSERT INTO public.scanner_conflict_resolutions(operation_id,actor_user_id,reason) VALUES(p_operation,auth.uid(),p_reason) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;

-- SOURCE: eshop_orders/scan_ticket.sql
CREATE OR REPLACE FUNCTION public.scan_ticket(scanned_id TEXT, scanned_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ticket_row RECORD;
    order_json JSONB;
    products_json JSONB;
    spot_json JSONB;
    groups_json JSONB; -- New variable for groups
    order_id BIGINT;
    occasion_id BIGINT;
    hide_price BOOLEAN := FALSE;
    target_user_id UUID; -- New variable to store the resolved User ID
    expected_scan_code TEXT;
    is_uuid BOOLEAN;
    -- Deposit info variables
    v_deposit_amount NUMERIC;
    v_paid NUMERIC;
    v_amount NUMERIC;
    v_deposit_deadline_days INT;
    v_deposit_deadline TEXT;
    v_occ_start_time TIMESTAMPTZ;
    v_occ_features JSONB;
    v_deposit_feature JSONB;
    v_deposit_info JSONB;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1((SELECT occasion FROM eshop.tickets WHERE ticket_symbol=scanned_id LIMIT 1)) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    -----------------------------------------------------
    -- 1. Attempt to find ticket by Ticket Symbol
    -----------------------------------------------------
    SELECT *
      INTO ticket_row
    FROM eshop.tickets
    WHERE ticket_symbol = scanned_id
    LIMIT 1;

    -----------------------------------------------------
    -- 1.a. Fallback: Scan by User ID if Ticket Symbol not found
    -----------------------------------------------------
    IF ticket_row IS NULL THEN
        -- Check if the scanned_id is a valid UUID format
        is_uuid := scanned_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

        IF is_uuid THEN
            -- If scanned by UUID, we know the user immediately
            target_user_id := scanned_id::UUID;

            SELECT t.*
              INTO ticket_row
            FROM public.occasion_users ou
            JOIN public.occasions o ON ou.occasion = o.id
            JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
            JOIN eshop.tickets t ON ou.ticket = t.id
            WHERE ou.user = target_user_id
              AND oh.secret = scanned_code
            LIMIT 1;
        END IF;
    END IF;

    -----------------------------------------------------
    -- 1.b. Final Check if Ticket is still missing
    -----------------------------------------------------
    IF ticket_row IS NULL OR ticket_row.state='waitlisted' OR ticket_row.ticket_symbol IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket or User with valid ticket not found');
    END IF;

    -----------------------------------------------------
    -- 2. Retrieve the associated order ID
    -----------------------------------------------------
    SELECT opt."order" INTO order_id
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ticket_row.id
    LIMIT 1;

    IF order_id IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code', 404, 'message', 'Order for ticket not found');
    END IF;

    -----------------------------------------------------
    -- 3. Retrieve the occasion ID from the order
    -----------------------------------------------------
    SELECT o.occasion, NOT coalesce((ss.config#>>'{sensitive,price}')::boolean,true)
      INTO occasion_id, hide_price
    FROM eshop.orders o
    JOIN public.occasions occ ON occ.id = o.occasion
    LEFT JOIN public.scanner_settings ss ON ss.occasion_id=occ.id
    WHERE o.id = order_id
    LIMIT 1;

    PERFORM public.check_occasion_writable(occasion_id);
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion for order not found');
    END IF;

    -----------------------------------------------------
    -- 3.b. Resolve User ID if not already found via UUID scan
    -----------------------------------------------------
    -- If we found the ticket via Symbol (Step 1), we need to find who holds it
    IF target_user_id IS NULL THEN
        SELECT "user" INTO target_user_id
        FROM public.occasion_users
        WHERE ticket = ticket_row.id
          AND occasion = occasion_id
        LIMIT 1;
    END IF;

    -----------------------------------------------------
    -- 4. Retrieve the expected scan_code
    -----------------------------------------------------
    SELECT oh.secret
      INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    IF expected_scan_code IS NULL THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion');
    END IF;

    -----------------------------------------------------
    -- 5. Validate the scanned_code
    -----------------------------------------------------
    IF scanned_code IS DISTINCT FROM expected_scan_code THEN
        PERFORM public.admit_scan_access_v1(occasion_id,false);
        RETURN jsonb_build_object('code', 401, 'message', 'Scan code is not correct');
    END IF;

    -----------------------------------------------------
    -- 6. Fetch order, products, spot, AND GROUPS
    -----------------------------------------------------

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    IF NOT public.stripe_ticket_admission_allowed_internal(ticket_row.id) THEN
        RETURN jsonb_build_object('code',403,'message','stripe_admission_hold');
    END IF;

    -- A. Fetch Order
    SELECT CASE
             WHEN hide_price THEN
               (to_jsonb(o) - 'price') || jsonb_build_object(
                 'data',
                 CASE
                   WHEN jsonb_typeof(o.data->'tickets') = 'array' THEN
                     jsonb_set(
                       o.data,
                       '{tickets}',
                       COALESCE(
                         (
                           SELECT jsonb_agg(
                             CASE
                               WHEN jsonb_typeof(ticket->'products') = 'array' THEN
                                 jsonb_set(
                                   ticket,
                                   '{products}',
                                   COALESCE(
                                     (
                                       SELECT jsonb_agg(product - 'price')
                                       FROM jsonb_array_elements(ticket->'products') AS product
                                     ),
                                     '[]'::jsonb
                                   ),
                                   FALSE
                                 )
                               ELSE ticket
                             END
                           )
                           FROM jsonb_array_elements(o.data->'tickets') AS ticket
                         ),
                         '[]'::jsonb
                       ),
                       FALSE
                     )
                   ELSE o.data
                 END
               )
             ELSE to_jsonb(o)
           END
      INTO order_json
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- B. Fetch Products
    SELECT jsonb_agg(
             CASE
               WHEN hide_price THEN
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
               ELSE
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'price', p.price,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
             END
           )
      INTO products_json
    FROM eshop.products p
    WHERE p.id IN (
        SELECT opt.product
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    );

    -- C. Fetch Spot
    SELECT row_to_json(s) INTO spot_json
    FROM eshop.spots s
    WHERE s.order_product_ticket IN (
        SELECT opt.id
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    )
    LIMIT 1;

    -- D. Fetch User Groups (New Logic)
    IF target_user_id IS NOT NULL THEN
        -- We construct a JSON object compatible with UserGroupInfoModel
        -- We join user_groups -> user_group_info -> places to get full context
        SELECT jsonb_agg(
                 to_jsonb(ugi) ||
                 jsonb_build_object(
                    'place_object', row_to_json(p)
                 )
               )
        INTO groups_json
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ug."group" = ugi.id
        LEFT JOIN public.places p ON ugi.place = p.id
        WHERE ug."user" = target_user_id
          AND ugi.occasion = occasion_id;
    END IF;

    -----------------------------------------------------
    -- 6E. Fetch deposit info for deposit orders
    -----------------------------------------------------
    SELECT pi.deposit_amount, pi.paid, pi.amount
    INTO v_deposit_amount, v_paid, v_amount
    FROM eshop.payment_info pi
    JOIN eshop.orders o ON o.payment_info = pi.id
    WHERE o.id = order_id;

    IF v_deposit_amount IS NOT NULL THEN
        -- Get occasion features and start_time for deposit deadline
        SELECT occ.features, occ.start_time
        INTO v_occ_features, v_occ_start_time
        FROM public.occasions occ
        WHERE occ.id = occasion_id;

        -- Read deposit deadline from deposit feature in features JSONB
        SELECT elem INTO v_deposit_feature
        FROM jsonb_array_elements(v_occ_features) elem
        WHERE elem->>'code' = 'deposit';

        v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
        v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

        v_deposit_info := jsonb_build_object(
            'remaining_amount', GREATEST(0, COALESCE(v_amount, 0) - COALESCE(v_paid, 0)),
            'is_fully_paid', COALESCE(v_paid, 0) >= COALESCE(v_amount, 0),
            'deadline_type', CASE
                WHEN v_deposit_deadline = 'on_site' THEN 'on_site'
                WHEN v_deposit_deadline_days IS NOT NULL THEN 'date'
                ELSE NULL
            END,
            'deadline_date', CASE
                WHEN v_deposit_deadline_days IS NOT NULL AND v_deposit_deadline IS DISTINCT FROM 'on_site'
                THEN (v_occ_start_time - make_interval(days => v_deposit_deadline_days))::text
                ELSE NULL
            END,
            'deposit_amount', v_deposit_amount,
            'total_amount', v_amount,
            'paid_amount', COALESCE(v_paid, 0)
        );
    END IF;

    -----------------------------------------------------
    -- 7. Return the compiled JSONB response
    -----------------------------------------------------
    RETURN jsonb_build_object(
        'code', 200,
        'ticket', to_jsonb(ticket_row)||jsonb_build_object('online_required',public.stripe_ticket_requires_online_internal(ticket_row.id)),
        'order', order_json,
        'products', products_json,
        'spot', spot_json,
        'groups', COALESCE(groups_json, '[]'::jsonb),
        'deposit_info', v_deposit_info
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;

-- SOURCE: eshop_orders/get_all_tickets_for_scan.sql
CREATE OR REPLACE FUNCTION public.get_all_tickets_for_scan(scan_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id_val bigint;
    result jsonb; policy jsonb; max_items bigint; max_bytes bigint; found_items bigint;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1(NULL) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    SELECT o.id
    INTO occasion_id_val
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF occasion_id_val IS NULL THEN
         PERFORM public.admit_scan_access_v1(NULL,false);
         RETURN jsonb_build_object('code',401,'message','invalid_scan_code');
    END IF;

    IF NOT public.admit_scan_access_v1(occasion_id_val,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    policy:=public.abuse_effective_rules_v1('scan.export',(SELECT unit FROM public.occasions WHERE id=occasion_id_val),(SELECT organization FROM public.occasions WHERE id=occasion_id_val));
    SELECT (r->>'base_limit')::bigint INTO max_items FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.items';
    SELECT (r->>'base_limit')::bigint INTO max_bytes FROM jsonb_array_elements(policy->'rules') r WHERE r->>'rule_key'='scan.export.bytes';
    IF max_items IS NULL OR max_bytes IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
    SELECT count(*) INTO found_items FROM (SELECT id FROM eshop.tickets WHERE occasion=occasion_id_val LIMIT max_items+1) bounded;
    IF found_items>max_items THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', t.id,
            'ticket_symbol', t.ticket_symbol,
            'state', t.state,
            'related_order', jsonb_build_object(
                 'data', t.data
            )
        ) 
    )
    INTO result
    FROM (
        SELECT DISTINCT ON (t.id) t.id, t.ticket_symbol, t.state, o.data
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE o.occasion = occasion_id_val
          AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'
          AND t.ticket_symbol IS NOT NULL AND o.state IS DISTINCT FROM 'waitlisted'
          AND NOT public.stripe_ticket_requires_online_internal(t.id)
        ORDER BY t.id
    ) t;

    IF octet_length(result::text)>max_bytes THEN RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded'); END IF;
    RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- SOURCE: eshop_orders/update_order_and_tickets_to_paid.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id FOR UPDATE;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
      WHERE o.id=order_id AND pi.payment_method='stripe' AND NOT EXISTS(
        SELECT 1 FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id
        WHERE a.order_id=o.id AND m.kind='payment' AND m.amount_minor=a.amount_minor
          AND m.connection_id=pi.stripe_connection_id AND m.occurred_at<=a.reservation_expires_at)) THEN
      RETURN jsonb_build_object('code',409,'message','STRIPE_PROVIDER_PAYMENT_REQUIRED');
    END IF;

    -- Check if the order is in 'ordered' or 'created' state before proceeding
    IF current_state='expired' AND EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info
      WHERE o.id=order_id AND p.payment_method='stripe') THEN
      RETURN jsonb_build_object('code',409,'message','Stripe reservation was released');
    END IF;
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now(),email_payment_version=email_payment_version+1
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state IN ('ordered','expired','paid');

    -- Queue deposit-paid or fully-paid email for orders with deposit
    DECLARE
        v_deposit_amount NUMERIC;
        v_total_amount NUMERIC;
        v_total_paid NUMERIC;
        v_email_code TEXT;
        v_org_id BIGINT;
        v_unit_id BIGINT;
    BEGIN
        -- Fetch payment info for this order
        SELECT pi.deposit_amount, pi.amount, pi.paid
        INTO v_deposit_amount, v_total_amount, v_total_paid
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        WHERE o.id = order_id;

        -- Only queue emails for deposit orders. The template handler branches
        -- internally on amountPaid >= totalAmount to render either the
        -- deposit-paid copy (with remaining balance + QR) or the fully-paid copy.
        IF v_deposit_amount IS NOT NULL AND v_total_paid >= v_deposit_amount THEN
            -- Get organization and unit from occasion
            SELECT occ.organization, occ.unit
            INTO v_org_id, v_unit_id
            FROM public.occasions occ
            WHERE occ.id = occasion_id;

            v_email_code := 'TICKET_ORDER_PAYMENT_DONE';

            IF v_email_code IS NOT NULL THEN
                PERFORM public.enqueue_order_email(v_email_code,jsonb_build_object('order_id',order_id),v_org_id,occasion_id,v_unit_id);
            END IF;
        END IF;
    END;

    PERFORM public.enqueue_paid_order_tickets(order_id);

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;

-- SOURCE: eshop_orders/recalculate_order_payment_status.sql
CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_deposit_amount numeric;
    v_price numeric;
    v_state text;
    v_transition jsonb;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Card refunds/holds never create a new debt or resurrect expired capacity.
    -- Their current provider facts are applied by the atomic Stripe ingest.
    IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND payment_method='stripe') THEN RETURN; END IF;

    -- Get Paid Amount and Deposit Amount from Payment Info
    SELECT paid, deposit_amount INTO v_paid, v_deposit_amount
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    IF COALESCE(v_paid, 0) >= COALESCE(v_deposit_amount, v_price) THEN
        -- Fully Paid (or Deposit Paid) -> Move to Paid
        IF v_state != 'paid' AND (v_state = 'ordered' OR v_state = 'created' OR v_state = 'expired') THEN
             -- The legacy JSON boundary reports failures instead of raising.
             -- Propagate them so payment, order, ticket intent and webhook receipt
             -- cannot commit independently of the canonical paid transition.
             v_transition := public.update_order_and_tickets_to_paid(p_order_id);
             IF (v_transition->>'code') IS DISTINCT FROM '200' THEN
                 RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                     COALESCE(v_transition->>'message','invalid transition receipt');
             END IF;
        END IF;
    ELSE
        -- Underpaid -> Revert to Ordered (if currently Paid)
        IF v_state IN ('paid','sent') THEN
            PERFORM public.cancel_order_email_intents(p_order_id);
            -- Revert Order
            UPDATE eshop.orders
            SET state = 'ordered', updated_at = now(),email_payment_version=email_payment_version+1
            WHERE id = p_order_id;

            -- Revert Tickets (only those that are 'paid')
            UPDATE eshop.tickets
            SET state = 'ordered', updated_at = now() -- Reverted to 'ordered' as 'valid' is not a supported state

            FROM eshop.order_product_ticket
            WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
            AND eshop.order_product_ticket."order" = p_order_id
            AND eshop.tickets.state IN ('paid','sent');
        END IF;
    END IF;
END;
$$;

-- SOURCE: eshop/finalize_ticket_order.sql
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
    v_payment_method text;
    v_stripe_connection uuid;
    v_stripe_attempt uuid;
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

        form_deadline_duration := COALESCE(form_deadline_duration,
            (SELECT (elem->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) elem WHERE elem->>'code'='form'),604800);

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

        order_data := input_data - 'ticket' - 'stripePaymentSource' || JSONB_BUILD_OBJECT('tickets', public.order_tickets_with_seating_internal(order_id, ticket_details));

        v_payment_method:=coalesce(input_data->>'payment_method','bank');
        IF v_payment_method NOT IN ('bank','stripe') THEN RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
        IF calculated_price=0 THEN v_payment_method:='bank'; END IF;
        IF calculated_price=0 THEN
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at) VALUES(0,first_currency_code,now) RETURNING id INTO payment_info_id;
        ELSIF v_payment_method='stripe' THEN
          IF coalesce(input_data->>'payment_type','full')<>'full' OR v_total_deposit>0 THEN
            RAISE EXCEPTION 'STRIPE_DEPOSIT_UNSUPPORTED'; END IF;
          v_stripe_connection:=public.assert_stripe_form_payable_internal(form_id,
            (input_data->>'stripe_connection_id')::uuid,input_data->>'payment_surface');
          IF (input_data->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM calculated_price*100
            OR input_data->>'expected_payment_currency' IS DISTINCT FROM first_currency_code::text THEN
            RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','STRIPE_PRICE_CHANGED','message','Order price changed. Review the order before paying.')::text;
          END IF;
          IF first_currency_code NOT IN ('CZK','EUR','PLN','USD','GBP') OR calculated_price*100<>trunc(calculated_price*100) THEN
            RAISE EXCEPTION 'STRIPE_AMOUNT_UNSUPPORTED'; END IF;
          bank_account_id:=NULL;
          INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method,stripe_connection_id)
          VALUES(calculated_price,first_currency_code,now,'stripe',v_stripe_connection) RETURNING id INTO payment_info_id;
        ELSE
          IF calculated_price>0 AND coalesce(form_data#>'{payments,bankEnabled}','true'::jsonb)<>'true'::jsonb THEN
            RAISE EXCEPTION 'BANK_PAYMENT_NOT_CONFIGURED'; END IF;
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

          -- Calculate deadline if deadline duration is provided
          IF v_payment_method='stripe' THEN
              v_stripe_attempt:=public.create_stripe_order_attempt_internal(order_id);
              SELECT reservation_expires_at INTO deadline FROM eshop.stripe_checkout_attempts WHERE id=v_stripe_attempt;
          ELSIF form_deadline_duration IS NOT NULL THEN
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
                v_reminder_interval BIGINT;
                v_reminder_is_enabled BOOLEAN;
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

                    -- Only queue reminder if deadline is in the future
                    IF v_deposit_deadline_ts > NOW() THEN
                        -- Get reminder interval from occasion form feature
                        SELECT COALESCE((form_data->>'reminder_interval_seconds')::bigint, (elem->>'reminder_interval_seconds')::bigint,86400)
                        INTO v_reminder_interval
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        -- Check if reminder is enabled on the form feature
                        SELECT (elem->>'is_enabled')::boolean AND COALESCE((form_data->>'is_reminder_enabled')::boolean,(elem->>'reminder_is_enabled')::boolean,true)
                        INTO v_reminder_is_enabled
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        IF COALESCE(v_reminder_is_enabled, FALSE) AND v_reminder_interval IS NOT NULL THEN
                            PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',
                                jsonb_build_object('order_id',order_id,'is_deposit_reminder',true),organization_id,occasion_id,unit_id,
                                v_deposit_deadline_ts-make_interval(secs=>v_reminder_interval));
                        END IF;
                    END IF;
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
            'payment',public.stripe_order_payment_projection_internal(order_id),
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
            WHEN SQLERRM = 'STRIPE_RECIPIENT_CHANGED' THEN
                JSONB_BUILD_OBJECT('code',409,'errorCode','STRIPE_RECIPIENT_CHANGED',
                    'message','The payment recipient changed. Review the current form.')
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_orders/create_ticket_order_client_sync_v1.sql
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
    'occasion',v_occasion,'order',p_order-'stripePaymentSource')::text,'UTF8'),'sha256'),'hex');
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
  v_result:=public.create_ticket_order_internal_v1(p_order-'stripePaymentSource');
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN COALESCE((v_result->>'code')::integer,500) BETWEEN 100 AND 599
        THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  IF v_result#>>'{order,payment_info,payment_method}'='stripe' THEN
    PERFORM public.attach_stripe_order_pay_source_internal((v_result#>>'{order,id}')::bigint,p_command_id,p_order->'stripePaymentSource');
  END IF;
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

-- SOURCE: eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash','stripepaymentsource');
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
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',p_payload#-'{orderDetails,stripePaymentSource}','actor',p_actor)::text,'sha256'),'hex');
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

-- SOURCE: eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer;
BEGIN
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
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
 result:=public.finalize_ticket_order_internal_v1(target,input-'stripePaymentSource',true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 IF result#>>'{order,payment_info,payment_method}'='stripe' THEN
  PERFORM public.attach_stripe_order_pay_source_internal(target,p_command,input->'stripePaymentSource');
 END IF;
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

-- SOURCE: eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic
        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Ensure user is authorized to edit this occasion
        IF NOT COALESCE(get_is_editor_order_on_occasion(occasion_id), false) THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 403, 'message', 'User is not authorized to edit this occasion')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT (public.get_is_editor_on_unit(occasion_unit) OR public.get_is_editor_on_occasion(occasion_id)) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        form_id := NULLIF(input_data->>'id','')::bigint;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);
        DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion'
          AND scope_id=occasion_id AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(deleted_products) id));

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                field_id := NULLIF(field_data->>'id', '')::BIGINT;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    PERFORM public.advance_ticketing_authoring_version_internal_v1('product_type',occasion_id,product_type_id);
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            PERFORM public.advance_ticketing_authoring_version_internal_v1('product',occasion_id,product_id);
                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = field_data->'data',
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = field_product_type,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        IF (input_data->'data'->>'reminder_interval_seconds')::bigint < 0 THEN
            RAISE EXCEPTION 'reminder_interval_seconds must be zero or higher or null';
        END IF;
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        IF input_data->>'blueprint' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM eshop.blueprints WHERE id=(input_data->>'blueprint')::bigint AND occasion=occasion_id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',403,'message','Foreign blueprint')::text; END IF;
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
               data = CASE WHEN input_data ? 'data' THEN input_data->'data' ELSE data END,
               header = CASE WHEN input_data ? 'header' THEN input_data->>'header' ELSE header END,
               header_off = CASE WHEN input_data ? 'header_off' THEN input_data->>'header_off' ELSE header_off END,
               link = link_param,
               blueprint = CASE WHEN input_data ? 'blueprint' THEN NULLIF(input_data->>'blueprint','')::BIGINT ELSE blueprint END,
               bank_account = CASE WHEN input_data ? 'bank_account' THEN bank_account_val ELSE bank_account END,
               deadline_duration_seconds = CASE WHEN input_data ? 'deadline_duration_seconds' THEN deadline_val ELSE deadline_duration_seconds END,
               is_open = CASE WHEN input_data ? 'is_open' THEN (input_data->>'is_open')::boolean ELSE is_open END
         WHERE id = form_id;

        PERFORM public.validate_form_payment_configuration_internal(form_id);

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

    EXCEPTION WHEN raise_exception THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'organizationIdentity', (SELECT CASE WHEN o.organization=u.organization THEN public.get_verified_unit_identity_internal(u.id) END FROM public.occasions o JOIN public.units u ON u.id=o.unit WHERE o.id=f.occasion),
                'header_off', f.header_off,
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'organizationIdentity', CASE WHEN o.organization=(SELECT organization FROM public.units WHERE id=o.unit) THEN public.get_verified_unit_identity_internal(o.unit) END,
            'payments',public.form_payment_availability_internal(f.id),
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', CASE WHEN EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
                AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)'))
                THEN f.blueprint END,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal(public.resolve_form_link_internal(form_link),false);
$$;

-- SOURCE: eshop_forms/duplicate_form_to_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion_internal_v1(
    source_form_id BIGINT,
    target_occasion_link TEXT
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE id = public.resolve_occasion_link_internal(target_occasion_link);
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    PERFORM public.check_occasion_writable(target_occasion_id);

    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = source_occasion_id AND "user" = user_id AND is_editor_view = TRUE
    ) OR EXISTS (
        SELECT 1 FROM public.unit_users
        WHERE unit = source_unit_id AND "user" = user_id AND is_editor_view = TRUE
    )
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = target_occasion_id AND "user" = user_id AND is_editor = TRUE
    )
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        public.copy_occasion_title_internal(title,'en'),
        CASE WHEN source_unit_id IS DISTINCT FROM (SELECT unit FROM public.occasions WHERE id=target_occasion_id)
          THEN data #- '{payments,stripeConnectionId}' ELSE data END,
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        is_open,
        NULL,
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,NULL,true) WHERE id=new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    RETURN new_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(source_form_id bigint,target_occasion_link text)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.duplicate_form_to_occasion_client_sync_v1(source_form_id,target_occasion_link,gen_random_uuid())#>>'{data,formId}')::bigint;
$$;
REVOKE ALL ON FUNCTION public.duplicate_form_to_occasion(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form_to_occasion(bigint,text) TO authenticated;

-- SOURCE: eshop_payment_references/replay.sql
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
   IF payment.payment_method='stripe' THEN
    payload:=payload||jsonb_build_object('payment',public.stripe_order_payment_projection_internal(target.id));
   END IF;
  END IF;
 END IF;
 IF p_response ? 'data' THEN RETURN jsonb_set(p_response,'{data}',payload); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.project_local_payment_reference_order_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_waitlist/order_overview.sql
-- Private pure projection. No matcher, paid transition or payment side effect.
CREATE OR REPLACE FUNCTION public.customer_order_payment_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH facts AS (
 SELECT o.*,p.payment_method,p.amount,coalesce(p.paid,0) received,coalesce(p.returned,0) returned,
 p.deposit_amount,p.deposit_deadline,p.deadline,p.variable_symbol,p.creditor_reference,
 b.account_number,b.account_number_human_readable,
 CASE WHEN o.state='preparing_payment' THEN 'preparing'
 WHEN o.state='storno' THEN 'cancelled'
 WHEN o.state='waitlisted' AND p.id IS NULL THEN 'not_required_yet'
 WHEN o.price=0 THEN 'free'
 WHEN p.id IS NULL OR p.currency_code IS DISTINCT FROM o.currency_code OR p.amount IS NULL OR p.amount<0 OR coalesce(p.paid,0)<0 OR coalesce(p.paid_externally,0)<>0
  OR (o.state IN ('paid','sent') AND o.price>0 AND coalesce(p.paid,0)=0) THEN 'unknown'
 WHEN coalesce(p.paid,0)>=p.amount THEN 'fully_paid'
 WHEN coalesce(p.paid,0)=0 THEN 'unpaid'
 WHEN p.deposit_amount>0 AND p.paid>=p.deposit_amount THEN 'deposit_paid'
 ELSE 'partially_paid' END status
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order),
 due AS (SELECT *,greatest(amount-received,0) outstanding,
 CASE WHEN deposit_amount>received THEN greatest(deposit_amount-received,0) ELSE greatest(amount-received,0) END due_now,
 CASE WHEN deposit_amount>received THEN deposit_deadline ELSE deadline END due_at FROM facts)
 SELECT CASE WHEN payment_method='stripe' THEN public.stripe_order_payment_projection_internal(p_order) ELSE jsonb_build_object('status',status,'amount',amount,'received',received,'returned',returned,
 'totalOutstanding',outstanding,'overpaid',greatest(received-amount,0),'depositAmount',deposit_amount,
 'depositDeadline',deposit_deadline,'finalDeadline',deadline,
 'dueNow',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN due_now ELSE 0 END,
 'dueAt',due_at,'overdue',coalesce(due_at<statement_timestamp() AND due_now>0,false),
 'instructionsAvailable',status IN ('unpaid','partially_paid','deposit_paid') AND account_number IS NOT NULL
  AND CASE WHEN currency_code='EUR' THEN creditor_reference IS NOT NULL ELSE variable_symbol IS NOT NULL END,
 'reference',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN
  CASE WHEN currency_code='EUR' THEN creditor_reference ELSE variable_symbol::text END END,
 'referenceKind',CASE WHEN currency_code='EUR' THEN 'RF' ELSE 'VS' END,
 'publicAccount',CASE WHEN status IN ('unpaid','partially_paid','deposit_paid') THEN coalesce(account_number_human_readable,account_number) END)
 END FROM due;
$$;
REVOKE ALL ON FUNCTION public.customer_order_payment_internal(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.customer_ticket_label_internal(p_ticket bigint,p_form bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT nullif(string_agg(a.value#>>'{}',' ' ORDER BY CASE f.type WHEN 'name' THEN 0 ELSE 1 END,f.id),'')
 FROM eshop.tickets t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t.data->'fields','[]')) field
 CROSS JOIN LATERAL jsonb_each(field) a JOIN public.form_fields f ON f.id::text=a.key
 WHERE t.id=p_ticket AND f.form=p_form AND f.is_ticket_field AND NOT f.is_hidden AND f.type IN ('name','surname');
$$;
REVOKE ALL ON FUNCTION public.customer_ticket_label_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_customer_order_overview(p_token text,p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE root eshop.orders; cap eshop.waitlist_capabilities; occ public.occasions; f public.forms;
 ids bigint[]; result jsonb;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO root FROM eshop.orders WHERE id=p_order_id AND source_waitlist_order_id IS NULL;
 SELECT * INTO occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 SELECT * INTO cap FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND kind='order_view' AND order_id=root.id AND form_id=f.id AND organization_id=occ.organization
 AND revoked_at IS NULL AND expires_at>statement_timestamp();
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' OR cap.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT array_agg(id) INTO ids FROM eshop.orders WHERE id=root.id OR (source_waitlist_order_id=root.id AND NOT (
  NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=eshop.orders.id)
  AND EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=eshop.orders.id AND source_order_id=root.id AND state='aborted')));
 -- Reject malformed provenance rather than expanding an apparently related scope.
 IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(ids) AND (o.form IS DISTINCT FROM f.id OR o.occasion IS DISTINCT FROM occ.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.tickets t ON t.id=x.ticket WHERE x."order"=ANY(ids)
  AND (t.occasion<>occ.id OR EXISTS(SELECT 1 FROM eshop.order_product_ticket y WHERE y.ticket=t.id AND y."order" IS DISTINCT FROM x."order")))
 OR EXISTS(SELECT 1 FROM eshop.orders o WHERE o.source_waitlist_order_id=root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  JOIN eshop.order_product_ticket x ON x.ticket=s.ticket_id AND x."order"=o.id
  WHERE w.order_id=root.id AND w.form_id=f.id AND s.form_id=f.id AND s.outcome='accepted' AND s.resulting_order_id=o.id))
 OR EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=ANY(ids) AND x."order"<>root.id AND NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.ticket_id=x.ticket AND s.resulting_order_id=x."order" AND s.outcome='accepted' AND w.order_id=root.id AND w.form_id=f.id))
 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT jsonb_build_object('code',200,'root',jsonb_build_object('id',root.id,'symbol',root.order_symbol,'title',occ.title,'formLink',f.link,'hasTickets',EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(occ.features,'[]')) feature WHERE feature->>'code'='ticket' AND feature->>'is_enabled'='true')),
 'organizationIdentity',CASE WHEN occ.organization=(SELECT organization FROM public.units WHERE id=occ.unit) THEN public.get_verified_unit_identity_internal(occ.unit) END,
 'serverTime',statement_timestamp(),'accessExpiresAt',cap.expires_at,'actions',jsonb_build_array('refresh'),
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),
  'effectiveLifecycle',CASE WHEN (SELECT state FROM eshop.orders WHERE id=x."order")='preparing_payment' THEN 'preparing' ELSE public.get_effective_waitlist_ticket_lifecycle_internal(t.id) END,'currentOrderId',x."order") ORDER BY t.id),'[]')
  FROM (SELECT DISTINCT "order",ticket FROM eshop.order_product_ticket WHERE "order"=ANY(ids)) x JOIN eshop.tickets t ON t.id=x.ticket),
 'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'expiresAt',w.expires_at,
  'pendingPlaces',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending' AND w.expires_at>statement_timestamp()),
  'effectiveStatus',CASE WHEN w.expires_at<=statement_timestamp() THEN 'expired'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending') THEN 'pending'
   WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled' ELSE 'accepted' END)
  ORDER BY w.created_at,w.id),'[]') FROM eshop.waitlist_offers w WHERE w.order_id=root.id AND w.form_id=f.id),
 'orders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'symbol',o.order_symbol,'state',o.state,'total',o.price,'currency',o.currency_code,
  'payment',public.customer_order_payment_internal(o.id),
  'ticketIds',(SELECT coalesce(jsonb_agg(t.id ORDER BY t.id),'[]') FROM public.get_order_tickets_internal(o.id) t),
  'items',CASE WHEN o.state='preparing_payment' THEN '[]'::jsonb ELSE (SELECT coalesce(jsonb_agg(jsonb_build_object(
   'ticketId',t->'id','title',p->>'title','spotTitle',p->>'spot_title','spotGroupTitle',p->>'spot_group_title','price',p->'price','currency',p->>'currency_code')),'[]')
   FROM jsonb_array_elements(public.order_tickets_with_seating_internal(o.id,o.data->'tickets')) t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
   WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint)) END,
  'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',public.customer_ticket_label_internal(t.id,f.id),'rawState',t.state,
   'displayStatus',CASE t.state WHEN 'ordered' THEN 'awaiting_payment' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END,
   'usageStatus',CASE t.state WHEN 'ordered' THEN 'unused' WHEN 'paid' THEN 'unused' WHEN 'sent' THEN 'unused' WHEN 'used' THEN 'used' WHEN 'storno' THEN 'cancelled' ELSE 'unknown' END) ORDER BY t.id),'[]')
   FROM public.get_order_tickets_internal(o.id) t)) ORDER BY o.id),'[]')
  FROM eshop.orders o WHERE o.id=ANY(ids) AND o.state IS DISTINCT FROM 'waitlisted')) INTO result;
 RETURN result;
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.get_customer_order_overview(text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_customer_order_overview(text,bigint) TO anon,authenticated,service_role;

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
  v_paid             numeric;
  v_price            numeric;
  v_new_state        text;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
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

  IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND payment_method='stripe') THEN
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

  /* 5a) decide new state based on money received */
  SELECT COALESCE(pi.paid,0), o.price
    INTO v_paid, v_price
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON o.payment_info = pi.id
   WHERE o.id = v_order_id;

  v_new_state := CASE
                   WHEN v_paid >= v_price AND v_price > 0 THEN 'paid'
                   WHEN v_price <= 0 THEN 'paid'
                   ELSE 'ordered'
                 END;

  IF v_new_state = 'paid' THEN
    IF NOT EXISTS (
      SELECT 1 FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
      WHERE opt."order" = v_order_id AND t.state <> 'sent'
    ) THEN
      v_new_state := 'sent';
    END IF;
  END IF;

  PERFORM public.cancel_order_email_intents(v_order_id);
  UPDATE eshop.orders
     SET email_payment_version=email_payment_version+1, state      = v_new_state,
         updated_at = now()
   WHERE id = v_order_id;

  -- A price edit can pay off the order without the usual paid transition.
  -- Email acceptance only projects paid tickets to sent, so keep eligible
  -- tickets in step with the order before creating its delivery intent.
  IF v_new_state = 'paid' THEN
    UPDATE eshop.tickets t
       SET state = 'paid', updated_at = now()
      FROM eshop.order_product_ticket opt
     WHERE opt.ticket = t.id AND opt."order" = v_order_id
       AND t.state IN ('ordered', 'expired');
  END IF;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (SELECT f.deadline_duration_seconds FROM public.forms f
         JOIN eshop.orders o ON o.form=f.id WHERE o.id=v_order_id),
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM apply_allocations(v_order_id);
  PERFORM public.enqueue_paid_order_tickets(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_new_state,
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

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

-- SOURCE: eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION public.cancel_order_domain_internal_v1(order_id BIGINT,p_notify boolean)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
    v_order eshop.orders;
    v_occasion public.occasions;
    v_notice jsonb;
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=order_id FOR UPDATE;
    IF v_order.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
    IF v_order.state='storno' THEN RETURN; END IF;
    PERFORM public.check_order_is_mutable(order_id);
    -- Card finances and admission are resolved by provider facts and the
    -- audited refund decision, never by resetting an order's original price.
    IF EXISTS(SELECT 1 FROM eshop.payment_info pi
      WHERE pi.id=v_order.payment_info AND pi.payment_method='stripe') THEN
        RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION';
    END IF;
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;

    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

    -- The full transition owns the durable automatic commitment for every caller.
    SELECT * INTO v_occasion FROM public.occasions WHERE id=v_order.occasion;
    IF p_notify AND position('@' in v_order.data->>'email')>0
      AND length(v_order.data->>'email')<=320 THEN
      v_notice:=public.enqueue_order_email('TICKET_ORDER_STORNO',
        jsonb_build_object('order_id',order_id),v_occasion.organization,
        v_occasion.id,v_occasion.unit);
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_order_domain_internal_v1(bigint,boolean)
 FROM PUBLIC,anon,authenticated,service_role;
-- Compatibility for trusted SQL callers; domain logic exists only above.
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_221(order_id bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.cancel_order_domain_internal_v1(order_id,true);
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_221(bigint)
 FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop_orders/storno_tickets_bulk.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order_id BIGINT;
    v_occasion_id BIGINT;
    v_tickets_in_order BIGINT[];
    v_tickets_to_cancel_in_order BIGINT[];
    v_remaining_count INT;
    v_ticket_id_to_remove BIGINT;
    v_original_data JSONB;
    v_updated_tickets_json JSONB;
    v_ticket_elem JSONB;
    v_product_elem JSONB;
    v_removed_price NUMERIC(10, 2);
    v_current_price NUMERIC(10, 2);
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
    -- 1. Identify all unique orders involved in this batch AND their occasion
    -- We need the occasion ID to perform the security check
    FOR v_order_id, v_occasion_id IN
        SELECT DISTINCT o.id, o.occasion
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE t.id = ANY(p_ticket_ids)
        ORDER BY o.id
    LOOP
        -- 2. SECURITY CHECK
        -- Verify that the current user has editor permissions on the occasion associated with the order.
        IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
            RAISE EXCEPTION 'Permission denied to storno tickets for order % on occasion %', v_order_id, v_occasion_id;
        END IF;

        IF (SELECT state FROM eshop.orders WHERE id=v_order_id)='storno' THEN CONTINUE; END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        IF EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=v_order_id AND pi.payment_method='stripe') THEN
            RAISE EXCEPTION 'STRIPE_USE_REFUND_ADMISSION_DECISION'; END IF;
        -- Serialize cancellations on the same order before counting survivors.
        PERFORM 1 FROM eshop.orders WHERE id = v_order_id FOR UPDATE;

        -- 3. Get all active tickets currently in this order
        SELECT ARRAY_AGG(t.id)
        INTO v_tickets_in_order
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        WHERE opt."order" = v_order_id
        AND (t.state IS NULL OR t.state != 'storno');

        -- 4. Get intersection: Tickets in this order that we want to cancel
        SELECT ARRAY_AGG(id)
        INTO v_tickets_to_cancel_in_order
        FROM UNNEST(v_tickets_in_order) AS id
        WHERE id = ANY(p_ticket_ids);

        -- A replay or a selection containing only cancelled tickets has no effect.
        IF coalesce(cardinality(v_tickets_to_cancel_in_order), 0) = 0 THEN
            CONTINUE;
        END IF;

        -- 5. Calculate how many would remain
        v_remaining_count := array_length(v_tickets_in_order, 1) - array_length(v_tickets_to_cancel_in_order, 1);

        -- -----------------------------------------------------
        -- SCENARIO A: Full Order Cancellation
        -- -----------------------------------------------------
        IF v_remaining_count <= 0 THEN
            -- Helper function to cancel the entire order
            PERFORM update_order_and_tickets_to_storno_ws_internal_v1(v_order_id);

        -- -----------------------------------------------------
        -- SCENARIO B: Partial Cancellation (Modify Order)
        -- -----------------------------------------------------
        ELSE
            -- 1. Mark specific tickets as storno in DB
            PERFORM internal_storno_tickets_221(v_tickets_to_cancel_in_order);

            -- 2. Fetch Order Data
            SELECT data, price INTO v_original_data, v_current_price
            FROM eshop.orders WHERE id = v_order_id;

            v_updated_tickets_json := '[]'::JSONB;
            v_removed_price := 0;

            -- 3. Rebuild JSON data, filtering out cancelled tickets and summing price to remove
            FOR v_ticket_elem IN SELECT * FROM jsonb_array_elements(v_original_data->'tickets')
            LOOP
                v_ticket_id_to_remove := (v_ticket_elem->>'id')::BIGINT;

                -- If this ticket is one of the ones being cancelled
                IF v_ticket_id_to_remove = ANY(v_tickets_to_cancel_in_order) THEN
                    -- Sum up price to deduct
                    FOR v_product_elem IN SELECT * FROM jsonb_array_elements(v_ticket_elem->'products')
                    LOOP
                        v_removed_price := v_removed_price + COALESCE((v_product_elem->>'price')::NUMERIC, 0);
                    END LOOP;
                ELSE
                    -- Keep this ticket in the new JSON
                    v_updated_tickets_json := v_updated_tickets_json || v_ticket_elem;
                END IF;
            END LOOP;

            -- Fence unsent snapshots of the previous ticket set, and keep the
            -- payment amount aligned with the new order total.
            PERFORM public.cancel_order_email_intents(v_order_id);
            UPDATE eshop.payment_info SET amount=GREATEST(0, COALESCE(v_current_price,0)-v_removed_price)
            WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);

            -- 4. Update Order (Data & Price)
            UPDATE eshop.orders
            SET
                data = v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                price = GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                email_payment_version = email_payment_version + 1,
                updated_at = NOW()
            WHERE id = v_order_id;

            -- Refresh only this order's existing reminder schedule for its new amount.
            PERFORM public.set_payment_deadline(pi.id,pi.deadline)
            FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
            WHERE o.id=v_order_id AND o.state='ordered' AND pi.deadline IS NOT NULL;

            -- Existing delivery policy prepares the surviving tickets if their
            -- paid order has not finished sending yet; sent orders stay untouched.
            PERFORM public.enqueue_paid_order_tickets(v_order_id);

            -- 5. Insert ONE history record for this modification
            INSERT INTO eshop.orders_history (
                "order",
                data,
                state,
                price,
                created_at
            )
            VALUES (
                v_order_id,
                v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                (SELECT state FROM eshop.orders WHERE id=v_order_id),
                GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                NOW()
            );
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[]) FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop_orders/get_orders.sql
CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link)
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link)
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden,
        'data', t.data
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'participant_capacity',f.participant_capacity,
        'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,
        'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),
        'registrationMode',public.get_form_registration_mode_internal(f.id),
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders, conditionally filtering by form link
    IF v_form_id IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',(public.get_waitlist_summary_internal(o.id)->'allowedActions') -
              CASE WHEN EXISTS(SELECT 1 FROM eshop.payment_info card WHERE card.id=o.payment_info AND card.payment_method='stripe')
                THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END,
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data || jsonb_build_object('tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id AND o.form = v_form_id;
    ELSE
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',(public.get_waitlist_summary_internal(o.id)->'allowedActions') -
              CASE WHEN EXISTS(SELECT 1 FROM eshop.payment_info card WHERE card.id=o.payment_info AND card.payment_method='stripe')
                THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END,
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data || jsonb_build_object('tickets', public.order_tickets_with_seating_internal(o.id,o.data->'tickets'))
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'payment_method', pi.payment_method, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'order_sequence', (SELECT o.order_sequence FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;

-- SOURCE: eshop_orders/get_orders_tab_data.sql
CREATE OR REPLACE FUNCTION public.get_orders_tab_data(
    p_occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
    v_occasion BIGINT;
BEGIN
    SELECT id INTO v_occasion FROM public.occasions
    WHERE id=public.resolve_occasion_link_internal(p_occasion_link)
      AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());
    IF auth.uid() IS NULL OR v_occasion IS NULL
       OR NOT coalesce(public.get_is_editor_order_view_on_occasion(v_occasion),false) THEN
        RAISE insufficient_privilege USING MESSAGE='order viewer required';
    END IF;

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    RETURN (v_orders_data->'data') || jsonb_build_object('forms', v_forms_data->'data', 'email_delivery',
      public.get_order_email_summaries(v_occasion,
        ARRAY(SELECT (ord->>'id')::bigint FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord)));
END;
$$;

-- SOURCE: eshop/get_order_history.sql
CREATE OR REPLACE FUNCTION public.get_order_history(order_id bigint)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    v_occasion_id bigint;
    v_order_data jsonb;
    v_history_data jsonb;
    v_users_data jsonb;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT o.occasion, to_jsonb(o) || jsonb_build_object('payment_method', pi.payment_method)
    INTO v_occasion_id, v_order_data
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON pi.id = o.payment_info
    WHERE o.id = order_id;

    -- Check if the order exists
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
    END IF;

    -- Verify if the current user is an editor for the order's occasion
    IF NOT get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this order history');
    END IF;

    -- Fetch history items for the order, ordered by creation date
    SELECT jsonb_agg(to_jsonb(h) || jsonb_build_object('order_symbol', v_order_data->>'order_symbol', 'order_sequence', v_order_data->'order_sequence') ORDER BY h.created_at)
    INTO v_history_data
    FROM eshop.orders_history h
    WHERE h. "order" = order_id;

    -- Fetch unique users who created the history items
    WITH user_ids AS (
        SELECT DISTINCT created_by
        FROM eshop.orders_history
        WHERE "order" = order_id AND created_by IS NOT NULL
    )
    SELECT jsonb_agg(u.*)
    INTO v_users_data
    FROM public.user_info u
    WHERE u.id IN (SELECT created_by FROM user_ids);

    -- Return the combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'order', COALESCE(v_order_data, '{}'::jsonb),
            'history', COALESCE(v_history_data, '[]'::jsonb),
            'users', COALESCE(v_users_data, '[]'::jsonb)
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

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
    new_state TEXT;

    price_delta NUMERIC;
    history_needed BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order";
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the orders.data
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

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate financials and state
    price_delta := new_price - original_price;
    history_needed := (original_product_id IS DISTINCT FROM p_new_product_id);
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- Recalculate order state
    SELECT CASE
        WHEN COALESCE(pi.paid, 0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM eshop.payment_info pi WHERE pi.id = ord.payment_info;

    -- 6. Build the new orders.data JSON
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
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND payment_method='stripe') THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        state = new_state,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- 8. Create history log *only if* the product ID actually changed
    IF history_needed THEN
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        VALUES (ord.id, new_data, new_state, new_order_price, ord.currency_code);
    END IF;

END;
$$;


CREATE OR REPLACE FUNCTION public.swap_spot_tickets_internal_v1(spot_id_1 BIGINT, spot_id_2 BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    spot1 RECORD;
    spot2 RECORD;
    occasion_id_common BIGINT;
    has_permission BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Input Validation
    IF spot_id_1 IS NULL OR spot_id_2 IS NULL THEN
        RAISE EXCEPTION 'Both spot_id_1 and spot_id_2 must be provided' USING ERRCODE = '22023';
    END IF;
    IF spot_id_1 = spot_id_2 THEN
        RAISE EXCEPTION 'Cannot swap a spot with itself' USING ERRCODE = '22023';
    END IF;

    PERFORM public.lock_spot_assignment_scope_internal_v1(ARRAY[spot_id_1,spot_id_2]);

    -- 2. Fetch Spot Data
    SELECT * INTO spot1 FROM eshop.spots WHERE id = spot_id_1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 1 not found (ID: %)', spot_id_1 USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO spot2 FROM eshop.spots WHERE id = spot_id_2;
    IF NOT FOUND THEN RAISE EXCEPTION 'Spot 2 not found (ID: %)', spot_id_2 USING ERRCODE = 'P0002'; END IF;

    -- 3. Permission and Occasion Check
    IF spot1.occasion IS NULL OR spot2.occasion IS NULL THEN
         RAISE EXCEPTION 'Spots are missing occasion information' USING ERRCODE = '22004';
    END IF;
    IF spot1.occasion <> spot2.occasion THEN
        RAISE EXCEPTION 'Spots do not belong to the same occasion (Spot1: %, Spot2: %)', spot1.occasion, spot2.occasion USING ERRCODE = 'P0001';
    END IF;
    occasion_id_common := spot1.occasion;

    -- Check permission
    BEGIN
        SELECT get_is_editor_order_on_occasion(occasion_id_common) INTO has_permission;
    EXCEPTION
        WHEN undefined_function THEN RAISE EXCEPTION 'Permission check function get_is_editor_order_on_occasion() does not exist.' USING ERRCODE = '42883';
        WHEN OTHERS THEN RAISE EXCEPTION 'Error during permission check: %', SQLERRM;
    END;
    IF has_permission <> TRUE THEN
        RAISE EXCEPTION 'User is not authorized to edit orders for this occasion' USING ERRCODE = '42501';
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.spots WHERE id IN(spot_id_1,spot_id_2)
      AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp()) THEN
      RAISE object_not_in_prerequisite_state USING MESSAGE='SPOT_HELD'; END IF;
    -- Ticket locks follow the already locked order parents, in a stable order.
    PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT ticket FROM eshop.order_product_ticket
      WHERE id IN(spot1.order_product_ticket,spot2.order_product_ticket)) ORDER BY id FOR UPDATE;

    -- 4. Main Swap Logic: Branch based on assignment status
    -- This logic is now greatly simplified by the helper functions.

    IF spot1.order_product_ticket IS NOT NULL AND spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE A: BOTH SPOTS ARE ASSIGNED
        -- ----------------------------------------------------------------

        -- Ticket 1 (from spot 1) moves to Spot 2, so it must adopt Spot 2's product.
        PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);

        -- Ticket 2 (from spot 2) moves to Spot 1, so it must adopt Spot 1's product.
        PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);

    ELSIF spot1.order_product_ticket IS NOT NULL OR spot2.order_product_ticket IS NOT NULL THEN
        -- ----------------------------------------------------------------
        -- CASE B/C: ONE SPOT IS ASSIGNED, ONE IS UNASSIGNED
        -- ----------------------------------------------------------------

        IF spot1.order_product_ticket IS NOT NULL THEN
            -- Spot 1 is assigned, Spot 2 is unassigned.
            -- Ticket 1 moves to Spot 2 and adopts Spot 2's product.
            PERFORM public._swap_spots_update_ticket(spot1.order_product_ticket, spot2.product, spot_id_2);
        ELSE
            -- Spot 2 is assigned, Spot 1 is unassigned.
            -- Ticket 2 moves to Spot 1 and adopts Spot 1's product.
            PERFORM public._swap_spots_update_ticket(spot2.order_product_ticket, spot1.product, spot_id_1);
        END IF;

    ELSE
        -- ----------------------------------------------------------------
        -- CASE D: BOTH SPOTS ARE UNASSIGNED
        -- ----------------------------------------------------------------
        -- Nothing to do.
        RETURN;
    END IF;

    -- 5. Final Spot Update
    -- This block runs for Cases A, B, and C.
    -- We ONLY swap the 'order_product_ticket' FK. The 'product' column
    -- on the spot (spot1.product, spot2.product) never changes.
    UPDATE eshop.spots
    SET
        order_product_ticket = CASE
            WHEN id = spot_id_1 THEN spot2.order_product_ticket -- Spot 1 gets Ticket 2
            WHEN id = spot_id_2 THEN spot1.order_product_ticket -- Spot 2 gets Ticket 1
        END
    WHERE id IN (spot_id_1, spot_id_2);

END;
$$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets_internal_v1(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

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
  IF p_input_data->>'payment_method'='stripe' OR EXISTS(
    SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket
    JOIN eshop.orders o ON o.id=x."order" JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE s.id=ANY(p_spot_ids) AND pi.payment_method='stripe') THEN
    RAISE EXCEPTION 'STRIPE_REPLACEMENT_UNSUPPORTED'; END IF;

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

REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[],jsonb) FROM PUBLIC,anon,authenticated;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method='stripe')
   AND public.stripe_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method='stripe' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid(); v_wait integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT (x->>'base_limit')::integer INTO v_wait FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.dispatch',NULL,NULL)->'rules') x;
 IF v_wait IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY CASE WHEN m.created_at<=now()-make_interval(secs=>v_wait) THEN 0 ELSE priority END,
 (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.last_claimed_at IS NOT NULL) NULLS FIRST,
 CASE WHEN m.unit IS NULL THEN (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.unit IS NULL AND served.last_claimed_at IS NOT NULL)
 ELSE (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.unit=m.unit AND served.last_claimed_at IS NOT NULL) END NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',last_claimed_at=now(),lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF octet_length(p_prepared::text)>(SELECT (x->>'base_limit')::bigint
  FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.payload',NULL,NULL)->'rules') x LIMIT 1) THEN
  RAISE configuration_limit_exceeded USING MESSAGE='email_payload_too_large'; END IF;
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=p_message),true);
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||v_row.admission_class,v_row.unit,v_row.organization),
   jsonb_build_object('recipient',public.abuse_recipient_key_v1(v_row.recipient)));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;

-- SOURCE: eshop/format_occasion_report_text.sql
CREATE OR REPLACE FUNCTION public.format_occasion_report_text(report jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE result text; item jsonb; section text;
BEGIN
  result := (report->'occasion'->>'title') || E'\n' || (report->>'generated_at') || E'\n';
  FOREACH section IN ARRAY ARRAY['orders','tickets'] LOOP
    result := result || CASE section WHEN 'orders' THEN 'Počet objednávek celkem: ' ELSE 'Počet vstupenek celkem: ' END || (report->section->>'total') || E'\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->section->'by_state') LOOP
      result := result || '  ' || (item->>'state') || ': ' || (item->>'count') || E'\n';
    END LOOP;
  END LOOP;
  result := result || 'Místa (obsazená / celkem): ' || (report->'spots'->>'occupied') || ' / ' || (report->'spots'->>'total') || E'\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'money_by_currency') LOOP
    result := result || E'\n' || (item->>'currency') || E'\n'
      || 'Aktuální hodnota objednávek: ' || (item->>'current_order_value') || E'\n'
      || 'Přijato: ' || (item->>'received') || E'\n'
      || 'Vráceno: ' || (item->>'returned') || E'\n'
      || 'Čistý příjem: ' || (item->>'net_received') || E'\n'
      || 'Ručně evidováno: ' || (item->>'manual_received') || E'\n'
      || 'Ostatní příjmy: ' || (item->>'other_received') || E'\n';
    IF item ? 'stripe_received' THEN
      result:=result||'Z toho přijato přes Stripe: '||(item->>'stripe_received')||E'\n'
       ||'Z toho vráceno přes Stripe: '||(item->>'stripe_refunded')||E'\n'
       ||'Částka ve sporu (není vratka): '||(item->>'disputed')||E'\n'
       ||'Dostupné po odečtení sporů: '||(item->>'available_after_disputes')||E'\n';
    END IF;
    IF item ? 'external_unattributed' THEN
      result:=result||'Externí částka bez doloženého přiřazení: '||(item->>'external_unattributed')||E'\n';
    END IF;
    IF (item->>'has_deposits')::boolean THEN
      result := result || 'Přijaté zálohy (hrubé): ' || (item->>'deposit_received_gross') || E'\n'
        || 'Přijato nad zálohu (hrubé): ' || (item->>'beyond_deposit_received_gross') || E'\n';
    END IF;
  END LOOP;
  IF report ? 'timeline' THEN
    result := result || E'\nNové objednávky po dnech (Europe/Prague, včetně později stornovaných):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'orders') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': ' || (item->>'count') || E'\n';
    END LOOP;
    result := result || E'\nZaevidované platby po dnech (datum bankovní transakce nebo čas pohybu Stripe v Europe/Prague; včetně částečných plateb):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'payments') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': přijato ' || (item->>'received') || ', vráceno ' || (item->>'returned') || E'\n';
    END LOOP;
  END IF;
  result := result || E'\nProdukty v potvrzených objednávkách (paid/sent/used, včetně záloh):\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'products') LOOP
    result := result || coalesce(item->>'type_title','Bez typu') || ' / ' || (item->>'product_title') || ': ' || (item->>'confirmed_count') || E'\n';
  END LOOP;
  result := result || E'\nSouhrn stavů odpovídá aktuálnímu stavu, nikoli historickým přechodům. Denní platby obsahují pouze zaevidované transakce. Stav paid může znamenat jen uhrazenou zálohu.\nMísta nezahrnují dočasné blokace. Ruční příjmy nejsou nutně hotovost; ostatní nejsou nutně banka.\nZálohy jsou hrubé platby před vratkami, pouze u plateb se zálohou.\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'warnings') LOOP
    result := result || 'Upozornění: ' || (item->>'code') || ' (' || (item->>'count') || E')\n';
  END LOOP;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.format_occasion_report_text(jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: eshop/get_report_ws.sql
CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE r jsonb; invalid_payment boolean;
BEGIN
  WITH scope AS MATERIALIZED (
    SELECT o.id, o.title FROM public.occasions o
    JOIN public.user_info u ON u.organization = o.organization AND u.id = auth.uid()
    WHERE o.id = public.resolve_occasion_link_internal(occasion_link) AND public.get_is_editor_order_view_on_occasion(o.id)
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

-- SOURCE: eshop_stripe/client_sync.sql
-- Provider facts invalidate the existing private inventory projection. This
-- registry never exposes raw tables, capabilities or sealed payment sources.
INSERT INTO public.client_sync_component_sources
 (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
 (1,'private_inventory','public.forms','forms.occasion',ARRAY['data'],
  ARRAY['complete_stripe_connection_flow_internal'],'{}','migrate','database/tests/eshop/stripe/connections_test.sql',false),
 (1,'private_inventory','eshop.orders','orders.occasion',ARRAY['state','email_payment_version'],
  ARRAY['ingest_stripe_payment_internal','decide_stripe_partial_refund_client_sync_v1'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false),
 (1,'private_inventory','eshop.tickets','tickets.occasion',ARRAY['state'],
  ARRAY['ingest_stripe_payment_internal','decide_stripe_partial_refund_client_sync_v1'],'{}','migrate','database/tests/eshop/stripe/refund_decisions_test.sql',false),
 (1,'private_inventory','eshop.stripe_payment_movements','attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion',
  ARRAY['provider_id','kind','amount_minor','currency','occurred_at'],
  ARRAY['ingest_stripe_payment_internal'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false),
 (1,'private_inventory','eshop.stripe_disputes','attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion',
  ARRAY['provider_id','amount_minor','status','observed_at'],
  ARRAY['ingest_stripe_payment_internal'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false)
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
