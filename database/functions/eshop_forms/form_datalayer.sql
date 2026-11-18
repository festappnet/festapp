CREATE OR REPLACE FUNCTION public.form_conversion_policy_allows_internal(p_status jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_status @> '{"requested_enabled":true,"organization_allowed":true,"organization_enabled":true,"unit_enabled":true}'::jsonb
  AND NOT (p_status->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb),false);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_policy_allows_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Read only after the existing command's receipt authorization. Live policy is
-- deliberately separate from immutable conversion facts and durable receipts.
CREATE OR REPLACE FUNCTION public.form_conversion_datalayer_internal(p_order bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT c.payload FROM analytics.conversion_facts c
 JOIN eshop.orders o ON o.id=c."order"
 CROSS JOIN LATERAL (SELECT public.form_measurement_status_internal(o.form) s) policy
 WHERE p_kind IN ('waitlist','free_registration')
   AND c."order"=p_order AND c.kind=p_kind AND public.form_conversion_policy_allows_internal(s);
$$;
REVOKE ALL ON FUNCTION public.form_conversion_datalayer_internal(bigint,text) FROM PUBLIC,anon,authenticated,service_role;

DROP FUNCTION IF EXISTS public.form_purchase_datalayer_internal(bigint);

-- Called exactly at canonical finalization/registration, never on replay.
CREATE OR REPLACE FUNCTION public.record_form_conversion_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=public,extensions AS $$
DECLARE o eshop.orders; s jsonb; lead_kind text; identity uuid:=gen_random_uuid();
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 lead_kind:=CASE WHEN o.state='waitlisted' THEN 'waitlist' WHEN o.price=0 THEN 'free_registration' END;
 IF lead_kind IS NULL THEN RETURN; END IF;
 s:=public.form_measurement_status_internal(o.form);
 IF NOT public.form_conversion_policy_allows_internal(s) THEN RETURN; END IF;
 INSERT INTO analytics.conversion_facts("order",kind,event_id,payload)
 VALUES (p_order,lead_kind,identity,jsonb_build_object('event','generate_lead','event_id',identity,
   'currency',coalesce(nullif(trim(o.currency_code),''),'CZK'),'value',0,'lead_source',lead_kind))
 ON CONFLICT("order",kind) DO NOTHING;
-- Measurement failure cannot change checkout.
EXCEPTION WHEN OTHERS THEN RETURN;
END $$;
REVOKE ALL ON FUNCTION public.record_form_conversion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
