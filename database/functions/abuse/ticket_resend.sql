-- Admission and fenced sending use distinct counters with the same bounds.
INSERT INTO public.abuse_policy_rules
 (rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
SELECT budget||'.recipient.'||rule,s.budget,scope,'rolling',window_seconds,bucket_seconds,quota,quota
FROM (VALUES ('email.ticket_resend'),('email.send.ticket_resend')) s(budget)
CROSS JOIN (VALUES
 ('unit.burst','unit',60,60,2), ('unit.day','unit',86400,3600,5),
 ('global.burst','recipient',60,60,4), ('global.day','recipient',86400,3600,12)
) r(rule,scope,window_seconds,bucket_seconds,quota);

CREATE OR REPLACE FUNCTION public.ticket_resend_scopes_internal_v1(m public.email_messages)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE actor uuid; recipient_key text;
BEGIN
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR m.order_id IS NULL OR m.unit IS NULL OR m.recipient IS NULL
    OR COALESCE(m.data->>'requested_by','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RETURN NULL; END IF;
 actor := (m.data->>'requested_by')::uuid;
 IF NOT EXISTS (
  SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=m.order_id AND o.occasion=m.occasion AND oc.organization=m.organization AND oc.unit=m.unit
   AND o.state IN ('paid','sent') AND o.email_payment_version=m.source_version
   AND lower(btrim(o.data->>'email'))=lower(btrim(m.recipient))
   AND (m.dedupe_key ~ '^(resend|repair|operator):'
        OR m.dedupe_key=public.order_email_automatic_key_internal(o.id,o.email_payment_version,o.data->>'email'))
 ) OR public.can_write_orders_as_actor_internal(actor,m.occasion) IS DISTINCT FROM TRUE
 THEN RETURN NULL; END IF;
 recipient_key := public.abuse_recipient_key_v1(m.recipient);
 RETURN jsonb_build_object('actor',actor,'unit',m.unit||':'||recipient_key,'recipient',recipient_key);
END $$;
REVOKE ALL ON FUNCTION public.ticket_resend_scopes_internal_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.charge_email_send_recipient_internal_v1(m public.email_messages)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE resend_scopes jsonb; limit_detail text;
BEGIN
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||m.admission_class,m.unit,m.organization),
  jsonb_build_object('recipient',CASE WHEN m.admission_class='notification' THEN m.recipient_user::text ELSE public.abuse_recipient_key_v1(m.recipient) END,'global','all'));
EXCEPTION WHEN SQLSTATE 'PT429' THEN
 GET STACKED DIAGNOSTICS limit_detail = PG_EXCEPTION_DETAIL;
 IF m.admission_class IS DISTINCT FROM 'ordinary' OR coalesce(limit_detail::jsonb->>'ruleKey','') NOT IN
  ('email.send.ordinary.recipient.burst','email.send.ordinary.recipient.day') THEN RAISE; END IF;
 resend_scopes:=public.ticket_resend_scopes_internal_v1(m);
 IF resend_scopes IS NULL THEN RAISE; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.ticket_resend',m.unit,m.organization),resend_scopes);
END $$;
REVOKE ALL ON FUNCTION public.charge_email_send_recipient_internal_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;
