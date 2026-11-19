-- Let Unit managers request platform approval of Meta CAPI. Approval itself stays a platform decision.

-- SOURCE: eshop_forms/unit_meta_capi_approval.sql
CREATE TABLE IF NOT EXISTS analytics.unit_meta_capi_request (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 requested_at timestamptz NOT NULL DEFAULT now(),
 requested_by uuid,
 revision integer NOT NULL DEFAULT 1
);
ALTER TABLE analytics.unit_meta_capi_request ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.unit_meta_capi_request FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS unit_meta_capi_notification_generation
 ON public.email_messages(unit,((data->>'request_revision')::integer))
 WHERE code='META_CAPI_APPROVAL_REQUEST';

-- Unit managers see only the platform decision and their own request; Meta
-- CAPI settings remain organization-administrator only.
CREATE OR REPLACE FUNCTION public.unit_meta_capi_approval_internal(p_unit bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH status AS (
  SELECT u.id,public.meta_purchase_platform_allowed_internal(u.id) AND NOT public.is_demo_unit(u.id) approved,q.requested_at,
   EXISTS(SELECT FROM public.email_messages m
    JOIN public.organization_users ou ON ou.organization=u.organization
     AND ou."user"=m.recipient_user AND ou.is_admin
    WHERE m.unit=u.id AND m.organization=u.organization AND m.code='META_CAPI_APPROVAL_REQUEST'
     AND (m.data->>'request_revision')::integer=q.revision
     AND public.get_user_delivery_email(ou."user")=m.recipient
     -- Same retry rule as the measurement request: accepted or ambiguous
     -- sends are not duplicated; terminal or expired generations are.
     AND (m.workflow_state IN ('accepted','sending','unknown') OR
      (m.workflow_state IN ('pending','retry_wait','preparing','blocked') AND m.expires_at>now()))) active_request
  FROM public.units u
  LEFT JOIN analytics.unit_meta_capi_request q ON q.unit=u.id WHERE u.id=p_unit
 ) SELECT jsonb_build_object('approved',approved,'requested_at',requested_at,
  'request_state',CASE WHEN requested_at IS NULL THEN 'not_requested'
    WHEN active_request THEN 'requested' ELSE 'retry_available' END,
  'can_request',NOT public.is_demo_unit(id) AND NOT approved AND NOT active_request) FROM status;
$$;
REVOKE ALL ON FUNCTION public.unit_meta_capi_approval_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.can_read_unit_administration(p_unit) OR public.can_manage_unit_configuration(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI approval read denied';
 END IF;
 RETURN public.unit_meta_capi_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.get_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_unit_meta_capi_approval(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_unit_meta_capi_approval(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE u public.units; o public.organizations; a record; status jsonb; msg jsonb; origin text; sent integer:=0; request_revision integer;
BEGIN
 -- Same boundary as the measurement request: Unit managers ask, demo readers get a no-op.
 IF auth.uid() IS NULL OR NOT (public.can_manage_unit_configuration(p_unit)
  OR (public.is_demo_unit(p_unit) AND public.can_read_unit_administration(p_unit))) THEN
  RAISE insufficient_privilege USING MESSAGE='unit Meta CAPI approval request denied';
 END IF;
 -- Serialize requests for this Unit without blocking the delivery FK's key-share lock.
 SELECT * INTO u FROM public.units WHERE id=p_unit FOR NO KEY UPDATE;
 status:=public.unit_meta_capi_approval_internal(p_unit);
 IF status->'can_request' IS DISTINCT FROM 'true'::jsonb THEN RETURN status; END IF;
 SELECT * INTO o FROM public.organizations WHERE id=u.organization;
 origin:=rtrim(o.data->>'DEFAULT_URL','/');
 IF origin IS NULL OR origin !~ '^https://[^/?#[:space:]]+$' THEN RAISE EXCEPTION 'meta_capi_notification_origin_missing'; END IF;
 INSERT INTO analytics.unit_meta_capi_request(unit,requested_by) VALUES(p_unit,auth.uid())
 ON CONFLICT(unit) DO UPDATE SET requested_at=clock_timestamp(),requested_by=auth.uid(),
  revision=analytics.unit_meta_capi_request.revision+1
 RETURNING revision INTO request_revision;
 FOR a IN SELECT ou."user" id,public.get_user_delivery_email(ou."user") email
  FROM public.organization_users ou WHERE ou.organization=u.organization AND ou.is_admin ORDER BY ou."user"
 LOOP
  IF a.email IS NULL THEN CONTINUE; END IF;
  msg:=public.enqueue_email('custom',jsonb_build_object('organization',u.organization,'unit',p_unit,'recipient_user',a.id),a.email,
   jsonb_build_object('request_revision',request_revision,'unit_id',p_unit,'unit_title',u.title,'organization_title',o.title,
    'review_url',origin||'/organizationEdit/'||u.organization,'lang',CASE WHEN o.data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END),
   'meta-capi-approval:'||p_unit||':'||a.id||':'||request_revision,'META_CAPI_APPROVAL_REQUEST',now(),now()+interval '30 days');
  UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(msg->>'message_id')::uuid;
  sent:=sent+1;
 END LOOP;
 -- Nobody could be notified: roll back the request so it stays retryable.
 IF sent=0 THEN RAISE EXCEPTION 'meta_capi_request_no_recipient'; END IF;
 RETURN public.unit_meta_capi_approval_internal(p_unit);
END $$;
REVOKE ALL ON FUNCTION public.request_unit_meta_capi_approval(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.request_unit_meta_capi_approval(bigint) TO authenticated;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb; v_template_epoch bigint; template_audit jsonb; bank_enabled boolean;
BEGIN
 IF p_message.message_kind='custom' AND p_message.code='MEASUREMENT_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_measurement_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND q.revision=coalesce((p_message.data->>'request_revision')::integer,1)
    AND public.unit_measurement_approval_internal(u.id)->'approved'='false'::jsonb
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='META_CAPI_APPROVAL_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM analytics.unit_meta_capi_request q JOIN public.units u ON u.id=q.unit
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE q.unit=p_message.unit AND u.organization=p_message.organization AND NOT public.is_demo_unit(u.id)
    AND q.revision=(p_message.data->>'request_revision')::integer
    AND NOT public.meta_purchase_platform_allowed_internal(u.id)
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='admin_notification_digest' THEN
  RETURN p_message.recipient IS NOT DISTINCT FROM public.get_user_delivery_email(p_message.recipient_user)
   AND coalesce(jsonb_array_length(public.notification_center_email_context_internal(p_message.notification_dispatch_id,p_message.recipient_user)->'items'),0)>0;
 END IF;

 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.access_invitations i WHERE i.message_id=p_message.message_id
   AND i.accepted_at IS NULL AND public.access_invitation_valid_internal_v1(i)
   AND i.email=p_message.recipient AND i.occasion IS NOT DISTINCT FROM p_message.occasion AND i.unit=p_message.unit AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_ACCESS_NOTICE' THEN
  RETURN public.can_manage_member_access_as_actor_internal_v1(p_message.producer_actor,
   CASE WHEN p_message.occasion IS NULL THEN 'unit' ELSE 'occasion' END,coalesce(p_message.occasion,p_message.unit))
   AND public.get_user_delivery_email(p_message.recipient_user)=p_message.recipient
   AND CASE WHEN p_message.occasion IS NULL THEN EXISTS(SELECT 1 FROM public.unit_users WHERE unit=p_message.unit AND "user"=p_message.recipient_user)
    ELSE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_message.occasion AND "user"=p_message.recipient_user) END;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_confirmation' THEN RETURN false; END IF;
 IF p_message.message_kind='sale_opening_opened' THEN
  RETURN public.sale_opening_intent_valid_internal(p_message);
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
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  v_template_epoch:=coalesce((SELECT e.revision FROM eshop.payment_template_epochs e WHERE e.occasion_id=v_order.occasion),0);
  bank_enabled:=coalesce(public.payment_method_policy_enabled_internal(v_occ.unit,'bank'),false);
  IF p_message.data ? 'paymentTemplateEpoch' THEN
   IF (p_message.data->>'paymentTemplateEpoch')::bigint IS DISTINCT FROM v_template_epoch THEN RETURN false; END IF;
  ELSIF p_message.prepared IS NOT NULL AND (NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method)) THEN
   -- An encrypted legacy snapshot has no attestation for the current template.
   -- Preserve it as audit; a new authorized preparation must replace the intent.
   RETURN false;
  END IF;
  IF NOT bank_enabled OR public.payment_method_is_online_internal(v_pi.payment_method) THEN
   template_audit:=public.payment_template_audit_internal(v_order.occasion);
   IF template_audit->'compatible' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  END IF;
 END IF;
 IF p_message.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  IF p_message.data#>>'{collectionAction,policyRevision}' IS NULL THEN RETURN false; END IF;
  IF public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}' THEN RETURN false; END IF;
 END IF;
 IF p_message.data#>'{collectionAction,allowed}'='true'::jsonb THEN
 IF (
  public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb OR
  public.payment_collection_action_internal(v_order.id)->'policyRevision' IS DISTINCT FROM p_message.data#>'{collectionAction,policyRevision}') THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND public.payment_method_is_online_internal(payment_method))
   AND public.provider_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  IF public.payment_collection_action_internal(v_order.id)->'allowed' IS DISTINCT FROM 'true'::jsonb THEN RETURN false; END IF;
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method<>'bank' OR v_pi.data#>>'{payment_policy,mode}'='none' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND coalesce(v_pi.paid,0)-coalesce(v_pi.returned,0)<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

-- SOURCE: units/delete_unit.sql
CREATE OR REPLACE FUNCTION public.delete_unit(p_unit_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_manager_count integer;
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    IF EXISTS (SELECT 1 FROM public.occasions WHERE unit = p_unit_id) THEN
        RAISE EXCEPTION 'UNIT_HAS_OCCASIONS';
    END IF;

    SELECT count(*)
      INTO v_manager_count
      FROM public.unit_users
     WHERE "user" = auth.uid()
       AND is_manager = true;

    IF v_manager_count <= 1 THEN
        RAISE EXCEPTION 'CANNOT_DELETE_LAST_UNIT';
    END IF;

    -- Preserve notification history without retaining a deleted unit or live intent.
    UPDATE public.email_messages
       SET unit = NULL,
           workflow_state = CASE WHEN workflow_state IN ('pending','retry_wait','blocked','preparing')
                                 THEN 'cancelled' ELSE workflow_state END
     WHERE unit = p_unit_id AND message_kind = 'custom' AND code IN ('UNIT_VERIFICATION_REQUEST','MEASUREMENT_APPROVAL_REQUEST','META_CAPI_APPROVAL_REQUEST');

    DELETE FROM public.unit_users WHERE unit = p_unit_id;
    DELETE FROM public.units WHERE id = p_unit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_unit(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_unit(bigint) TO authenticated;
