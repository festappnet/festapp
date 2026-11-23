-- Enable open tracking for waitlist mail without rewriting its access links.

-- SOURCE: emails/email_queue.sql (enqueue_email)
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_tracking_policy text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF p_code='BANK_SYNC_WARNING' THEN RAISE EXCEPTION 'bank_warning_producer_retired'; END IF;
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF (v_org IS NULL AND p_kind<>'admin_notification_digest') OR p_kind NOT IN ('admin_notification_digest','order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer','sale_opening_opened')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF (v_org IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org)) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_kind='admin_notification_digest' THEN
  IF v_org IS NOT NULL OR v_occ IS NOT NULL OR v_unit IS NOT NULL OR p_order IS NOT NULL OR
   p_recipient IS DISTINCT FROM public.get_user_delivery_email((p_context->>'recipient_user')::uuid) OR
   NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d
    WHERE d.id=(p_data->>'dispatchId')::uuid AND d.recipient=(p_context->>'recipient_user')::uuid AND d.state IN ('collecting','queued')) THEN
   RAISE EXCEPTION 'email_recipient_scope_mismatch';
  END IF;
 END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('collectionAction',public.payment_collection_action_internal(p_order));
 END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('paymentTemplateEpoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=v_occ),0));
 END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 -- Waitlist links grant access to the order or offer and must never be click-tracked.
 v_tracking_policy:=CASE
  WHEN p_kind IN ('waitlist_confirmation','waitlist_offer') THEN 'open'
  WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN
   CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END
  ELSE 'disabled'
 END;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',CASE WHEN p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN p_data-'requested_by'-'collectionAction'-'paymentTemplateEpoch'-'systemOrderDelivery' ELSE p_data-'requested_by' END,'code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 IF p_kind='admin_notification_digest' THEN
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,v_tracking_policy,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(recipient_user,message_kind,dedupe_key) WHERE message_kind='admin_notification_digest' DO NOTHING RETURNING * INTO v_row;
 ELSE
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,v_tracking_policy,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 END IF;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE (organization=v_org OR (p_kind='admin_notification_digest' AND recipient_user=(p_context->>'recipient_user')::uuid)) AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'email_active_notification_conflict'; END IF;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

-- The sender consumes the policy under its existing message lock at send time.
UPDATE public.email_messages
SET tracking_policy='open'
WHERE message_kind IN ('waitlist_confirmation','waitlist_offer')
  AND tracking_policy='disabled'
  AND workflow_state IN ('pending','blocked','preparing','retry_wait');
