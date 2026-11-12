-- Fixed product policy, not a recipient setting. Changing a published interval
-- requires a forward migration that handles existing windows.
CREATE OR REPLACE FUNCTION public.notification_center_email_window_internal()
RETURNS interval LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT interval '300 seconds';
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_window_internal() FROM PUBLIC,anon,authenticated,service_role;

-- Required operational alerts ignore optional subscriptions and action muting.
-- Recipient capture, live authorization and the universal queue gate still apply.
CREATE OR REPLACE FUNCTION public.notification_center_email_required_kind_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(p_kind IN ('bank_problem','provider_problem'),false);
$$;
REVOKE ALL ON FUNCTION public.notification_center_email_required_kind_internal(text) FROM PUBLIC,anon,authenticated,service_role;
