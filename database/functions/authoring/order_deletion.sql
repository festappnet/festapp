-- The ordinary deletion context/SQL receipt and Fakturoid gateway remain the
-- effect owners. Scope and inspected revision fence their delegated transport.
CREATE OR REPLACE FUNCTION public.check_delegated_order_deletion_scope_internal_v1(p_occasion bigint,p_organization bigint,p_unit bigint,p_order bigint,p_command_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_delete_orders(p_occasion) OR NOT EXISTS(
  SELECT 1 FROM public.occasions o JOIN public.user_info viewer ON viewer.id=auth.uid() AND viewer.organization=o.organization
  WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit)) OR NOT (
  EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion)
  OR EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND occasion=p_occasion AND actor_id=auth.uid() AND command_name='inventory.order.delete'
   AND request_sha256=encode(extensions.digest(convert_to(jsonb_build_object('order',p_order)::text,'UTF8'),'sha256'),'hex'))) THEN RAISE insufficient_privilege USING MESSAGE='order deletion unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_delegated_order_deletion_scope_internal_v1(bigint,bigint,bigint,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_delegated_order_deletion_context(p_occasion bigint,p_organization bigint,p_unit bigint,p_order bigint,p_command_id uuid DEFAULT NULL,p_expected_revision text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 -- Deny unauthorized targets before acquiring a global send fence or foreign locks.
 PERFORM public.check_delegated_order_deletion_scope_internal_v1(p_occasion,p_organization,p_unit,p_order,p_command_id);
 -- Preserve the canonical email -> form -> order/capacity -> occasion order.
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM 1 FROM public.forms WHERE id=(SELECT form FROM eshop.orders WHERE id=p_order) FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order) THEN PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]); END IF;
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit,false);
 PERFORM public.check_delegated_order_deletion_scope_internal_v1(p_occasion,p_organization,p_unit,p_order,p_command_id);
 result:=public.get_order_deletion_context_v1(p_order,p_command_id);
 IF result ? 'response' THEN RETURN result; END IF;
 IF p_expected_revision IS NOT NULL AND p_expected_revision IS DISTINCT FROM public.operator_order_revision_internal_v1(p_order) THEN RAISE serialization_failure USING MESSAGE='order changed before deletion'; END IF;
 RETURN result||jsonb_build_object('revision',public.operator_order_revision_internal_v1(p_order));
END $$;
REVOKE ALL ON FUNCTION public.get_delegated_order_deletion_context(bigint,bigint,bigint,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_delegated_order_deletion_context(bigint,bigint,bigint,bigint,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_delegated_order_client_sync_v1(p_occasion bigint,p_organization bigint,p_unit bigint,p_order bigint,p_command_id uuid,p_expected_revision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_expected_revision IS NULL OR p_expected_revision !~ '^[a-f0-9]{64}$' THEN RAISE invalid_parameter_value USING MESSAGE='original deletion revision required'; END IF;
 result:=public.get_delegated_order_deletion_context(p_occasion,p_organization,p_unit,p_order,p_command_id,p_expected_revision);
 IF result ? 'response' THEN RETURN result->'response'; END IF;
 RETURN public.delete_order_client_sync_v1(p_order,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.delete_delegated_order_client_sync_v1(bigint,bigint,bigint,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_delegated_order_client_sync_v1(bigint,bigint,bigint,bigint,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_history_client_sync_v1(p_history_id bigint,p_command_id uuid,p_occasion bigint DEFAULT NULL,p_organization bigint DEFAULT NULL,p_unit bigint DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE order_id bigint; occasion_id bigint; unit_id bigint; hash text; receipt public.client_mutation_receipts; begun jsonb;
BEGIN
 IF auth.uid() IS NULL OR p_command_id IS NULL THEN RAISE insufficient_privilege USING MESSAGE='authenticated history command required'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('history',p_history_id)::text,'sha256'),'hex');
 SELECT h."order",o.occasion,oc.unit INTO order_id,occasion_id,unit_id FROM eshop.orders_history h JOIN eshop.orders o ON o.id=h."order" JOIN public.occasions oc ON oc.id=o.occasion WHERE h.id=p_history_id;
 SELECT * INTO receipt FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='unit.order_history.delete' AND request_sha256=hash;
 IF occasion_id IS NULL AND receipt.status IN ('completed','expired') THEN
  order_id:=(receipt.response#>>'{data,orderId}')::bigint;occasion_id:=(receipt.response#>>'{data,occasionId}')::bigint;
  SELECT unit INTO unit_id FROM public.occasions WHERE id=occasion_id;
 END IF;
 IF occasion_id IS NULL OR (p_order IS NOT NULL AND p_order<>order_id) OR (p_occasion IS NOT NULL AND p_occasion<>occasion_id) THEN RAISE insufficient_privilege USING MESSAGE='history entry unavailable'; END IF;
 PERFORM public.lock_people_scope_internal_v1(occasion_id,p_organization,p_unit);
 IF NOT public.can_manage_unit_configuration(unit_id) OR public.is_demo_unit(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='organizer manager required'; END IF;
 IF receipt.status='completed' THEN RETURN receipt.response; ELSIF receipt.status='expired' THEN RETURN public.expired_client_mutation_response_v1(receipt); END IF;
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.order_history.delete',unit_id,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 PERFORM public.delete_order_history(p_history_id);
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,unit_id,'unit.order_history.delete','order_history',p_history_id,'delete',jsonb_build_object('historyId',p_history_id,'orderId',order_id,'occasionId',occasion_id));
END $$;
REVOKE ALL ON FUNCTION public.delete_order_history_client_sync_v1(bigint,uuid,bigint,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_order_history_client_sync_v1(bigint,uuid,bigint,bigint,bigint,bigint) TO authenticated;
