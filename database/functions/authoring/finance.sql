-- Shared transport for current organizer bank management. Existing typed
-- predicates and bank writers own all policy, normalization and provider intents.
CREATE OR REPLACE FUNCTION public.manage_bank_authoring(
 p_unit bigint,p_organization bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE unit_id bigint:=p_unit; bank bigint:=(p_payload->>'accountId')::bigint; result jsonb; begun jsonb; hash text; lim int:=coalesce((p_payload->>'limit')::int,50); ident bigint;
BEGIN
 IF unit_id IS NULL AND bank IS NOT NULL THEN
  SELECT r.unit INTO unit_id FROM public.client_mutation_receipts r WHERE r.command_id=p_command_id AND r.actor_id=auth.uid() AND r.command_name='unit.bank.'||p_action;
  IF unit_id IS NULL THEN
   SELECT link.unit INTO unit_id FROM eshop.unit_bank_accounts link WHERE link.bank_account=bank
    AND public.can_manage_bank_account(bank) AND public.can_manage_unit_bank_accounts(link.unit) ORDER BY link.unit LIMIT 1;
  END IF;
 END IF;
 PERFORM public.lock_people_scope_internal_v1(NULL,p_organization,unit_id);
 IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>16384 OR lim NOT BETWEEN 1 AND 100 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid bank request'; END IF;
 IF p_action='list' THEN
  -- Preserve the ordinary demo read rule, but never its connection secrets.
  IF NOT public.can_read_unit_bank_accounts(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='bank reader required'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]') INTO result FROM (
   SELECT b.id,b.title,b.account_number AS "accountNumber",b.account_number_human_readable AS "displayNumber",b.creditor_name AS "creditorName",b.type,b.supported_currencies AS currencies,l.priority,
    public.can_manage_bank_account(b.id) AS "canManage"
   FROM eshop.unit_bank_accounts l JOIN eshop.bank_accounts b ON b.id=l.bank_account
   WHERE l.unit=unit_id AND (p_payload->>'after' IS NULL OR b.id>(p_payload->>'after')::bigint) ORDER BY b.id LIMIT lim) page;
  RETURN jsonb_build_object('items',result);
 ELSIF p_action='candidates' THEN
  IF NOT public.can_manage_unit_bank_accounts(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]') INTO result FROM (
   SELECT b.id,b.title,b.account_number AS "accountNumber",b.type FROM eshop.bank_accounts b
   WHERE public.can_link_bank_account_to_unit(b.id,unit_id) AND (p_payload->>'after' IS NULL OR b.id>(p_payload->>'after')::bigint) ORDER BY b.id LIMIT lim) page;
  RETURN jsonb_build_object('items',result);
 END IF;
 -- Stored link is required for every account operation except explicit linking.
 IF p_action='link' THEN
  PERFORM 1 FROM eshop.unit_bank_accounts WHERE unit=unit_id AND bank_account=bank FOR UPDATE;
  IF (p_payload->>'priority' IS NULL OR FOUND) THEN
   IF NOT public.can_manage_unit_bank_accounts(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  ELSIF NOT public.can_link_bank_account_to_unit(bank,unit_id) THEN RAISE insufficient_privilege USING MESSAGE='bank admin and target unit manager required'; END IF;
 ELSIF p_action='save' AND bank IS NULL THEN
  IF NOT public.can_manage_unit_bank_accounts(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 ELSE
  PERFORM 1 FROM eshop.unit_bank_accounts WHERE unit=unit_id AND bank_account=bank FOR SHARE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='bank is not linked to selected unit'; END IF;
  PERFORM 1 FROM eshop.bank_account_users WHERE bank_account=bank AND "user"=auth.uid() FOR SHARE;
  IF p_action='users' THEN
   IF NOT public.can_read_bank_account_users(bank,unit_id) THEN RAISE insufficient_privilege USING MESSAGE='bank user reader required'; END IF;
  ELSIF NOT public.can_manage_unit_bank_accounts(unit_id) OR NOT public.can_manage_bank_account(bank) THEN RAISE insufficient_privilege USING MESSAGE='bank admin and selected linked manager required'; END IF;
 END IF;
 IF p_action='users' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.user_id),'[]') INTO result FROM (
   SELECT * FROM public.get_bank_account_users(bank,unit_id) x
   WHERE p_payload->>'afterUser' IS NULL OR x.user_id>(p_payload->>'afterUser')::uuid ORDER BY x.user_id LIMIT lim) page;
  RETURN jsonb_build_object('items',result);
 ELSIF p_action='status' THEN
  result:=public.get_bank_sync_connection(bank);
  RETURN jsonb_build_object('connection',CASE WHEN result IS NULL THEN NULL ELSE result-ARRAY['receiving_address','remote_bank_account_id','last_error'] END);
 ELSIF p_action='operations' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."createdAt" DESC,page.id DESC),'[]') INTO result FROM (
   SELECT id,operation,state,created_at AS "createdAt",updated_at AS "updatedAt" FROM eshop.bank_sync_operations
   WHERE bank_account_id=bank AND (p_payload->>'before' IS NULL OR (created_at,id)<((p_payload#>>'{before,createdAt}')::timestamptz,(p_payload#>>'{before,id}')::uuid))
   ORDER BY created_at DESC,id DESC LIMIT lim) page;
  RETURN jsonb_build_object('items',result);
 ELSIF p_action='observations' THEN
  -- The canonical observation owner omits source mail bodies and credentials.
  SELECT coalesce(jsonb_agg(jsonb_build_object('deliveryId',x->'delivery_id','receivedAt',x->'received_at','outcome',x->'outcome')),'[]') INTO result FROM jsonb_array_elements(public.get_bank_sync_observations(bank,lim)) x;
  RETURN jsonb_build_object('items',result);
 END IF;
 IF p_action NOT IN ('save','link','user') OR p_command_id IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='bank command required'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('unit',unit_id,'action',p_action,'payload',p_payload)::text,'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.bank.'||p_action,unit_id,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 IF p_action='save' THEN
  ident:=public.update_bank_account(bank,p_payload->>'accountNumber',p_payload->>'title',p_payload->>'type',
   CASE WHEN p_payload->'currencies' IS NULL OR p_payload->'currencies'='null'::jsonb THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text(p_payload->'currencies')) END,p_payload->>'displayNumber',unit_id,p_payload->>'creditorName');
  result:=jsonb_build_object('accountId',ident,'detailsSyncPending',EXISTS(SELECT 1 FROM eshop.bank_sync_operations WHERE bank_account_id=ident AND operation='update_details' AND state<>'completed'));
 ELSIF p_action='user' THEN
  PERFORM public.update_bank_account_user(bank,p_payload->>'email',(p_payload->>'isAdmin')::boolean,(p_payload->>'isSupport')::boolean);
  result:=jsonb_build_object('accountId',bank);
 ELSE
  PERFORM public.link_bank_account_to_unit(bank,unit_id,(p_payload->>'priority')::int,coalesce((p_payload->>'force')::boolean,false));
  result:=jsonb_build_object('accountId',bank,'priority',p_payload->'priority');
 END IF;
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,unit_id,'unit.bank.'||p_action,'bank_account',coalesce(ident,bank),CASE WHEN p_action='save' AND bank IS NULL THEN 'insert' ELSE 'update' END,result);
END $$;
REVOKE ALL ON FUNCTION public.manage_bank_authoring(bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_bank_authoring(bigint,bigint,text,jsonb,uuid) TO authenticated;

-- Scope admission and the original durable provider intent commit together.
CREATE OR REPLACE FUNCTION public.begin_delegated_bank_sync_operation(p_id uuid,p_account_id bigint,p_operation text,p_hash text,p_unit bigint,p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.manage_bank_authoring(p_unit,p_organization,'status',jsonb_build_object('accountId',p_account_id));
 IF p_operation NOT IN ('sync','suspend','resume') THEN RAISE invalid_parameter_value USING MESSAGE='delegated bank operation unsupported'; END IF;
 RETURN public.begin_bank_sync_operation(p_id,p_account_id,p_operation,p_hash);
END $$;
REVOKE ALL ON FUNCTION public.begin_delegated_bank_sync_operation(uuid,bigint,text,text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_delegated_bank_sync_operation(uuid,bigint,text,text,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_card_refund_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_order bigint,p_payload jsonb DEFAULT NULL,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='order scope changed'; END IF;
 IF p_payload IS NULL THEN
  result:=public.get_stripe_order_admin_detail(p_order);
  IF result IS NULL THEN RETURN NULL; END IF;
  RETURN (result-'dashboardUrl')||jsonb_build_object('tickets',(SELECT coalesce(jsonb_agg(x- 'label'),'[]') FROM jsonb_array_elements(result->'tickets') x));
 END IF;
 RETURN public.decide_stripe_partial_refund_client_sync_v1(p_order,p_payload->>'action',ARRAY(SELECT jsonb_array_elements_text(p_payload->'ticketIds'))::bigint[],p_payload->>'note',(p_payload->>'expectedRefundedMinor')::bigint,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.manage_card_refund_authoring(bigint,bigint,bigint,bigint,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_card_refund_authoring(bigint,bigint,bigint,bigint,jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_stripe_unit_paused_client_sync_v1(p_unit bigint,p_livemode boolean,p_paused boolean,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE begun jsonb; hash text;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 hash:=encode(extensions.digest(jsonb_build_object('unit',p_unit,'live',p_livemode,'paused',p_paused)::text,'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.cards.pause',p_unit,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 PERFORM public.set_stripe_unit_paused(p_unit,p_livemode,p_paused);
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.cards.pause','unit',p_unit,'update',jsonb_build_object('state',public.get_stripe_unit_connection(p_unit,p_livemode)));
END $$;
REVOKE ALL ON FUNCTION public.set_stripe_unit_paused_client_sync_v1(bigint,boolean,boolean,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_stripe_unit_paused_client_sync_v1(bigint,boolean,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.begin_stripe_disconnect_client_sync_v1(p_unit bigint,p_livemode boolean,p_expected_connection uuid,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE begun jsonb; hash text; result jsonb;
BEGIN
 PERFORM public.check_stripe_unit_manager_internal(p_unit,auth.uid());
 hash:=encode(extensions.digest(jsonb_build_object('unit',p_unit,'live',p_livemode,'connection',p_expected_connection)::text,'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.cards.disconnect',p_unit,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 result:=public.begin_stripe_disconnect(p_unit,p_livemode,p_expected_connection);
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.cards.disconnect','unit',p_unit,'update',result);
END $$;
REVOKE ALL ON FUNCTION public.begin_stripe_disconnect_client_sync_v1(bigint,boolean,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_stripe_disconnect_client_sync_v1(bigint,boolean,uuid,uuid) TO authenticated;
