-- Apply unit bank account priorities in one receipted command.

-- SOURCE: units/begin_unit_client_mutation_v1.sql
CREATE OR REPLACE FUNCTION public.begin_unit_client_mutation_v1(p_command_id uuid, p_command_name text, p_unit bigint, p_actor_id uuid, p_request_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid()
     OR p_command_id IS NULL OR p_unit IS NULL
     OR p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR NOT (CASE WHEN p_command_name IN ('occasion.create','occasion.setup.finalize')
       THEN public.can_create_occasion(p_unit)
       WHEN p_command_name='occasion.delete' THEN public.can_delete_occasion_in_unit(p_unit)
       WHEN p_command_name IN ('unit.information.save','unit.information.delete')
         THEN public.can_write_unit_information(p_unit)
       WHEN p_command_name IN ('unit.icon.save','unit.icon.delete')
         THEN public.can_write_unit_icons(p_unit)
       WHEN p_command_name IN ('unit.email_template.save','unit.email_template.reset','unit.email_banner.save')
         THEN public.can_write_unit_email_templates(p_unit)
       WHEN p_command_name IN ('profile.unit_access.delete','profile.unit_user.save','profile.unit_membership.add') THEN public.can_manage_unit_users(p_unit)
       WHEN p_command_name='unit.config.save' THEN public.can_manage_unit_configuration(p_unit)
       WHEN p_command_name IN ('unit.cards.pause','unit.cards.disconnect') THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name='unit.order_history.delete' THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name='unit.delete' THEN public.can_manage_unit_configuration(p_unit) AND NOT public.is_demo_unit(p_unit)
       WHEN p_command_name IN ('unit.legal.save','unit.legal.submit') THEN public.can_manage_unit_legal_profile(p_unit)
       WHEN p_command_name IN ('unit.bank.save','unit.bank.link','unit.bank.user','unit.bank.reorder') THEN public.can_manage_unit_bank_accounts(p_unit)
       WHEN p_command_name='occasion.duplicate' THEN public.can_copy_occasion_target(p_unit)
       ELSE false END) THEN
    RAISE insufficient_privilege USING MESSAGE='invalid unit mutation receipt claim';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,unit,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_unit,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS NOT NULL OR v_receipt.unit IS DISTINCT FROM p_unit
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id OR v_receipt.actor_client_id IS NOT NULL
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $function$
;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(p_command_id uuid, p_command_name text, p_unit bigint, p_actor_id uuid, p_request_sha256 text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.begin_unit_client_mutation_v1(uuid,text,bigint,uuid,text) TO service_role;

-- SOURCE: authoring/finance.sql
CREATE OR REPLACE FUNCTION public.manage_bank_authoring(
 p_unit bigint,p_organization bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE unit_id bigint:=p_unit; bank bigint:=(p_payload->>'accountId')::bigint; result jsonb; begun jsonb; hash text; lim int:=coalesce((p_payload->>'limit')::int,50); ident bigint;
 current_order bigint[]; expected_order bigint[]; requested_order bigint[];
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
 ELSIF p_action='reorder' THEN
  IF NOT public.can_manage_unit_bank_accounts(unit_id) THEN RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  PERFORM public.require_bank_authoring_scope_internal(NULL,unit_id);
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
 IF p_action NOT IN ('save','link','user','reorder') OR p_command_id IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='bank command required'; END IF;
 hash:=encode(extensions.digest(jsonb_build_object('unit',unit_id,'action',p_action,'payload',p_payload)::text,'sha256'),'hex');
 begun:=public.begin_unit_client_mutation_v1(p_command_id,'unit.bank.'||p_action,unit_id,auth.uid(),hash);
 IF begun->>'disposition'='replay' THEN RETURN begun->'response'; END IF;
 IF p_action='save' THEN
  ident:=public.update_bank_account(bank,p_payload->>'accountNumber',p_payload->>'title',p_payload->>'type',
   CASE WHEN p_payload->'currencies' IS NULL OR p_payload->'currencies'='null'::jsonb THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text(p_payload->'currencies')) END,p_payload->>'displayNumber',unit_id,p_payload->>'creditorName');
  result:=jsonb_build_object('accountId',ident,'detailsSyncPending',EXISTS(SELECT 1 FROM eshop.bank_sync_operations WHERE bank_account_id=ident AND operation='update_details' AND state<>'completed'));
 ELSIF p_action='reorder' THEN
  IF jsonb_typeof(p_payload->'expectedOrder') IS DISTINCT FROM 'array'
    OR jsonb_typeof(p_payload->'accountOrder') IS DISTINCT FROM 'array' THEN
   RAISE invalid_parameter_value USING MESSAGE='bank account order arrays required';
  END IF;
  expected_order:=ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'expectedOrder') WITH ORDINALITY AS item(value,position) ORDER BY position);
  requested_order:=ARRAY(SELECT value::bigint FROM jsonb_array_elements_text(p_payload->'accountOrder') WITH ORDINALITY AS item(value,position) ORDER BY position);
  -- The unit authoring lock serializes organizer link and reorder commands.
  SELECT ARRAY(SELECT l.bank_account FROM eshop.unit_bank_accounts l
   JOIN eshop.bank_accounts a ON a.id=l.bank_account
   WHERE l.unit=unit_id AND a.type <> 'CASH'
   ORDER BY coalesce(l.priority,0),l.bank_account FOR UPDATE OF l) INTO current_order;
  IF expected_order IS DISTINCT FROM current_order THEN
   RAISE serialization_failure USING MESSAGE='BANK_ACCOUNT_ORDER_CHANGED';
  END IF;
  IF cardinality(requested_order) <> cardinality(current_order)
    OR NOT (requested_order @> current_order AND current_order @> requested_order) THEN
   RAISE invalid_parameter_value USING MESSAGE='bank account order must include each linked account once';
  END IF;
  PERFORM public.check_bank_account_writable(account_id) FROM unnest(requested_order) AS requested(account_id);
  UPDATE eshop.unit_bank_accounts l SET priority=(requested.position-1)::int
   FROM unnest(requested_order) WITH ORDINALITY AS requested(account_id,position)
   WHERE l.unit=unit_id AND l.bank_account=requested.account_id;
  RETURN public.complete_unit_mutation_internal_v1(p_command_id,unit_id,'unit.bank.reorder','unit',unit_id,'update',
    jsonb_build_object('accountOrder',requested_order));
 ELSIF p_action='user' THEN
  PERFORM public.update_bank_account_user(bank,p_payload->>'email',(p_payload->>'isAdmin')::boolean,(p_payload->>'isSupport')::boolean);
  result:=jsonb_build_object('accountId',bank);
 ELSE
  PERFORM public.link_bank_account_to_unit(bank,unit_id,(p_payload->>'priority')::int,coalesce((p_payload->>'force')::boolean,false));
  result:=jsonb_build_object('accountId',bank,'priority',p_payload->'priority');
 END IF;
 RETURN public.complete_unit_mutation_internal_v1(p_command_id,unit_id,'unit.bank.'||p_action,'bank_account',coalesce(ident,bank),CASE WHEN p_action='save' AND bank IS NULL THEN 'insert' ELSE 'update' END,result);
END $$;
