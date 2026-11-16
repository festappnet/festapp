-- Operator-managed sandbox installation only. This neither discovers keys nor
-- attests production merchant/marketplace/refund eligibility.
CREATE OR REPLACE FUNCTION public.configure_barion_sandbox_connection_internal(p_organization bigint,p_unit bigint,p_shop text,p_name text,p_forms bigint[],p_enabled boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE existing eshop.barion_connections; connection uuid;
BEGIN
 PERFORM public.require_service_role();
 IF p_shop IS NULL OR p_shop !~ '^[a-f0-9]{32}$' OR nullif(p_name,'') IS NULL OR p_forms IS NULL OR cardinality(p_forms)>20 OR p_enabled IS NULL
  OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=p_unit AND organization=p_organization)
  OR EXISTS(SELECT 1 FROM unnest(p_forms) fid WHERE fid IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion WHERE f.id=fid AND oc.unit=p_unit AND oc.organization=p_organization))
  THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO existing FROM eshop.barion_connections WHERE account_id=p_shop FOR UPDATE;
 IF existing.id IS NOT NULL AND (existing.unit_id<>p_unit OR existing.organization_id<>p_organization) THEN RAISE EXCEPTION 'BARION_SANDBOX_SCOPE_INVALID'; END IF;
 INSERT INTO eshop.barion_connections(organization_id,unit_id,account_id,business_name,sandbox_form_ids,enabled) VALUES(p_organization,p_unit,p_shop,p_name,p_forms,p_enabled)
 ON CONFLICT(account_id) DO UPDATE SET business_name=excluded.business_name,sandbox_form_ids=excluded.sandbox_form_ids,enabled=excluded.enabled RETURNING id INTO connection;
 PERFORM public.notification_center_provider_connection_internal('barion',connection);
 RETURN connection;
END $$;
REVOKE ALL ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_barion_sandbox_connection_internal(bigint,bigint,text,text,bigint[],boolean) TO service_role;
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap) VALUES
 ('barion.checkout.token.minute','barion.checkout','actor','rolling',60,60,5,10),
 ('barion.checkout.unit.minute','barion.checkout','unit','rolling',60,60,100,200),
 ('barion.checkout.organization.day','barion.checkout','organization','rolling',86400,3600,5000,10000)
 ON CONFLICT(rule_key) DO NOTHING;
