-- Browser projections and the Meta delivery worker subscribe to stored facts
-- by role. Each adapter still owns its own authorization and delivery rules.
CREATE OR REPLACE FUNCTION public.form_measurement_subscription_kind_internal(p_subscription text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE p_subscription
  WHEN 'web_purchase_snapshot' THEN 'purchase'
  WHEN 'web_paid_purchase' THEN 'order_fully_paid'
  WHEN 'web_free_registration' THEN 'free_registration'
  WHEN 'web_waitlist' THEN 'waitlist'
  WHEN 'meta_purchase' THEN 'order_fully_paid'
 END;
$$;
REVOKE ALL ON FUNCTION public.form_measurement_subscription_kind_internal(text) FROM PUBLIC,anon,authenticated,service_role;
