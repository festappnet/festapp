-- One-time, reviewed operator transition. No runtime fallback or email send.
-- Set LOCAL festapp.payment_policy_release.organization and .apply in the release transaction.
DO $$
DECLARE org bigint:=nullif(current_setting('festapp.payment_policy_release.organization',true),'')::bigint;
 apply_changes boolean:=coalesce(nullif(current_setting('festapp.payment_policy_release.apply',true),'')::boolean,false);
 original public.email_messages; proposed public.email_messages; candidates bigint:=0; eligible bigint:=0; changed bigint:=0; affected bigint;
BEGIN
 IF current_user NOT IN ('postgres','supabase_admin') THEN RAISE insufficient_privilege; END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=org) THEN
  RAISE invalid_parameter_value USING MESSAGE='Explicit verified release organization required'; END IF;
 IF apply_changes AND NOT EXISTS(SELECT 1 FROM public.email_capacity WHERE paused) THEN
  RAISE EXCEPTION 'PAYMENT_POLICY_RELEASE_REQUIRES_PAUSED_QUEUE'; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.payment_policy_fence_internal(org);
 FOR original IN SELECT m.* FROM public.email_messages m JOIN eshop.orders o ON o.id=m.order_id
 JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info
 WHERE m.organization=org AND oc.organization=org AND pi.payment_method='bank'
 AND m.message_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice')
 AND m.workflow_state IN ('pending','retry_wait') AND m.prepared IS NULL AND m.prepared_at IS NULL
 AND m.provider_message_id IS NULL AND m.lease_token IS NULL AND m.processing_at IS NULL AND coalesce(m.attempt_count,0)=0
 AND NOT (coalesce(m.data,'{}') ? 'collectionAction') AND NOT (coalesce(m.data,'{}') ? 'paymentTemplateEpoch')
 AND NOT EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id)
 AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id)
 AND coalesce(public.payment_method_policy_enabled_internal(oc.unit,'bank'),false)
 LOOP
  candidates:=candidates+1; proposed:=original;
  proposed.data:=coalesce(original.data,'{}')||jsonb_build_object(
   'collectionAction',public.payment_collection_action_internal(original.order_id),
   'paymentTemplateEpoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=original.occasion),0),
   'paymentPolicyRelease',jsonb_build_object('contract','20261112200000','previousInputHash',original.input_hash));
  IF NOT public.email_intent_valid(proposed) THEN CONTINUE; END IF;
  eligible:=eligible+1;
  IF apply_changes THEN
   UPDATE public.email_messages m SET data=proposed.data
   WHERE m.message_id=original.message_id AND m.data IS NOT DISTINCT FROM original.data
    AND m.workflow_state=original.workflow_state AND m.prepared IS NULL AND m.prepared_at IS NULL
    AND m.provider_message_id IS NULL AND m.lease_token IS NULL AND m.processing_at IS NULL AND coalesce(m.attempt_count,0)=0
    AND NOT EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id)
    AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id);
   GET DIAGNOSTICS affected=ROW_COUNT;
   IF affected<>1 THEN RAISE EXCEPTION 'PAYMENT_POLICY_EMAIL_TRANSITION_RACE'; END IF;
   changed:=changed+affected;
  END IF;
 END LOOP;
 PERFORM set_config('festapp.payment_policy_release.candidates',candidates::text,true);
 PERFORM set_config('festapp.payment_policy_release.eligible',eligible::text,true);
 PERFORM set_config('festapp.payment_policy_release.changed',changed::text,true);
 RAISE NOTICE 'Payment policy email transition: candidates %, eligible %, changed %',candidates,eligible,changed;
END $$;
