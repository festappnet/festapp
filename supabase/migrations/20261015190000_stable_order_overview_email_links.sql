-- Stable overview link in existing order emails; retire standalone delivery.

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
 OR requested.data->>'email' IS DISTINCT FROM p_recipient OR root.data->>'email' IS DISTINCT FROM p_recipient THEN
  RAISE EXCEPTION 'INVALID_OVERVIEW_RECIPIENT';
 END IF;
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


-- Source: database/functions/others/get_all_email_templates.sql
CREATE OR REPLACE FUNCTION public.get_all_email_templates(p_context jsonb)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  email_data jsonb;
  v_occ  bigint;
  v_unit bigint;
  v_org  bigint;

  v_effective_org bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
  is_app_supported boolean := false;
  show_waitlist_templates boolean := false;
BEGIN
  -- 1. Extract context values from the JSON parameter
  v_occ  := CASE
              WHEN p_context ? 'occasion' AND (p_context->>'occasion') IS NOT NULL
              THEN (p_context->>'occasion')::bigint
              ELSE NULL
            END;
  v_unit := CASE
              WHEN p_context ? 'unit' AND (p_context->>'unit') IS NOT NULL
              THEN (p_context->>'unit')::bigint
              ELSE NULL
            END;
  v_org  := CASE
              WHEN p_context ? 'organization' AND (p_context->>'organization') IS NOT NULL
              THEN (p_context->>'organization')::bigint
              ELSE NULL
            END;

  -- Resolve ancestors from the requested object; never trust mixed tenant IDs.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org
    FROM public.occasions WHERE id = v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_editor_view_on_occasion(v_occ) IS NOT TRUE
       AND public.get_is_editor_order_view_on_occasion(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Occasion template access denied';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id = v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_manager_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_view_on_unit(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Unit template access denied';
    END IF;
    v_org := v_actual_org;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.get_is_admin_on_organization(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Organization template access denied';
    END IF;
  END IF;
  v_effective_org := v_org;

  -- 3. Check if App is Supported for the effective organization
  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
  END IF;

  -- The catalog follows the requested scope; stored templates and queue rendering
  -- remain available independently of whether the feature is currently enabled.
  SELECT EXISTS (
    SELECT 1 FROM public.forms f
    JOIN public.occasions o ON o.id = f.occasion
    WHERE o.organization = v_effective_org
      AND (v_occ IS NULL OR o.id = v_occ)
      AND (v_unit IS NULL OR o.unit = v_unit)
      AND f.participant_capacity > 0
      AND f.waitlist_enabled IS TRUE
  ) INTO show_waitlist_templates;

  -- 5. Retrieve email templates
  SELECT jsonb_agg(public.get_resolved_email_template(result.code,
    jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org)) ORDER BY result.code)
    INTO email_data
  FROM (
    SELECT DISTINCT et.code
    FROM public.email_templates et
    WHERE
      -- A. Filter based on context (Scope)
      (
           (v_occ IS NOT NULL AND et.occasion = v_occ)
        OR (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL)
        OR (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL)
        OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
      )
      AND et.code <> 'ORDER_OVERVIEW'
      -- B. Filter based on App Support (New Logic)
      AND (
        is_app_supported IS TRUE
        OR
        et.code NOT IN ('SIGN_IN_CODE', 'RESET_PASSWORD', 'APP_LINKS',
                        'ACCOUNT_DELETION_CONFIRM', 'ACCOUNT_DELETION_COMPLETE')
      )
      AND (show_waitlist_templates OR et.code NOT IN
        ('waitlist_confirmation', 'waitlist_offer'))
  ) result;

  IF email_data IS NULL THEN
    email_data := '[]'::jsonb;
  END IF;

  RETURN email_data;
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_email_templates(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_email_templates(jsonb) TO authenticated, service_role;


-- Source: database/functions/emails/email_queue.sql (email_intent_valid only)
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 -- Retired standalone overview emails must never leave the queue.
 IF p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
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
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;
