-- Typed organizer operation. Service credentials are not a customer entitlement.
CREATE OR REPLACE FUNCTION public.can_manage_customer_order_policy(p_form bigint,p_automatic_refund boolean)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT auth.uid() IS NOT NULL AND public.can_author_forms(f.occasion)
  AND (NOT p_automatic_refund OR (public.get_is_manager_on_unit(o.unit) AND NOT public.is_demo_occasion(o.id)))
  FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_form),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_customer_order_policy(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_customer_order_policy(bigint,boolean) TO authenticated;

-- Scoped customer write authorization, independent of every staff role.
CREATE OR REPLACE FUNCTION public.authorize_customer_change_internal(p_token text,p_command uuid DEFAULT NULL)
RETURNS eshop.customer_order_change_capabilities LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE c eshop.customer_order_change_capabilities;
BEGIN
 IF p_token IS NULL OR p_token!~'^[a-f0-9]{64}$' THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 SELECT cap.* INTO c FROM eshop.customer_order_change_capabilities cap
 JOIN eshop.waitlist_capabilities parent ON parent.token_hash=cap.parent_hash AND parent.order_id=cap.order_id
 JOIN eshop.orders o ON o.id=cap.order_id JOIN public.occasions oc ON oc.id=o.occasion
 JOIN eshop.customer_order_change_policies policy ON policy.form_id=cap.form_id
 WHERE cap.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp()
 AND parent.revoked_at IS NULL AND parent.expires_at>statement_timestamp() AND parent.kind='order_view'
 AND parent.organization_id=cap.organization_id AND parent.form_id=o.form AND oc.organization=cap.organization_id
 AND (o.form=cap.form_id OR (cap.consumed_by=p_command AND o.form=cap.consumed_form_id))
 AND policy.revision=cap.policy_revision AND oc.customer_self_service_epoch=cap.feature_epoch
 AND (CASE WHEN cap.operation='withdraw' THEN public.customer_order_feature_enabled_internal(cap.form_id) ELSE public.customer_order_operation_enabled_internal(cap.form_id,cap.operation) END)
 AND (cap.consumed_by IS NULL OR cap.consumed_by=p_command);
 IF c.id IS NULL THEN RAISE insufficient_privilege USING MESSAGE='INVALID_CAPABILITY'; END IF;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION public.authorize_customer_change_internal(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
