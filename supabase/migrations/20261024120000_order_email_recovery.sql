-- Additive order email recovery. No backfill or automatic resend.
-- Source: database/functions/eshop_orders/repair_order_email_client_sync_v1.sql
-- Shared recipient validation. Preserve aliases and local-part spelling.
CREATE OR REPLACE FUNCTION public.normalize_order_email_contact(p_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=public,extensions AS $$
DECLARE v_email text:=btrim(p_email);
BEGIN
 IF length(v_email)>320 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 RETURN v_email;
END $$;
REVOKE ALL ON FUNCTION public.normalize_order_email_contact(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_order_email_contact(text) TO service_role;

-- A read token over the existing payment facts, not a stored/global version.
CREATE OR REPLACE FUNCTION public.order_email_payment_fingerprint(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT encode(extensions.digest(jsonb_build_array(o.payment_info,p.payment_method,p.amount,p.paid,p.returned,
  p.currency_code,p.deadline,p.deposit_amount,p.deposit_deadline,p.variable_symbol,p.creditor_reference,
  p.bank_account,b.account_number,b.account_number_human_readable,b.creditor_name)::text,'sha256'),'hex')
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info
 LEFT JOIN eshop.bank_accounts b ON b.id=p.bank_account WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.order_email_payment_fingerprint(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_payment_fingerprint(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.repair_order_email_client_sync_v1(
 p_order bigint,p_expected_email text,p_expected_state text,p_expected_payment_version bigint,
 p_email text,p_source_message uuid,p_resend boolean,p_command_id uuid,p_expected_payment_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; src public.email_messages; active public.email_messages;
 v_begin jsonb; v_hash text; v_email text; v_form bigint; v_field bigint; v_fields jsonb;
 v_kind text; v_intent jsonb; v_users uuid[]; v_payload jsonb; v_details jsonb; v_origin text;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO oc FROM public.occasions WHERE id=o.occasion;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.can_write_orders(o.occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 -- Re-authorize the object relationship even on receipt replay.
 IF p_source_message IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.message_id=p_source_message AND m.order_id=o.id AND m.occasion=o.occasion
   AND m.organization=oc.organization AND public.email_report_allowed(m.organization,m.occasion,m.recipient_user)) THEN
  RAISE insufficient_privilege USING MESSAGE='order email unavailable'; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'expectedEmail',p_expected_email,
  'expectedState',p_expected_state,'expectedVersion',p_expected_payment_version,'email',p_email,
  'source',p_source_message,'resend',p_resend,'paymentFingerprint',p_expected_payment_fingerprint)::text,'sha256'),'hex');
 v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.order.repair_email',o.occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
 v_form:=o.form;
 -- Same form -> order -> message order as response editing / send fencing.
 IF v_form IS NOT NULL THEN PERFORM 1 FROM public.forms WHERE id=v_form FOR SHARE; END IF;
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL OR o.form IS DISTINCT FROM v_form OR o.data->>'email' IS DISTINCT FROM p_expected_email
  OR o.state IS DISTINCT FROM p_expected_state OR o.email_payment_version IS DISTINCT FROM p_expected_payment_version
  OR p_expected_payment_fingerprint IS DISTINCT FROM public.order_email_payment_fingerprint(o.id) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','order_changed')); END IF;
 PERFORM public.check_occasion_writable(o.occasion);
 IF o.state NOT IN ('ordered','paid','sent') THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF p_resend IS NULL OR p_email IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 v_email:=public.normalize_order_email_contact(p_email);
 v_kind:=CASE WHEN o.state='ordered' THEN 'order_confirmation' ELSE 'order_tickets' END;
 PERFORM 1 FROM public.email_messages WHERE order_id=o.id ORDER BY id FOR UPDATE;
 SELECT * INTO src FROM public.email_messages WHERE message_id=p_source_message;
 IF p_resend AND src.id IS NOT NULL AND (src.message_kind<>v_kind OR src.last_error='post_action_failed') THEN
  RAISE EXCEPTION 'source_not_resendable'; END IF;
 -- An issued permit or unknown outcome cannot be bypassed by changing contact.
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=o.id AND message_kind IN ('order_confirmation','order_tickets')
  AND workflow_state IN ('sending','unknown')) THEN RAISE EXCEPTION 'email_outcome_unresolved'; END IF;
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_email)) THEN
  RAISE EXCEPTION 'email_recipient_suppressed'; END IF;
 IF p_resend THEN
  SELECT * INTO active FROM public.email_messages WHERE order_id=o.id AND message_kind=v_kind
   AND workflow_state IN ('pending','preparing','retry_wait','blocked')
   AND recipient=o.data->>'email' AND source_version=o.email_payment_version
   AND (expires_at IS NULL OR expires_at>now())
   ORDER BY id DESC LIMIT 1;
  IF active.id IS NOT NULL THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
    jsonb_build_object('reason','active_email_intent','messageId',active.message_id)); END IF;
 END IF;
 -- Repair chains have one successor per source. A stale source cannot fork
 -- around a newer failed/waiting attempt, even after its active lease ended.
 IF p_resend AND src.id IS NOT NULL AND EXISTS(SELECT 1 FROM public.email_messages
  WHERE order_id=o.id AND data->>'repair_source_message_id'=src.message_id::text) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
   jsonb_build_object('reason','source_replaced')); END IF;
 -- Update only the existing contact projection, without invoking pricing/stock.
 SELECT min(id) INTO v_field FROM public.form_fields WHERE form=v_form AND type='email';
 IF (SELECT count(*) FROM public.form_fields WHERE form=v_form AND type='email')>1 THEN
  RAISE EXCEPTION 'ambiguous_contact_field'; END IF;
 IF v_field IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(e - v_field::text) FILTER (WHERE e - v_field::text<>'{}'::jsonb),'[]') INTO v_fields
   FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) e;
  o.data:=jsonb_set(o.data,'{fields}',v_fields||jsonb_build_array(jsonb_build_object(v_field::text,v_email)));
 END IF;
 UPDATE eshop.orders SET data=jsonb_set(o.data,'{email}',to_jsonb(v_email)),updated_at=now()
  WHERE id=o.id RETURNING * INTO o;
 INSERT INTO eshop.orders_history("order",state,price,currency_code,data,created_by)
  VALUES(o.id,o.state,o.price,o.currency_code,o.data,auth.uid());
 -- A prepared payload is a snapshot of its recipient; retire pre-permit old
 -- contacts explicitly, including legacy manual ticket snapshots.
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='contact_changed',lease_token=NULL,lease_until=NULL
  WHERE order_id=o.id AND recipient IS DISTINCT FROM v_email
   AND workflow_state IN ('pending','preparing','retry_wait','blocked');
 IF p_resend THEN
  v_payload:=jsonb_build_object('order_id',o.id,'requested_by',auth.uid(),'repair_source_message_id',p_source_message,'repair_payment_fingerprint',p_expected_payment_fingerprint);
  IF v_kind='order_confirmation' THEN
   -- The existing confirmation renderer consumes the canonical checkout shape,
   -- not an order ID. Rebuild it from current facts without a checkout mutation.
   v_details:=public.get_order_details_for_email(o.id)->'data';
   SELECT data->>'command_id' INTO v_origin FROM public.email_messages
    WHERE order_id=o.id AND message_kind='order_confirmation' AND data->>'command_id' IS NOT NULL
    ORDER BY id LIMIT 1;
   v_payload:=v_payload||jsonb_build_object('command_id',v_origin,
    'ticket_order',jsonb_build_object('order',v_details->'order'||jsonb_build_object(
     'occasion',v_details->'occasion','reply_to',v_details->'reply_to',
     'form',jsonb_build_object('id',o.form,'data',v_details->'form_data'),
     'payment_info',coalesce(v_details->'payment_info','{}')||jsonb_build_object(
      'account_number',v_details#>'{bank_account,account_number}',
      'account_number_human_readable',v_details#>'{bank_account,account_number_human_readable}',
      'creditor_name',v_details#>'{bank_account,creditor_name}'))));
  END IF;
  v_intent:=public.enqueue_order_email(CASE v_kind WHEN 'order_confirmation' THEN 'TICKET_ORDER_CONFIRMATION' ELSE 'ORDER_TICKETS' END,
   v_payload,
   oc.organization,oc.id,oc.unit,now(),'repair:'||p_command_id);
  IF v_intent->>'message_id' IS NULL OR coalesce((v_intent->>'replayed')::boolean,false) THEN
   RAISE EXCEPTION 'email_enqueue_rejected'; END IF;
 END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'inventory.order.repair_email',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
    'safeLabel','Order contact','changedFields',jsonb_build_array('data'))),v_users,
  jsonb_build_object('order',to_jsonb(o)||jsonb_build_object('email_payment_fingerprint',public.order_email_payment_fingerprint(o.id)),'intent',v_intent,'sendingRequested',p_resend));
END $$;
REVOKE ALL ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.repair_order_email_client_sync_v1(bigint,text,text,bigint,text,uuid,boolean,uuid,text) TO authenticated;

-- Extend the current registry row in place; no readiness/version transition.
UPDATE public.client_sync_component_sources SET canonical_writers=array_append(canonical_writers,'repair_order_email_client_sync_v1')
 WHERE source_relation='eshop.orders'::regclass AND NOT ('repair_order_email_client_sync_v1'=ANY(canonical_writers));

-- Source: database/functions/eshop/get_order_history.sql
CREATE OR REPLACE FUNCTION public.get_order_history(order_id bigint)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    v_occasion_id bigint;
    v_order_data jsonb;
    v_history_data jsonb;
    v_users_data jsonb;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT o.occasion, to_jsonb(o) || jsonb_build_object('payment_method', pi.payment_method,'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id))
    INTO v_occasion_id, v_order_data
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id = order_id;

    -- Check if the order exists
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
    END IF;

    -- Verify if the current user is an editor for the order's occasion
    IF NOT can_read_orders(v_occasion_id) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this order history');
    END IF;

    -- Fetch history items for the order, ordered by creation date
    SELECT jsonb_agg(to_jsonb(h) || jsonb_build_object('order_symbol', v_order_data->>'order_symbol', 'order_sequence', v_order_data->'order_sequence') ORDER BY h.created_at)
    INTO v_history_data
    FROM eshop.orders_history h
    WHERE h. "order" = order_id;

    -- Fetch unique users who created the history items
    WITH user_ids AS (
        SELECT DISTINCT created_by
        FROM eshop.orders_history
        WHERE "order" = order_id AND created_by IS NOT NULL
    )
    SELECT jsonb_agg(u.*)
    INTO v_users_data
    FROM public.user_info u
    WHERE u.id IN (SELECT created_by FROM user_ids);

    -- Return the combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'order', COALESCE(v_order_data, '{}'::jsonb),
            'history', COALESCE(v_history_data, '[]'::jsonb),
            'users', COALESCE(v_users_data, '[]'::jsonb)
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Source: database/functions/eshop_waitlist/order_overview_email.sql
-- The overview link belongs in existing order emails, never a separate message.
-- Keep historical template and delivery rows; exclude this code from the catalog.
DROP FUNCTION IF EXISTS public.enqueue_order_overview_reissue_v1(bigint,uuid,uuid,jsonb,text);

-- Private renderer boundary. The first ordinary order email creates the source;
-- every later message and split child reuses the root's encrypted source.
CREATE OR REPLACE FUNCTION public.get_order_email_overview_source_v1(
 p_order_id bigint,p_recipient text,p_command_id uuid,p_delivery jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE requested eshop.orders; root eshop.orders; occ public.occasions; f public.forms;
 s eshop.order_overview_sources;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO STRICT requested FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO STRICT root FROM eshop.orders WHERE id=coalesce(requested.source_waitlist_order_id,requested.id) FOR UPDATE;
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=root.occasion;
 SELECT * INTO f FROM public.forms WHERE id=root.form AND occasion=occ.id;
 IF requested.occasion IS DISTINCT FROM root.occasion OR requested.form IS DISTINCT FROM root.form
 OR requested.data->>'email' IS DISTINCT FROM p_recipient THEN
  RAISE EXCEPTION 'INVALID_OVERVIEW_RECIPIENT';
 END IF;
 -- A repaired split child must not receive the root capability covering other
 -- orders at its former contact. Omit that optional link; preserve the root
 -- source and every other order/contact unchanged.
 IF root.data->>'email' IS DISTINCT FROM p_recipient THEN RETURN NULL; END IF;
 -- Orders without a public form have no public overview route.
 IF f.id IS NULL THEN RETURN NULL; END IF;
 SELECT src.* INTO s FROM eshop.order_overview_sources src JOIN eshop.waitlist_capabilities cap USING(token_hash)
 WHERE cap.order_id=root.id AND cap.form_id=f.id AND cap.organization_id=occ.organization
 AND cap.kind='order_view' AND cap.revoked_at IS NULL AND cap.expires_at>statement_timestamp()
 AND src.expires_at=cap.expires_at ORDER BY src.created_at DESC LIMIT 1;
 IF s.token_hash IS NULL THEN
  -- Never silently replace an expired/revoked capability with a different link.
  IF EXISTS(SELECT 1 FROM eshop.waitlist_capabilities WHERE order_id=root.id AND kind='order_view') THEN RETURN NULL; END IF;
  IF p_delivery IS NOT NULL THEN
   PERFORM public.issue_order_overview_internal(root.id,p_delivery,p_command_id);
   SELECT * INTO STRICT s FROM eshop.order_overview_sources WHERE command_id=p_command_id;
  END IF;
 END IF;
 RETURN jsonb_build_object('orderId',root.id,'organization',occ.organization,'occasion',occ.id,'unit',occ.unit,
 'recipient',p_recipient,'occasionTitle',occ.title,'orderSymbol',root.order_symbol,
 'participantCount',(SELECT count(*) FROM public.get_order_tickets_internal(root.id)),
 'formLink',f.link,'webLink',(SELECT data->>'DEFAULT_URL' FROM public.organizations WHERE id=occ.organization),
 'source',CASE WHEN s.token_hash IS NOT NULL THEN jsonb_build_object('sealed',s.sealed,'contentHash',s.content_hash,'tokenHash',s.token_hash,'expiresAt',s.expires_at) END);
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_email_overview_source_v1(bigint,text,uuid,jsonb) TO service_role;

-- Source: database/functions/emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.occasion_team_invitations i
   JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
   JOIN public.unit_users uu ON uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager
   WHERE i.message_id=p_message.message_id AND i.accepted_at IS NULL AND i.expires_at>now()
    AND i.email=p_message.recipient AND i.occasion=p_message.occasion AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method='stripe')
   AND public.stripe_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN v_order.state='ordered' AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method='stripe' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid(); v_wait integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT (x->>'base_limit')::integer INTO v_wait FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.dispatch',NULL,NULL)->'rules') x;
 IF v_wait IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY CASE WHEN m.created_at<=now()-make_interval(secs=>v_wait) THEN 0 ELSE priority END,
 (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.last_claimed_at IS NOT NULL) NULLS FIRST,
 CASE WHEN m.unit IS NULL THEN (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.organization=m.organization AND served.unit IS NULL AND served.last_claimed_at IS NOT NULL)
 ELSE (SELECT max(served.last_claimed_at) FROM public.email_messages served WHERE served.unit=m.unit AND served.last_claimed_at IS NOT NULL) END NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',last_claimed_at=now(),lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF octet_length(p_prepared::text)>(SELECT (x->>'base_limit')::bigint
  FROM jsonb_array_elements(public.abuse_effective_rules_v1('email.payload',NULL,NULL)->'rules') x LIMIT 1) THEN
  RAISE configuration_limit_exceeded USING MESSAGE='email_payload_too_large'; END IF;
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=p_message),true);
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  PERFORM public.notification_center_email_internal(v_row.message_id);
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||v_row.admission_class,v_row.unit,v_row.organization),
   jsonb_build_object('recipient',public.abuse_recipient_key_v1(v_row.recipient)));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  PERFORM public.notification_center_email_internal(v_m.message_id);
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
 PERFORM public.notification_center_email_internal(v_m.message_id);
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  PERFORM public.notification_center_email_internal(v_event.message_id);
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;

-- Source: database/functions/emails/email_domain.sql
-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 IF v_order.state='stock' THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF v_order.data ? 'ticketBatchOrigin' AND nullif(trim(v_order.data->>'email'),'') IS NULL THEN
  RETURN jsonb_build_object('state','skipped','reason','no_recipient'); END IF;
 IF v_order.state='storno' AND p_code<>'TICKET_ORDER_STORNO' THEN
  RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
 END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_storno' AND coalesce(p_request,'') NOT LIKE 'manual:%' THEN
  -- requested_by is audit metadata, never proof of an explicit resend.
  v_recipient:=v_order.data->>'email';
  p_data:=jsonb_build_object('order_id',v_order.id);
  v_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':storno';
  -- Older Edge follow-ups carried requested_by but no explicit resend ID and
  -- used the generic :false key. Reuse that committed identity rather than
  -- manufacture a second automatic message, including cancelled/expired rows.
  SELECT * INTO v_existing FROM public.email_messages
    WHERE organization=p_org AND order_id=v_order.id AND message_kind='order_storno'
      AND recipient=v_recipient AND source_version=v_version
      AND dedupe_key IN (v_key,v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false')
    ORDER BY (dedupe_key=v_key) DESC,id LIMIT 1;
  IF v_existing.id IS NOT NULL THEN v_key:=v_existing.dedupe_key; END IF;
 END IF;
 IF v_kind IN ('order_tickets','order_confirmation') THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false';
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_paid_order_tickets(p_order bigint) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_occ public.occasions;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
 IF v_order.data ? 'ticketBatchOrigin' AND coalesce((v_order.data#>>'{ticketBatchOrigin,sendTickets}')::boolean,false) IS NOT TRUE THEN RETURN; END IF;
 IF v_order.state='paid' AND (v_occ.is_order_synchronization_enabled OR v_order.data ? 'ticketBatchOrigin') AND v_order.data ? 'email'
 AND (coalesce(v_order.price,0)<>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_occ.features) f WHERE f->>'code'='ticket' AND (f->>'is_enabled')::boolean)) THEN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order),v_occ.organization,v_occ.id,v_occ.unit);
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_order_email_intents(p_order bigint) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='payment_changed',lease_token=NULL,lease_until=NULL
 WHERE order_id=p_order AND message_kind IN ('order_payment_notice','order_tickets','order_reminder') AND workflow_state IN ('pending','retry_wait','blocked','preparing');
END $$;

CREATE OR REPLACE FUNCTION public.apply_email_post_actions(p_message uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m record; v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 FOR m IN SELECT * FROM public.email_messages WHERE workflow_state='accepted' AND post_action_state='pending'
 AND (p_message IS NULL OR message_id=p_message) ORDER BY id LIMIT 20 LOOP
  -- Domain producers lock order before message; follow that order before owning the projection.
  IF m.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=m.order_id FOR UPDATE; END IF;
  SELECT * INTO m FROM public.email_messages WHERE id=m.id AND workflow_state='accepted' AND post_action_state='pending' FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  BEGIN
   IF m.message_kind='order_tickets' THEN
    -- Never resurrect a used/storno ticket or a reverted/cancelled order.
    UPDATE eshop.orders SET state='sent',updated_at=now() WHERE id=m.order_id AND state='paid' AND email_payment_version=m.source_version;
    IF FOUND THEN
     UPDATE eshop.tickets t SET state='sent',updated_at=now()
     FROM eshop.order_product_ticket opt WHERE opt.ticket=t.id AND opt."order"=m.order_id AND t.state='paid'
      AND t.id IN (SELECT jsonb_array_elements_text(m.post_action->'ticket_ids')::bigint);
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code) SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=m.order_id;
    END IF;
   END IF;
   IF m.message_kind='app_links' AND m.recipient_user IS NOT NULL THEN PERFORM public.mark_app_links_sent(m.occasion,m.recipient_user); END IF;
   IF m.message_kind='deletion_confirm' AND m.post_action ? 'deletion_request' THEN PERFORM public.set_account_deletion_email_state((m.post_action->>'deletion_request')::uuid,true); END IF;
   IF m.post_action ? 'history_id' THEN PERFORM public.add_sent_to_customer_flag((m.post_action->>'history_id')::bigint); END IF;
   IF m.message_kind='order_reminder' THEN
    UPDATE eshop.payment_info SET data=coalesce(data,'{}')||'{"current_version_reminded":true}'::jsonb
    WHERE id=(m.post_action->>'payment_info_id')::bigint AND email_reminder_version=m.source_version;
   END IF;
   UPDATE public.email_messages SET post_action_state='done',last_error=CASE WHEN last_error='post_action_failed' THEN NULL ELSE last_error END WHERE id=m.id;
  EXCEPTION WHEN OTHERS THEN UPDATE public.email_messages SET last_error='post_action_failed' WHERE id=m.id; END;
 END LOOP;
END $$;

-- Account-domain writes and their durable intent are one DB transaction.
CREATE OR REPLACE FUNCTION public.enqueue_account_email(p_operation text,p_domain jsonb,p_context jsonb,p_recipient text,p_sealed jsonb,p_content_hash text,p_dedupe text,p_code text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_context jsonb:=p_context; v_kind text; v_result jsonb; v_domain_result jsonb; v_user uuid:=(p_domain->>'user_id')::uuid; v_source jsonb:='{}'; v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 PERFORM pg_advisory_xact_lock(hashtextextended('email-account:'||(p_context->>'organization')||':'||coalesce(v_user::text,p_dedupe)||':'||p_operation,0));
 -- Command replay is checked before generating/replacing the domain proof.
 SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND dedupe_key=p_dedupe;
 IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true,'domain',
  CASE WHEN p_operation='register' THEN (SELECT jsonb_build_object('code',200,'id',recipient_user) FROM public.email_messages WHERE message_id=v_message) ELSE NULL END); END IF;
 -- Older clients have no stable request ID. Join any unresolved proof instead of rotating it on a timeout retry.
 IF p_operation IN ('reset_token','deletion_confirm') AND v_user IS NOT NULL THEN
  SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND recipient_user=v_user
   AND message_kind=CASE WHEN p_operation='reset_token' THEN 'reset_password' ELSE 'deletion_confirm' END
   AND (workflow_state IN ('pending','preparing','sending','retry_wait','unknown') OR (p_operation='reset_token' AND workflow_state='accepted')) AND expires_at>now() ORDER BY id DESC LIMIT 1;
  IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true);END IF;
 END IF;
 IF p_operation='reset_token' THEN
  v_kind:='reset_password';
  IF NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=v_user AND organization=(p_context->>'organization')::bigint) THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  INSERT INTO public.user_reset_token("user",token,created_at) VALUES(v_user,(p_domain->>'token')::uuid,now()) ON CONFLICT("user") DO UPDATE SET token=excluded.token,created_at=excluded.created_at;
  v_source:=jsonb_build_object('reset_hash',encode(extensions.digest(p_domain->>'token','sha256'),'hex'));
 ELSIF p_operation='register' THEN
  v_kind:='registration';
  v_domain_result:=public.create_user_from_registration((p_context->>'organization')::bigint,p_recipient,coalesce(p_domain->>'password',p_domain->>'invitation_code'),p_domain->'data',p_domain->>'unit_title');
  IF v_domain_result->>'code'<>'200' THEN RETURN jsonb_build_object('domain',v_domain_result); END IF;
  v_user:=(v_domain_result->>'id')::uuid;
  -- The delivery deadline expires the message, never the reusable password.
  v_source:=jsonb_build_object('password_version',(SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') FROM auth.users WHERE id=v_user));
 ELSIF p_operation='deletion_confirm' THEN
  v_kind:='deletion_confirm';
  v_domain_result:=public.create_account_deletion_request(v_user,(p_context->>'organization')::bigint,p_domain->>'token_hash',p_expires,p_domain->>'masked_email');
  v_source:=jsonb_build_object('deletion_request',v_domain_result->>'requestId');
 ELSIF p_operation='google_mailbox' THEN
  v_kind:='google_mailbox';
  v_domain_result:=public.google_auth_transition_v1('mailbox_send',(p_domain->>'attempt_id')::uuid,p_domain->>'secret_hash',p_domain->'payload');
  IF (v_domain_result->>'organization')::bigint IS DISTINCT FROM (p_context->>'organization')::bigint OR v_domain_result->>'email' IS DISTINCT FROM p_recipient THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  v_source:=jsonb_build_object('google_attempt',p_domain->>'attempt_id','mailbox_hash',p_domain#>>'{payload,mailboxHash}');
 ELSE RAISE EXCEPTION 'invalid_account_email_operation'; END IF;
 IF v_user IS NOT NULL THEN v_context:=v_context||jsonb_build_object('recipient_user',v_user); END IF;
 v_result:=public.enqueue_email(v_kind,v_context,p_recipient,v_source||jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now(),post_action=v_source WHERE message_id=(v_result->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result||jsonb_build_object('domain',v_domain_result);
END $$;
REVOKE ALL ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.reset_password_and_enqueue_email(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_answer jsonb; v_context jsonb; v_email text; v_result jsonb; v_existing public.email_messages; v_password_version text;
BEGIN
 -- Reuse the existing hierarchical permission check, including elevated-account protections.
 IF auth.uid() IS NULL OR NOT coalesce(public.get_can_reset_user_password(p_user),false) THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sign-in:'||p_user::text||':'||p_occasion::text,0));
 -- Team invitations never own a password transition, including older clients.
 PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user FOR SHARE;
 IF EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user
   AND (is_editor OR is_editor_view OR is_manager)) THEN
  RAISE insufficient_privilege USING MESSAGE='Team invitations cannot reset account passwords'; END IF;
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown','accepted') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
 IF v_existing.id IS NOT NULL THEN
  RETURN jsonb_build_object('message_id',v_existing.message_id,'replayed',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user) THEN RAISE EXCEPTION 'user_not_in_occasion'; END IF;
 v_answer:=public.reset_user_password(p_user,p_password);
 IF v_answer->>'code'<>'200' THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') INTO v_password_version FROM auth.users WHERE id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('password_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 PERFORM public.admit_email_intent_v1((SELECT id FROM public.email_messages WHERE message_id=(v_result->>'message_id')::uuid),true);
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;

-- Compatibility name for older clients; both names own the same permanent password transition.
CREATE OR REPLACE FUNCTION public.enqueue_sign_in_code_v1(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.reset_password_and_enqueue_email(p_user,p_password,p_occasion,p_sealed,p_content_hash,p_dedupe,p_expires);
$$;
REVOKE ALL ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;

-- Source: database/functions/emails/email_reporting.sql
CREATE OR REPLACE FUNCTION public.get_email_occasion_context(p_occasion bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'unit',unit) FROM public.occasions WHERE id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_email_occasion_context(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_occasion_context(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.email_reporting_state(m public.email_messages) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN m.complained_at IS NOT NULL THEN 'complaint' WHEN m.bounced_at IS NOT NULL THEN 'bounce'
 WHEN m.last_error='post_action_failed' THEN 'post_action_failed' WHEN m.provider_failure IN ('reject','rendering_failure') THEN m.provider_failure
 WHEN m.workflow_state IN ('unknown','dead','suppressed','retry_wait') THEN m.workflow_state
 WHEN m.clicked_at IS NOT NULL THEN 'click' WHEN m.opened_at IS NOT NULL THEN 'open' WHEN m.delivered_at IS NOT NULL THEN 'delivery'
 WHEN m.provider_failure='delay' THEN 'delay' ELSE m.workflow_state END;
$$;
REVOKE ALL ON FUNCTION public.email_reporting_state(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_reporting_state(public.email_messages) TO service_role;

-- Current issues are explicit provenance chains, independent of historical counts.
-- This invoker helper is only reachable through authorized reporting functions.
CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH RECURSIVE messages AS (
  SELECT m.*,CASE WHEN m.complained_at IS NULL AND m.last_error IS DISTINCT FROM 'post_action_failed'
   AND coalesce(m.provider_failure,'') NOT IN ('reject','rendering_failure')
   AND greatest(m.bounced_at,events.bounce) IS NOT NULL
   AND greatest(m.delivered_at,events.delivery)>greatest(m.bounced_at,events.bounce)
   THEN 'delivery' ELSE public.email_reporting_state(m) END rs FROM public.email_messages m
  LEFT JOIN LATERAL (SELECT max(provider_time) FILTER(WHERE event_type='bounce') bounce,
   max(provider_time) FILTER(WHERE event_type='delivery') delivery
   FROM public.email_delivery_events e WHERE e.message_id=m.message_id) events ON true
  JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
  WHERE m.order_id=p_order),
 chain AS (
  SELECT m.message_id root,m.message_id leaf,ARRAY[m.message_id] path FROM messages m
  WHERE NOT EXISTS(SELECT 1 FROM messages parent WHERE parent.message_id::text=m.data->>'repair_source_message_id' AND parent.message_kind=m.message_kind)
  UNION ALL
  SELECT c.root,m.message_id,c.path||m.message_id FROM chain c JOIN messages parent ON parent.message_id=c.leaf
  JOIN messages m ON m.data->>'repair_source_message_id'=c.leaf::text AND m.message_kind=parent.message_kind
  WHERE NOT m.message_id=ANY(c.path)),
 leaves AS (SELECT DISTINCT ON (root) * FROM chain ORDER BY root,cardinality(path) DESC,leaf),
 issues AS (
  SELECT root.message_id source_message_id,leaf.message_id,root.message_kind kind,root.recipient original_recipient,
   leaf.recipient,leaf.rs state,
   coalesce(leaf.last_error,CASE WHEN leaf.workflow_state IN ('pending','preparing','blocked') THEN
    (SELECT CASE WHEN paused THEN 'queue_paused' WHEN daily_quota<=provider_sent_24h THEN 'queue_limit' END FROM public.email_capacity) END) reason,
   (SELECT reason FROM public.email_suppressions WHERE recipient=lower(leaf.recipient)) suppression_reason,
   CASE WHEN o.state='storno' THEN 'cancelled'
    WHEN leaf.rs IN ('delivery','open','click') AND leaf.delivered_at IS NOT NULL
     AND (leaf.recipient IS DISTINCT FROM o.data->>'email' OR leaf.source_version IS DISTINCT FROM o.email_payment_version
      OR (leaf.data->>'repair_payment_fingerprint' IS NOT NULL AND leaf.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(o.id))) THEN 'stale_delivery'
    WHEN leaf.message_id<>root.message_id AND leaf.rs IN ('pending','preparing','accepted','open','click','sending','blocked') THEN 'waiting_repair'
    ELSE leaf.rs END resolution,
   (root.message_kind<>CASE WHEN o.state='ordered' THEN 'order_confirmation' ELSE 'order_tickets' END) obsolete
  FROM leaves c JOIN messages root ON root.message_id=c.root JOIN messages leaf ON leaf.message_id=c.leaf
  JOIN eshop.orders o ON o.id=p_order
  WHERE (EXISTS(SELECT 1 FROM messages m WHERE m.message_id=ANY(c.path)
    AND (m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
     OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now()))))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT coalesce(jsonb_agg(to_jsonb(issues) ORDER BY source_message_id),'[]'::jsonb) FROM issues;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH messages AS (
 SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion
  AND workflow_state NOT IN ('cancelled','expired')),
 ranked AS (
 SELECT *,CASE WHEN reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed') THEN 0
 WHEN workflow_state IN ('pending','preparing','sending','blocked') AND target_time<=now() THEN 1
 WHEN workflow_state='accepted' THEN 2 ELSE 3 END rank FROM messages)
 SELECT coalesce(jsonb_object_agg(r.order_id,jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'message_id',r.message_id,'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),
 'current_issues',public.order_email_current_issues(r.order_id),'scheduled_at',r.target_time,'attention_count',(SELECT count(*) FROM ranked n WHERE n.order_id=r.order_id AND rank=0),'loaded_at',now(),
 'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object('kind',message_kind,'state',reporting_state,'at',coalesce(delivered_at,accepted_at,created_at)) ORDER BY created_at DESC),'[]') FROM ranked n WHERE n.order_id=r.order_id))
),'{}'::jsonb) INTO v_summary FROM (SELECT DISTINCT ON (order_id) * FROM ranked ORDER BY order_id,rank,created_at DESC,id DESC) r;
 SELECT v_summary||coalesce(jsonb_object_agg(o.id,jsonb_build_object('state','unavailable','messages','[]'::jsonb,
  'current_issues',public.order_email_current_issues(o.id),'loaded_at',now())),'{}') INTO v_summary
 FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.occasion=p_occasion AND NOT v_summary ? o.id::text;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_order_email_summary(p_order bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occ bigint;
BEGIN
 SELECT occasion INTO v_occ FROM eshop.orders WHERE id=p_order;
 IF v_occ IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
 RETURN coalesce(public.get_order_email_summaries(v_occ,ARRAY[p_order])->p_order::text,jsonb_build_object('state','unavailable','messages','[]'::jsonb,'loaded_at',now()));
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summary(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summary(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.email_report_allowed(p_org bigint,p_occasion bigint,p_user uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.get_is_admin_on_organization(p_org),false) OR
 (p_occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_org)
 AND coalesce(public.can_read_orders(p_occasion),false)
 AND (p_user IS NULL OR EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user)));
$$;
REVOKE ALL ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) TO authenticated,service_role;

DROP FUNCTION IF EXISTS public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz);
CREATE OR REPLACE FUNCTION public.get_email_delivery_page(p_occasion bigint,p_before bigint DEFAULT NULL,p_limit integer DEFAULT 30,p_order bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_state text DEFAULT NULL,p_organization bigint DEFAULT NULL,p_user uuid DEFAULT NULL,p_since timestamptz DEFAULT NULL,p_orders_only boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion,p_user),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_page_limit'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY id DESC),'[]') INTO v_result FROM (
 SELECT id,message_id,message_kind,order_id,(SELECT o.order_symbol FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=m.order_id AND oc.organization=m.organization AND o.occasion=m.occasion) order_symbol,created_at,accepted_at,delivered_at,bounced_at,complained_at,opened_at,clicked_at,
 public.email_reporting_state(m) state,tracking_policy,post_action_state,last_error FROM public.email_messages m
 WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion OR (p_user IS NOT NULL AND occasion IS NULL))
 AND (p_user IS NULL OR recipient_user=p_user) AND (p_since IS NULL OR created_at>=p_since) AND (p_before IS NULL OR id<p_before) AND (p_order IS NULL OR order_id=p_order)
 AND (NOT coalesce(p_orders_only,false) OR order_id IS NOT NULL)
 AND (p_kind IS NULL OR message_kind=p_kind) AND (p_state IS NULL OR public.email_reporting_state(m)=p_state)
 ORDER BY id DESC LIMIT p_limit) x;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz,boolean) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_delivery_detail(p_message uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_id IS NULL THEN RAISE EXCEPTION 'email_detail_not_available'; END IF;
 IF NOT coalesce(public.email_report_allowed(m.organization,m.occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN jsonb_build_object('message',jsonb_build_object('id',m.message_id,'kind',m.message_kind,'state',public.email_reporting_state(m),'tracking_policy',m.tracking_policy,'opened_at',m.opened_at,'clicked_at',m.clicked_at,'post_action',m.post_action_state,'last_error',m.last_error,'provider_id',m.provider_message_id,'requested_by',m.data->>'requested_by'),
 'attempts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',attempt_id,'state',state,'at',created_at,'error',error_code,'provider_id',provider_message_id) ORDER BY created_at),'[]') FROM public.email_attempts WHERE message_id=p_message),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('type',event_type,'at',provider_time) ORDER BY provider_time),'[]') FROM (SELECT event_type,provider_time FROM public.email_delivery_events WHERE message_id=p_message ORDER BY provider_time DESC LIMIT 100) e));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_detail(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_detail(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.create_email_confirmation_receipt(p_command uuid,p_order bigint,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT message_id INTO v_message FROM public.email_messages WHERE message_kind='order_confirmation' AND data->>'command_id'=p_command::text AND order_id=p_order;
 IF v_message IS NULL THEN RETURN false; END IF;
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at) VALUES(p_hash,v_message,now()+interval '15 minutes');
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_email_confirmation_status(p_hash text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid; m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_confirmation_receipts SET reads=reads+1 WHERE token_hash=p_hash AND expires_at>now() AND reads<15 RETURNING message_id INTO v_message;
 IF v_message IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=v_message;
 RETURN CASE WHEN EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id AND e.invalid_recipient AND e.recipient=lower(m.recipient)) THEN 'invalid_email'
 WHEN m.bounced_at IS NOT NULL OR m.complained_at IS NOT NULL OR m.provider_failure IN ('reject','rendering_failure') THEN 'failed'
 WHEN m.delivered_at IS NOT NULL THEN 'delivered' WHEN m.workflow_state='accepted' THEN 'accepted' WHEN m.workflow_state IN ('unknown','dead','suppressed','expired','cancelled','retry_wait') THEN m.workflow_state ELSE 'queued' END;
END $$;
REVOKE ALL ON FUNCTION public.get_email_confirmation_status(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_confirmation_status(text) TO service_role;
CREATE OR REPLACE FUNCTION public.get_auth_email_context(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'recipient',public.get_user_delivery_email(id)) FROM public.user_info WHERE id=p_user);
END $$;
REVOKE ALL ON FUNCTION public.get_auth_email_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_email_context(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_email_delivery_overview(p_occasion bigint,p_organization bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN (SELECT jsonb_build_object('messages',count(*),'accepted',count(*) FILTER(WHERE accepted_at IS NOT NULL),
 'delivered',count(*) FILTER(WHERE delivered_at IS NOT NULL),'bounced',count(*) FILTER(WHERE bounced_at IS NOT NULL),
 'complained',count(*) FILTER(WHERE complained_at IS NOT NULL),'opened_messages',count(*) FILTER(WHERE opened_at IS NOT NULL),
 'clicked_messages',count(*) FILTER(WHERE clicked_at IS NOT NULL),'tracking_coverage',count(*) FILTER(WHERE tracking_policy<>'disabled'),
 'unknown',count(*) FILTER(WHERE workflow_state='unknown'),'dead',count(*) FILTER(WHERE workflow_state='dead'),
 'feedback_overdue',count(*) FILTER(WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=email_messages.message_id))) FROM public.email_messages WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_overview(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_overview(bigint,bigint) TO authenticated,service_role;

-- Source: database/functions/notification_center/core.sql
-- Called by trusted domain owners only. Never accept an actor in a public RPC.
CREATE OR REPLACE FUNCTION public.notification_center_require_service() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF session_user<>'postgres' AND coalesce(auth.role(),'')<>'service_role' THEN
  RAISE insufficient_privilege USING MESSAGE='notification_service_required'; END IF;
END $$;
-- Match the canonical account write policy: account admin AND linked-unit manager.
CREATE OR REPLACE FUNCTION public.notification_center_bank_admin(p_bank bigint,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank AND m."user"=p_user AND m.is_admin),
  EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l JOIN public.unit_users m ON m.unit=l.unit AND m."user"=p_user AND m.is_manager
   WHERE l.bank_account=p_bank AND NOT EXISTS(SELECT 1 FROM public.demo_unit_ids_internal() d WHERE d.unit_id=m.unit)),
  public.is_demo_bank_account(p_bank));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_admin(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_allowed(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_user IS NOT NULL AND (
 CASE WHEN p_event.kind='email_problem' THEN
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_event.organization AND "user"=p_user AND is_admin) OR (p_event.occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=p_event.organization AND oc.id=p_event.occasion AND ou."user"=p_user AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)))
 WHEN p_event.kind='bank_problem' THEN (EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user)
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba JOIN public.units u ON u.id=uba.unit WHERE u.organization=p_event.organization AND uba.bank_account=bu.bank_account))
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id WHERE oc.organization=p_event.organization AND oc.id=ANY(p_event.affected_occasions) AND ou."user"=p_user AND ou.is_editor_order_view))
 ELSE EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_event.organization AND ou."user"=p_user AND ou.is_editor_order_view
 AND NOT public.is_demo_occasion(oc.id)
 AND (oc.id=p_event.occasion OR oc.id=ANY(p_event.affected_occasions))) END
 );
$$;
CREATE OR REPLACE FUNCTION public.notification_center_check_context(p_org bigint,p_occ bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (
 EXISTS(SELECT 1 FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units u ON u.id=uba.unit WHERE bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=p_org) OR
 EXISTS(SELECT 1 FROM public.organization_users WHERE organization=p_org AND "user"=auth.uid() AND is_admin)
 OR EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id))) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_read_denied'; END IF;
 IF p_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id
 WHERE oc.id=p_occ AND oc.organization=p_org AND ou."user"=auth.uid() AND ou.is_editor_order_view AND NOT public.is_demo_occasion(oc.id)) THEN
 RAISE insufficient_privilege USING MESSAGE='notification_context_denied'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_capture_recipients_internal(p_event uuid,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; u uuid;
BEGIN
 SELECT * INTO e FROM public.notification_center_events WHERE id=p_event;
 IF NOT FOUND THEN RETURN; END IF;
 FOR u IN SELECT "user" FROM public.organization_users WHERE organization=e.organization AND is_admin
 UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion WHERE oc.organization=e.organization AND ou.is_editor_order_view
 UNION SELECT bu."user" FROM eshop.bank_account_users bu JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account
 JOIN public.units un ON un.id=uba.unit WHERE un.organization=e.organization AND bu.is_admin LOOP
  IF public.notification_center_allowed(e,u) AND (u IS DISTINCT FROM p_actor OR NOT EXISTS(
   SELECT 1 FROM public.occasion_users WHERE occasion=e.occasion AND "user"=p_actor AND is_editor_order) AND NOT EXISTS(SELECT 1 FROM public.organization_users WHERE organization=e.organization AND "user"=p_actor AND is_admin)) THEN
   INSERT INTO public.notification_center_recipients(event_id,recipient,eligible_revision) VALUES(e.id,u,e.attention_revision)
   ON CONFLICT(event_id,recipient) DO UPDATE SET eligible_revision=excluded.eligible_revision;
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_capture_recipients_internal(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.notification_center_publish_internal(p_org bigint,p_occ bigint,p_kind text,p_key text,
 p_data jsonb DEFAULT '{}',p_actor uuid DEFAULT NULL,p_at timestamptz DEFAULT NULL,p_affected bigint[] DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a public.notification_center_activation; e public.notification_center_events; u uuid;
BEGIN
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('notification-center-activation:'||p_org,0));
 p_at:=coalesce(p_at,clock_timestamp());
 -- The shared activation lock linearizes activation/pause with domain commits.
 SELECT * INTO a FROM public.notification_center_activation WHERE organization=p_org FOR SHARE;
 IF NOT FOUND OR NOT a.enabled OR p_at<coalesce(a.collection_started_at,a.activated_at) THEN RETURN NULL; END IF;
 IF p_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occ AND organization=p_org) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_affected) x WHERE NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=x AND organization=p_org)) THEN
 RAISE EXCEPTION 'notification_scope_mismatch'; END IF;
 INSERT INTO public.notification_center_events(organization,occasion,kind,source_key,actor,occurred_at,data,affected_occasions)
 VALUES(p_org,p_occ,p_kind,p_key,p_actor,p_at,p_data,p_affected) ON CONFLICT DO NOTHING RETURNING * INTO e;
 IF NOT FOUND THEN RETURN (SELECT id FROM public.notification_center_events WHERE organization=p_org AND source_key=p_key); END IF;
 PERFORM public.notification_center_capture_recipients_internal(e.id,p_actor);
 RETURN e.id;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_unmuted(p_event public.notification_center_events,p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_event.occasion IS NOT NULL THEN NOT EXISTS(SELECT 1 FROM public.notification_center_preferences
 WHERE organization=p_event.organization AND recipient=p_user AND occasion=p_event.occasion AND muted)
 WHEN cardinality(p_event.affected_occasions)=0 THEN true
 ELSE EXISTS(SELECT 1 FROM unnest(p_event.affected_occasions) oc JOIN public.occasion_users ou ON ou.occasion=oc AND ou."user"=p_user AND ou.is_editor_order_view
 WHERE NOT EXISTS(SELECT 1 FROM public.notification_center_preferences p WHERE p.organization=p_event.organization AND p.recipient=p_user AND p.occasion=oc AND p.muted))
 OR (p_event.kind='bank_problem' AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu ON
 bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
 WHERE c.id=(p_event.data->>'bankConnectionId')::bigint AND bu."user"=p_user AND public.notification_center_bank_admin(bu.bank_account,p_user))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_unmuted(public.notification_center_events,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.project_notification_center(p_limit integer DEFAULT 100) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE e public.notification_center_events; u uuid; n integer:=0; seq bigint; budget integer:=greatest(1,least(p_limit,500)); tz text;
BEGIN
 PERFORM public.notification_center_require_service();
 IF NOT pg_try_advisory_xact_lock(5831290471283) THEN RETURN 0; END IF;
 -- Row locks are the transaction lease. Rollback releases claims, including sequence allocation.
 FOR e IN SELECT ev.* FROM public.notification_center_events ev JOIN public.notification_center_activation a ON a.organization=ev.organization
 WHERE a.enabled AND ev.projected_revision<ev.attention_revision ORDER BY ev.organization,ev.occurred_at,ev.id
 LIMIT greatest(1,least(p_limit,500)) FOR UPDATE OF ev SKIP LOCKED LOOP
  SELECT timezone INTO tz FROM public.notification_center_activation WHERE organization=e.organization;
  FOR u IN SELECT recipient FROM public.notification_center_recipients WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision ORDER BY recipient LIMIT budget-n LOOP
   UPDATE public.notification_center_recipients SET processed_revision=e.attention_revision WHERE event_id=e.id AND recipient=u;
   n:=n+1;
   IF NOT public.notification_center_allowed(e,u) OR EXISTS(SELECT 1 FROM public.notification_center_deliveries
    WHERE event_id=e.id AND recipient=u AND attention_revision=e.attention_revision) THEN CONTINUE; END IF;
   IF NOT public.notification_center_unmuted(e,u) THEN CONTINUE; END IF;
   INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(e.organization,u) ON CONFLICT DO NOTHING;
   UPDATE public.notification_center_user_state SET last_delivery_sequence=last_delivery_sequence+1
    WHERE organization=e.organization AND recipient=u RETURNING last_delivery_sequence INTO seq;
   INSERT INTO public.notification_center_deliveries(event_id,recipient,organization,attention_revision,sequence,group_key)
    VALUES(e.id,u,e.organization,e.attention_revision,seq,
     CASE WHEN e.kind='email_problem' THEN coalesce(e.occasion::text,'shared')||':email_problem:'||coalesce(e.data->>'reason','problem')||':'||(e.occurred_at AT TIME ZONE tz)::date::text
     WHEN e.kind IN ('order_created','waitlist_registered','order_cancelled') THEN
      coalesce(e.occasion::text,'shared')||':'||e.kind||':'||(e.occurred_at AT TIME ZONE tz)::date::text ELSE e.id::text END);
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.notification_center_recipients WHERE event_id=e.id AND eligible_revision=e.attention_revision AND processed_revision<e.attention_revision) THEN
   UPDATE public.notification_center_events SET projected_revision=e.attention_revision WHERE id=e.id;
  END IF;
  EXIT WHEN n>=budget;
 END LOOP;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_dto(e public.notification_center_events,d public.notification_center_deliveries)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE payload jsonb:=e.data-'bankConnectionId'; account bigint; un bigint; impacts jsonb; customer text; actual_state text;
BEGIN
 IF e.kind='email_problem' AND public.notification_center_allowed(e,auth.uid()) THEN
  SELECT payload||jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,'recipient',m.recipient,'customerName',coalesce(
    nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),
    nullif(trim(concat_ws(' ',u.name,u.surname)),''))) INTO payload
  FROM public.email_messages m
  LEFT JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
    AND coalesce(public.can_read_orders(o.occasion),false)
    AND EXISTS(SELECT 1 FROM public.occasions oc WHERE oc.id=o.occasion AND oc.organization=m.organization)
  LEFT JOIN public.user_info u ON u.id=m.recipient_user AND u.organization=m.organization
  WHERE m.message_id=(e.data->>'messageId')::uuid AND m.organization=e.organization
    AND m.occasion IS NOT DISTINCT FROM e.occasion;
  payload:=coalesce(payload,e.data-'bankConnectionId');
 END IF;
 IF e.data ? 'orderId' AND e.occasion IS NOT NULL THEN
  SELECT nullif(trim(concat_ws(' ',o.data->>'name',o.data->>'surname')),''),o.state INTO customer,actual_state
   FROM eshop.orders o WHERE o.id=(e.data->>'orderId')::bigint AND o.occasion=e.occasion;
  payload:=payload||jsonb_build_object('customerName',customer,'state',coalesce(actual_state,e.data->>'state'));
 END IF;
 IF e.kind='bank_problem' THEN
  SELECT bu.bank_account,u.id INTO account,un FROM eshop.bank_sync_connections c JOIN eshop.bank_account_users bu
   ON bu.bank_account=c.bank_account_id OR bu.bank_account IN(SELECT bank_account_id FROM eshop.bank_sync_account_aliases WHERE connection_id=c.id)
   JOIN eshop.unit_bank_accounts uba ON uba.bank_account=bu.bank_account JOIN public.units u ON u.id=uba.unit
   WHERE c.id=(e.data->>'bankConnectionId')::bigint AND bu."user"=auth.uid() AND public.notification_center_bank_admin(bu.bank_account,auth.uid()) AND u.organization=e.organization AND EXISTS(SELECT 1 FROM public.unit_users um WHERE um.unit=u.id AND um."user"=auth.uid() AND um.is_manager) ORDER BY u.id LIMIT 1;
  IF account IS NOT NULL THEN payload:=payload||jsonb_build_object('bankAccountId',account,'unitId',un); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'link',oc.link)),'[]') INTO impacts
   FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid() AND ou.is_editor_order_view
   WHERE oc.organization=e.organization AND oc.id=ANY(e.affected_occasions);
  payload:=payload||jsonb_build_object('affectedOccasions',impacts);
 END IF;
 RETURN (SELECT jsonb_build_object('id',e.id,'sequence',d.sequence,'kind',e.kind,'occurredAt',e.occurred_at,
 'status',e.status,'data',payload,'occasionId',e.occasion,'occasionLink',oc.link,'occasionTitle',oc.title)
 FROM (SELECT 1) seed LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=e.organization);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_badge(p_organization bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; enabled boolean;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 SELECT a.enabled INTO enabled FROM public.notification_center_activation a WHERE organization=p_organization;
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 RETURN jsonb_build_object('enabled',coalesce(enabled,false),'lastSequence',coalesce(s.last_delivery_sequence,0),'readThrough',coalesce(s.read_through_sequence,0),
 'unread',coalesce(enabled,false) AND EXISTS(SELECT 1 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence>coalesce(s.read_through_sequence,0)
 AND public.notification_center_allowed(e,auth.uid()) AND public.notification_center_unmuted(e,auth.uid())));
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_group(p_organization bigint,p_group_key text,p_snapshot bigint,
 p_cursor bigint DEFAULT NULL,p_limit integer DEFAULT 5) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE items jsonb; next_cursor bigint;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 WITH rows AS (SELECT public.notification_center_dto(e,d) item,d.sequence FROM public.notification_center_deliveries d
 JOIN public.notification_center_events e ON e.id=d.event_id WHERE d.organization=p_organization AND d.recipient=auth.uid()
 AND d.group_key=p_group_key AND d.sequence<=p_snapshot AND (p_cursor IS NULL OR d.sequence<p_cursor)
 AND public.notification_center_allowed(e,auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer
 WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient AND newer.sequence<=p_snapshot AND newer.sequence>d.sequence)
 ORDER BY d.sequence DESC LIMIT greatest(1,least(p_limit,50)))
 SELECT coalesce(jsonb_agg(item ORDER BY sequence DESC),'[]'),CASE WHEN count(*)=greatest(1,least(p_limit,50)) THEN min(sequence) END INTO items,next_cursor FROM rows;
 RETURN jsonb_build_object('items',items,'nextCursor',next_cursor);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_page(p_organization bigint,p_current_occasion bigint DEFAULT NULL,
 p_limit integer DEFAULT 30,p_snapshot bigint DEFAULT NULL,p_cursor jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups jsonb; choices jsonb; snap bigint; tail jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT least(coalesce(p_snapshot,last_delivery_sequence),last_delivery_sequence) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 WITH available AS (SELECT d.*,e.kind,e.occasion,oc.title,
 CASE WHEN e.occasion IS NULL AND (p_current_occasion IS NULL OR cardinality(e.affected_occasions)=0 OR p_current_occasion=ANY(e.affected_occasions)) THEN 0 WHEN e.occasion=p_current_occasion THEN 1 ELSE 2 END section
 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 LEFT JOIN public.occasions oc ON oc.id=e.occasion AND oc.organization=p_organization
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence<=snap AND public.notification_center_allowed(e,auth.uid())
 AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient
 AND newer.sequence<=snap AND newer.sequence>d.sequence)), grouped AS (
 SELECT group_key,kind,occasion,title,section,count(*) n,max(sequence) latest FROM available GROUP BY group_key,kind,occasion,title,section
 ), page AS (SELECT * FROM grouped WHERE p_cursor IS NULL OR section>(p_cursor->>'section')::int OR
 (section=(p_cursor->>'section')::int AND (latest,group_key)<((p_cursor->>'sequence')::bigint,p_cursor->>'key'))
 ORDER BY section,latest DESC,group_key DESC LIMIT greatest(1,least(p_limit,100)))
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',group_key,'section',section,'occasionId',occasion,'occasionTitle',title,'kind',kind,'day',CASE WHEN kind IN ('order_created','waitlist_registered','order_cancelled','email_problem') THEN right(group_key,10) END,'count',n,
 'lastSequence',latest,'items',public.get_notification_center_group(p_organization,group_key,snap,NULL,5)->'items') ORDER BY section,latest DESC,group_key DESC),'[]'),
 (jsonb_agg(jsonb_build_object('section',section,'sequence',latest,'key',group_key) ORDER BY section DESC,latest,group_key)->0) INTO groups,tail FROM page;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
 FROM public.occasions oc JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid() AND ou.is_editor_order_view
 LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
 WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id);
 RETURN jsonb_build_object('snapshot',snap,'groups',groups,'nextCursor',CASE WHEN jsonb_array_length(groups)=greatest(1,least(p_limit,100)) THEN tail END,'occasions',choices);
END $$;
CREATE OR REPLACE FUNCTION public.open_notification_center(p_organization bigint,p_current_occasion bigint DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; result jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
 UPDATE public.notification_center_user_state SET read_through_sequence=greatest(read_through_sequence,s.last_delivery_sequence)
 WHERE organization=p_organization AND recipient=auth.uid();
 result:=public.get_notification_center_page(p_organization,p_current_occasion,p_limit,s.last_delivery_sequence,NULL);
 RETURN result||jsonb_build_object('readThrough',s.last_delivery_sequence);
END $$;
CREATE OR REPLACE FUNCTION public.set_notification_center_muted(p_organization bigint,p_occasion bigint,p_muted boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_occasion);
 IF p_occasion IS NULL OR p_muted IS NULL THEN RAISE EXCEPTION 'notification_invalid_preference'; END IF;
 INSERT INTO public.notification_center_preferences VALUES(p_organization,auth.uid(),p_occasion,p_muted)
 ON CONFLICT(organization,recipient,occasion) DO UPDATE SET muted=excluded.muted;
END $$;
-- Explicitly close every helper; PostgREST cannot publish or project as a user.
REVOKE ALL ON FUNCTION public.notification_center_require_service(),public.notification_center_allowed(public.notification_center_events,uuid),
 public.notification_center_check_context(bigint,bigint),public.notification_center_publish_internal(bigint,bigint,text,text,jsonb,uuid,timestamptz,bigint[]),
 public.notification_center_dto(public.notification_center_events,public.notification_center_deliveries),public.project_notification_center(integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.project_notification_center(integer) TO service_role;
REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint),public.open_notification_center(bigint,bigint,integer),
 public.get_notification_center_page(bigint,bigint,integer,bigint,jsonb),public.get_notification_center_group(bigint,text,bigint,bigint,integer),
 public.set_notification_center_muted(bigint,bigint,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_notification_center_updates(p_organization bigint,p_snapshot bigint,p_ids uuid[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 IF coalesce(cardinality(p_ids),0)>200 THEN RAISE EXCEPTION 'notification_update_limit'; END IF;
 SELECT coalesce(jsonb_agg(public.notification_center_dto(e,d) ORDER BY d.sequence DESC),'[]') INTO result
 FROM public.notification_center_events e JOIN public.notification_center_deliveries d ON d.event_id=e.id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND e.id=ANY(p_ids) AND d.sequence<=p_snapshot
 AND public.notification_center_allowed(e,auth.uid()) AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer
 WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient AND newer.sequence>d.sequence AND newer.sequence<=p_snapshot);
 RETURN jsonb_build_object('items',result);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_updates(bigint,bigint,uuid[]) TO authenticated;
