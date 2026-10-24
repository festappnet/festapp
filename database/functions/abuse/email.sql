CREATE OR REPLACE FUNCTION public.abuse_recipient_key_v1(p_recipient text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT encode(extensions.hmac(lower(btrim(p_recipient)),encode(secret,'hex'),'sha256'),'hex')
 FROM public.abuse_identity_key WHERE singleton;
$$;
REVOKE ALL ON FUNCTION public.abuse_recipient_key_v1(text) FROM PUBLIC,anon,authenticated,service_role;

-- Shared classification also adopts pending pre-cutover intents without recharging them.
CREATE OR REPLACE FUNCTION public.email_admission_class_v1(m public.email_messages) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; commitment boolean:=false;
BEGIN
 IF m.message_kind IN ('order_tickets','order_payment_notice','order_storno') AND m.order_id IS NOT NULL THEN
  SELECT * INTO o FROM eshop.orders WHERE id=m.order_id;
  commitment:=((m.message_kind IN ('order_tickets','order_payment_notice') AND o.state IN ('paid','sent')) OR (m.message_kind='order_storno' AND o.state='storno')) AND o.occasion=m.occasion AND o.email_payment_version=m.source_version
   AND m.recipient IS NOT DISTINCT FROM o.data->>'email'
   AND m.dedupe_key=o.id||':'||o.email_payment_version||':'||coalesce(m.recipient,'')||CASE WHEN m.message_kind='order_storno' THEN ':storno' ELSE ':false' END
   AND NOT m.data ? 'requested_by';
 END IF;
 IF commitment THEN RETURN 'commitment'; END IF;
 RETURN CASE WHEN m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 'auth' ELSE 'ordinary' END;
END $$;
REVOKE ALL ON FUNCTION public.email_admission_class_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_email_intent_v1(p_message bigint,p_recheck boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
 is_auth boolean; unit_count bigint; org_count bigint; unit_bytes bigint; org_bytes bigint; growth bigint:=0; policies jsonb;
BEGIN
 SELECT * INTO STRICT m FROM public.email_messages WHERE id=p_message;
 policies:=public.abuse_policy_bundle_v1(ARRAY['email.payload','email.actor','email.backlog','email.auth.backlog','email.auth','email.ordinary'],m.unit,m.organization);
 IF m.unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=m.unit AND organization=m.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='email_scope_mismatch'; END IF;
 scopes:=jsonb_build_object('unit',m.unit,'organization',m.organization,'global','all',
  'actor',m.producer_actor,'recipient',public.abuse_recipient_key_v1(coalesce(m.recipient,(SELECT email_readonly FROM public.user_info WHERE id=m.recipient_user))));
 PERFORM public.abuse_charge_v1(policies->'email.payload',scopes,
  jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
 -- Neither caller priority nor request data can claim the reserved class.
 IF public.email_admission_class_v1(m)='commitment' THEN
  UPDATE public.email_messages SET admission_class='commitment',priority=5 WHERE id=m.id;
  RETURN;
 END IF;
 IF NOT p_recheck AND m.producer_actor IS NOT NULL THEN
  PERFORM public.abuse_charge_v1(policies->'email.actor',scopes);
 END IF;
 is_auth:=public.email_admission_class_v1(m)='auth';
 UPDATE public.email_messages SET admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END WHERE id=m.id;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth.backlog' ELSE 'email.backlog' END);
 -- Null Unit auth has an explicit tenant/global class, never a synthetic Unit.
 IF m.unit IS NULL THEN policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit')); END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' IN ('bytes','duration') THEN CONTINUE; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 -- Pending partial indexes exclude delivery history. Include blocked/future/unknown.
 SELECT count(*) FILTER(WHERE unit=m.unit),count(*),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)) FILTER(WHERE unit=m.unit),0),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)),0)
 INTO unit_count,org_count,unit_bytes,org_bytes FROM public.email_messages
 WHERE organization=m.organization AND admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
 costs:=jsonb_build_object('email.auth.backlog.organization',org_count,'email.backlog.unit',unit_count,'email.backlog.organization',org_count,
  'email.backlog.unit.bytes',unit_bytes,'email.backlog.organization.bytes',org_bytes);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 IF p_recheck THEN RETURN; END IF;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth' ELSE 'email.ordinary' END);
 IF NOT is_auth AND m.unit IS NULL THEN
  -- System producers without a Unit retain tenant and recipient bounds.
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit'));
 END IF;
 IF NOT is_auth AND m.unit IS NOT NULL THEN
  SELECT coalesce(verified_orders,0) INTO growth FROM public.abuse_unit_evidence
   WHERE unit=m.unit AND measured_at>statement_timestamp()-interval '15 minutes';
  growth:=coalesce(growth,0);
 END IF;
 PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('growth',growth));
END $$;
REVOKE ALL ON FUNCTION public.admit_email_intent_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Separate committed preparation budget limits rendering before final enqueue.
CREATE OR REPLACE FUNCTION public.admit_email_preparation_v1(p_organization bigint,p_occasion bigint,p_unit bigint,p_recipient text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization)
 OR (p_unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization))
 OR (p_occasion IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_organization AND (p_unit IS NULL OR unit=p_unit)))
 OR p_recipient IS NULL OR length(p_recipient)>320 THEN RAISE invalid_parameter_value USING MESSAGE='email_preparation_scope'; END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('email.prepare',p_unit,p_organization),
  jsonb_build_object('organization',p_organization,'recipient',public.abuse_recipient_key_v1(p_recipient)), '{}',true);
END $$;
REVOKE ALL ON FUNCTION public.admit_email_preparation_v1(bigint,bigint,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_email_preparation_v1(bigint,bigint,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.admit_order_creation_v1(p_occasion bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ public.occasions; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
BEGIN
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=p_occasion;
 policy:=public.abuse_effective_rules_v1('order.creation',occ.unit,occ.organization);
 scopes:=jsonb_build_object('unit',occ.unit,'organization',occ.organization);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT jsonb_build_object('order.outstanding.unit',count(*) FILTER(WHERE oc.unit=occ.unit)+1,
  'order.outstanding.organization',count(*)+1) INTO costs
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
 WHERE oc.organization=occ.organization AND o.state IN ('ordered','created','expired','waitlisted','paid');
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
END $$;
REVOKE ALL ON FUNCTION public.admit_order_creation_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Periodic local maintenance, not a query per mail/request. The source is
-- positive signed-bank evidence, distinct orders, and a capped sample/count.
CREATE OR REPLACE FUNCTION public.refresh_abuse_unit_evidence_v1() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u record; cap bigint; n integer:=0; verified bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT hard_cap/greatest(growth_increment,1)+1 INTO cap FROM public.abuse_policy_rules WHERE rule_key='email.ordinary.unit.day';
 IF cap IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 FOR u IN SELECT units.id FROM public.units LEFT JOIN public.abuse_unit_evidence e ON e.unit=units.id
  WHERE e.measured_at IS NULL OR e.measured_at<statement_timestamp()-interval '5 minutes'
  ORDER BY e.measured_at NULLS FIRST,units.id LIMIT 20 LOOP
  IF NOT pg_try_advisory_xact_lock(hashtextextended('abuse-growth:'||u.id,0)) THEN CONTINUE; END IF;
  SELECT count(*) INTO verified FROM (
   SELECT ord.id FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion
   WHERE occ.unit=u.id AND ord.state IN ('paid','sent') AND ord.price>0
   AND (SELECT coalesce(sum(t.amount),0) FROM eshop.transactions t
    WHERE t.payment_info=ord.payment_info AND t.currency=ord.currency_code
     AND EXISTS(SELECT 1 FROM eshop.bank_transaction_identities i WHERE i.transaction_id=t.id))>=ord.price LIMIT cap
  ) proof;
  INSERT INTO public.abuse_unit_evidence VALUES(u.id,verified,statement_timestamp())
   ON CONFLICT(unit) DO UPDATE SET verified_orders=excluded.verified_orders,measured_at=excluded.measured_at;
  n:=n+1;
 END LOOP;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.refresh_abuse_unit_evidence_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_abuse_unit_evidence_v1() TO service_role;
