CREATE OR REPLACE FUNCTION public.import_payment_reference(
 p_bank_account bigint,p_source text,p_symbol bigint,p_payload_sha256 text,
 p_payment bigint DEFAULT NULL,p_form bigint DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ns eshop.payment_reference_namespaces; old eshop.payment_reference_reservations; result uuid;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.check_bank_account_writable(p_bank_account);
 IF p_symbol IS NULL OR p_symbol NOT BETWEEN 0 AND 9999999999 OR p_source IS NULL OR length(p_source) NOT BETWEEN 1 AND 255
 OR p_payload_sha256 IS NULL OR p_payload_sha256 !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_INVALID'; END IF;
 SELECT n.* INTO STRICT ns FROM eshop.payment_reference_namespaces n JOIN eshop.payment_reference_accounts a ON a.namespace_id=n.id
 WHERE a.bank_account_id=p_bank_account FOR UPDATE OF n;
 IF ns.allocation_enabled THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_REQUIRES_LOCK'; END IF;
 IF p_payment IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=p_payment AND bank_account=p_bank_account AND variable_symbol=p_symbol) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_IMPORT_PAYMENT_MISMATCH'; END IF;
 SELECT * INTO old FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND source_ref=p_source;
 IF old.id IS NOT NULL THEN
  IF old.variable_symbol<>p_symbol OR old.payload_sha256<>p_payload_sha256 OR old.original_payment_info_id IS DISTINCT FROM p_payment OR old.form_id IS DISTINCT FROM p_form THEN
   RAISE EXCEPTION 'PAYMENT_REFERENCE_SOURCE_CONFLICT'; END IF;
  RETURN old.id;
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_reference_reservations WHERE namespace_id=ns.id AND variable_symbol=p_symbol) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_HISTORICAL_CONFLICT'; END IF;
 INSERT INTO eshop.payment_reference_reservations(namespace_id,variable_symbol,source_ref,policy,payload_sha256,payment_info_id,original_payment_info_id,form_id)
 VALUES(ns.id,p_symbol,p_source,'{"mode":"historical"}',p_payload_sha256,p_payment,p_payment,p_form) RETURNING id INTO result;
 IF p_form IS NOT NULL THEN
  INSERT INTO eshop.payment_reference_form_watermarks(form_id,high_water) VALUES(p_form,p_symbol)
  ON CONFLICT(form_id) DO UPDATE SET high_water=greatest(eshop.payment_reference_form_watermarks.high_water,excluded.high_water);
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.import_payment_reference(bigint,text,bigint,text,bigint,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.import_payment_reference(bigint,text,bigint,text,bigint,bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.activate_payment_reference_scope(p_organization bigint,p_manifest_sha256 text,p_history_reviewed boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE namespace text; namespaces text[];
BEGIN
 PERFORM public.require_service_role();
 IF p_history_reviewed IS DISTINCT FROM true OR p_manifest_sha256 IS NULL OR p_manifest_sha256 !~ '^[a-f0-9]{64}$'
  OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACTIVATION_REVIEW_REQUIRED'; END IF;
 -- Drain old order writers at their existing form locks before enabling the scope.
 PERFORM 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE o.organization=p_organization ORDER BY f.id FOR UPDATE OF f;
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
  JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
  JOIN eshop.bank_accounts b ON b.id=u.bank_account
  LEFT JOIN eshop.payment_reference_accounts a ON a.bank_account_id=b.id
  WHERE o.organization=p_organization AND b.type IS DISTINCT FROM 'CASH' AND NOT public.is_demo_occasion(o.id) AND a.bank_account_id IS NULL) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_NOT_ENROLLED'; END IF;
 SELECT array_agg(DISTINCT a.namespace_id ORDER BY a.namespace_id) INTO namespaces FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
 JOIN eshop.payment_reference_accounts a ON a.bank_account_id=u.bank_account WHERE o.organization=p_organization AND NOT public.is_demo_occasion(o.id);
 IF namespaces IS NULL THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_NO_ENROLLED_DESTINATION'; END IF;
 FOREACH namespace IN ARRAY namespaces LOOP
  PERFORM 1 FROM eshop.payment_reference_namespaces WHERE id=namespace FOR UPDATE;
 END LOOP;
 -- Conservative: all configured destination candidates sharing a physical account
 -- must participate. An unenrolled alias cannot evade the writer inventory.
 IF EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN eshop.unit_bank_accounts u ON u.unit=o.unit AND (f.bank_account IS NULL OR f.bank_account=u.bank_account)
 JOIN eshop.bank_accounts b ON b.id=u.bank_account JOIN eshop.payment_reference_namespaces n ON n.id=ANY(namespaces)
  AND public.try_payment_reference_account_internal(b.account_number)=n.canonical_account
 WHERE o.organization<>p_organization AND b.type IS DISTINCT FROM 'CASH' AND NOT public.is_demo_occasion(o.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.payment_reference_scopes s WHERE s.organization_id=o.organization AND s.phase='active')) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_UNMIGRATED_SHARED_WRITER'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.payment_info p JOIN eshop.bank_accounts b ON b.id=p.bank_account
 JOIN eshop.payment_reference_namespaces n ON n.id=ANY(namespaces) AND public.try_payment_reference_account_internal(b.account_number)=n.canonical_account
 WHERE p.amount>0 AND p.variable_symbol IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM eshop.payment_reference_reservations r WHERE r.namespace_id=n.id AND r.variable_symbol=p.variable_symbol AND r.original_payment_info_id=p.id)) THEN
  RAISE EXCEPTION 'PAYMENT_REFERENCE_HISTORY_NOT_IMPORTED'; END IF;
 UPDATE eshop.payment_reference_namespaces SET allocation_enabled=true,manifest_sha256=p_manifest_sha256 WHERE id=ANY(namespaces);
 INSERT INTO eshop.payment_reference_scopes(organization_id,phase,manifest_sha256) VALUES(p_organization,'active',p_manifest_sha256)
 ON CONFLICT(organization_id) DO UPDATE SET phase='active',manifest_sha256=excluded.manifest_sha256,updated_at=clock_timestamp();
END $$;
REVOKE ALL ON FUNCTION public.activate_payment_reference_scope(bigint,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_payment_reference_scope(bigint,text,boolean) TO service_role;
