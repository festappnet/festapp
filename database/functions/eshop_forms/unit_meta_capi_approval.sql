-- Wire compatibility for installed clients and published API consumers.
-- Both legacy responses describe current organizer access without queueing mail.
CREATE OR REPLACE FUNCTION public.get_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.can_read_unit_administration(p_unit) OR public.can_manage_unit_meta_purchase(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI access denied';
 END IF;
 RETURN jsonb_build_object('approved',public.can_manage_unit_meta_purchase(p_unit),
  'requested_at',NULL,'request_state','not_requested','can_request',false);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_capi_approval(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_unit_meta_capi_approval(p_unit);
$$;
REVOKE ALL ON FUNCTION public.request_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_meta_capi_approval(bigint) TO authenticated;
