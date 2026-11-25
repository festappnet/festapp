-- Operator-managed sandbox installation only. This neither discovers keys nor
-- attests production merchant/marketplace/refund eligibility.
CREATE OR REPLACE FUNCTION public.configure_gopay_sandbox_connection_internal(p_organization bigint,p_unit bigint,p_go_id text,p_storefront_origin text,p_name text,p_forms bigint[],p_enabled boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE connection uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_go_id IS NULL OR p_go_id !~ '^[1-9][0-9]{0,15}$' OR p_storefront_origin IS NULL OR p_storefront_origin !~ '^https://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.vstupenky\.online$' OR nullif(p_name,'') IS NULL OR p_forms IS NULL OR p_enabled IS NULL
  OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization)
  OR EXISTS(SELECT 1 FROM unnest(p_forms) fid WHERE fid IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=fid AND oc.unit=p_unit AND oc.organization=p_organization))
  THEN RAISE EXCEPTION 'GOPAY_SANDBOX_SCOPE_INVALID'; END IF;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 INSERT INTO eshop.gopay_connections AS current_connection
  (organization_id,unit_id,account_id,storefront_origin,business_name,sandbox_form_ids,enabled)
 VALUES(p_organization,p_unit,p_go_id,p_storefront_origin,p_name,p_forms,p_enabled)
 ON CONFLICT(account_id) DO UPDATE SET business_name=excluded.business_name,
  sandbox_form_ids=excluded.sandbox_form_ids,enabled=excluded.enabled
 WHERE current_connection.unit_id=excluded.unit_id
  AND current_connection.organization_id=excluded.organization_id
  AND current_connection.storefront_origin=excluded.storefront_origin
 RETURNING id INTO connection;
 IF connection IS NULL THEN RAISE EXCEPTION 'GOPAY_SANDBOX_SCOPE_INVALID'; END IF;
 PERFORM public.notification_center_provider_connection_internal('gopay',connection);
 RETURN connection;
END $$;
REVOKE ALL ON FUNCTION public.configure_gopay_sandbox_connection_internal(bigint,bigint,text,text,text,bigint[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_gopay_sandbox_connection_internal(bigint,bigint,text,text,text,bigint[],boolean) TO service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('gopay.checkout.token.minute','gopay.checkout','actor','rolling',60,60,5,10),
 ('gopay.checkout.unit.minute','gopay.checkout','unit','rolling',60,60,100,200),
 ('gopay.checkout.organization.day','gopay.checkout','organization','rolling',86400,3600,5000,10000)
 ON CONFLICT(rule_key) DO NOTHING;
