-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_tickets' THEN
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
 IF v_order.state='paid' AND v_occ.is_order_synchronization_enabled AND v_order.data ? 'email'
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
   AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND expires_at>now() ORDER BY id DESC LIMIT 1;
  IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true);END IF;
 END IF;
 IF p_operation='reset_token' THEN
  v_kind:='reset_password';
  IF NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=v_user AND organization=(p_context->>'organization')::bigint) THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  INSERT INTO public.user_reset_token("user",token,created_at) VALUES(v_user,(p_domain->>'token')::uuid,now()) ON CONFLICT("user") DO UPDATE SET token=excluded.token,created_at=excluded.created_at;
  v_source:=jsonb_build_object('reset_hash',encode(extensions.digest(p_domain->>'token','sha256'),'hex'));
 ELSIF p_operation='register' THEN
  v_kind:='registration';
  v_domain_result:=public.create_user_from_registration((p_context->>'organization')::bigint,p_recipient,CASE WHEN p_domain ? 'invitation_code' THEN encode(extensions.gen_random_bytes(32),'hex') ELSE p_domain->>'password' END,p_domain->'data',p_domain->>'unit_title');
  IF v_domain_result->>'code'<>'200' THEN RETURN jsonb_build_object('domain',v_domain_result); END IF;
  v_user:=(v_domain_result->>'id')::uuid;
  IF p_domain ? 'invitation_code' THEN
   PERFORM public.store_sign_in_code_v1(v_user,p_domain->>'invitation_code',p_expires);
   v_source:=jsonb_build_object('sign_in_code_version',(SELECT version FROM public.sign_in_codes WHERE user_id=v_user));
  ELSE
   v_source:=jsonb_build_object('password_version',(SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') FROM auth.users WHERE id=v_user));
  END IF;
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
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
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
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_sign_in_code_v1(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_answer jsonb; v_context jsonb; v_email text; v_result jsonb; v_existing public.email_messages; v_password_version text;
BEGIN
 -- Reuse the existing hierarchical permission check, including elevated-account protections.
 IF auth.uid() IS NULL OR NOT coalesce(public.get_can_reset_user_password(p_user),false) THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sign-in:'||p_user::text||':'||p_occasion::text,0));
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
 IF v_existing.id IS NOT NULL THEN
  RETURN jsonb_build_object('message_id',v_existing.message_id,'replayed',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user) THEN RAISE EXCEPTION 'user_not_in_occasion'; END IF;
 PERFORM public.store_sign_in_code_v1(p_user,p_password,p_expires);
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT version::text INTO v_password_version FROM public.sign_in_codes WHERE user_id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('sign_in_code_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;
