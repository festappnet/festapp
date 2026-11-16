-- Customer-facing collection eligibility is separate from financial history.
CREATE OR REPLACE FUNCTION public.payment_collection_action_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; oc public.occasions; policy jsonb; allowed boolean; reason text; fin record; template_audit jsonb; availability jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.id IS NULL THEN RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',NULL,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','no_payment_identity'); END IF;
 SELECT * INTO STRICT oc FROM public.occasions WHERE id=o.occasion;
 IF NOT EXISTS(SELECT 1 FROM public.units WHERE id=oc.unit AND organization=oc.organization) THEN
  RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','payment_policy_scope_mismatch');
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=o.form AND occasion=o.occasion) THEN
  RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,'allowed',false,'policyRevision','0','reason','collection_form_unavailable');
 END IF;
 policy:=public.resolve_payment_method_policy_internal(oc.organization,oc.unit);
 SELECT * INTO fin FROM public.payment_financial_totals_bulk_internal(ARRAY[pi.id]);
 availability:=public.form_payment_availability_internal(o.form);
 allowed:=coalesce(policy#>ARRAY['methods',pi.payment_method,'policyEnabled']='true'::jsonb,false)
  AND o.state IN ('ordered','created','paid','sent') AND pi.amount>coalesce(fin.net_received,0)
  AND NOT coalesce(fin.invalid_identity,true) AND coalesce(fin.disputed,0)=0
  AND (pi.deadline>now() OR (pi.payment_method IN ('bank','cash') AND (pi.data#>>'{payment_policy,mode}'='none' OR pi.deposit_amount IS NOT NULL)))
  AND CASE WHEN public.payment_method_is_online_internal(pi.payment_method) THEN availability#>ARRAY['providers',pi.payment_method,'collectionAvailable']='true'::jsonb ELSE availability->'available' ? pi.payment_method END;
 template_audit:=public.payment_template_audit_internal(o.occasion);
 IF public.payment_method_is_online_internal(pi.payment_method) THEN
  allowed:=allowed AND template_audit->'compatible'='true'::jsonb AND (
   public.payment_method_policy_enabled_internal(oc.unit,'bank') OR template_audit->'reviewed'='true'::jsonb);
 END IF;
 reason:=CASE WHEN policy#>ARRAY['methods',pi.payment_method,'policyEnabled'] IS DISTINCT FROM 'true'::jsonb THEN 'method_policy_disabled'
  WHEN NOT coalesce(allowed,false) THEN 'collection_unavailable' END;
 RETURN jsonb_build_object('action','collect_payment','purpose','collect_payment','method',pi.payment_method,'sourceOrderId',o.id,
  'allowed',coalesce(allowed,false),'policyRevision',coalesce(policy#>>ARRAY['methods',pi.payment_method,'revision'],'0')||':'||coalesce(template_audit->>'revision',''),'reason',reason);
END $$;
REVOKE ALL ON FUNCTION public.payment_collection_action_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
