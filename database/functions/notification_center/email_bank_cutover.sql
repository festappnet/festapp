-- The source cutover stops producers first. Audit/prepared content stays intact.
DROP FUNCTION IF EXISTS public.enqueue_bank_sync_health_alerts(bigint);
DROP FUNCTION IF EXISTS public.claim_notification_center_bank_health(integer);
DROP FUNCTION IF EXISTS public.complete_notification_center_bank_health(bigint,uuid,timestamptz,text,timestamptz);
DROP TABLE IF EXISTS public.notification_center_bank_health;
-- Ambiguous old center episodes become a baseline, never matched by time/text.
SELECT public.notification_center_prepared_invalidate(id) FROM public.notification_center_events
 WHERE kind='bank_problem' AND NOT data ? 'incidentId' AND status NOT IN ('resolved','recovered');
UPDATE public.notification_center_events SET status='resolved'
 WHERE kind='bank_problem' AND NOT data ? 'incidentId';
UPDATE public.email_messages SET workflow_state='cancelled',last_error='notification_cutover_baseline'
 WHERE code='BANK_SYNC_WARNING' AND workflow_state IN ('blocked','pending','retry_wait') AND lease_token IS NULL;
-- Unknown/in-flight records remain under the original queue reconciliation.
-- No state here claims that unknown messages were delivered.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.email_messages WHERE code='BANK_SYNC_WARNING'
  AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown')) THEN
  RAISE EXCEPTION 'legacy_bank_notification_drain_required';
 END IF;
END $$;
-- Profiles serialize mandatory mail without opting anyone into optional mail.
-- Historical recipients also retain incident tombstones if their roles change.
WITH eligible AS MATERIALIZED(
 SELECT ui.id,ui.data FROM public.user_info ui WHERE EXISTS(
  SELECT 1 FROM eshop.bank_account_users bu WHERE bu."user"=ui.id AND bu.is_admin)
 OR EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=ui.id AND m.code='BANK_SYNC_WARNING'))
INSERT INTO public.notification_center_email_profiles(recipient,stopped,locale)
SELECT id,true,CASE WHEN data->>'locale' IN ('cs','en','de','pl','sk','uk') THEN data->>'locale' ELSE 'cs' END FROM eligible ON CONFLICT DO NOTHING;
-- Bank policy is required and has no editable subscription representation.
UPDATE public.notification_center_email_subscriptions SET kinds=kinds-'bank_problem' WHERE kinds ? 'bank_problem';
DO $$ DECLARE prior bigint; retained bigint; BEGIN
 SELECT count(DISTINCT "user") INTO prior FROM eshop.bank_account_users WHERE is_admin;
 SELECT count(DISTINCT bu."user") INTO retained FROM eshop.bank_account_users bu
 JOIN public.notification_center_email_profiles p ON p.recipient=bu."user" WHERE bu.is_admin
 AND EXISTS(SELECT 1 FROM public.notification_center_organizations a
  CROSS JOIN LATERAL public.notification_center_prepared_allowed_scopes(a.organization,NULL,bu."user") rights WHERE rights.scope LIKE 'bank:%');
 RAISE NOTICE 'bank_notification_recipient_migration: prior=%, retained=%, excluded=%',prior,retained,greatest(prior-retained,0);
END $$;
INSERT INTO public.notification_center_email_items(recipient,delivery_key,disposition)
SELECT DISTINCT p.recipient,'bank:'||(m.data->>'connection_id')||':incident:'||(m.data->>'incident_id'),'baseline'
FROM public.notification_center_email_profiles p JOIN public.email_messages m ON m.recipient_user=p.recipient
WHERE m.code='BANK_SYNC_WARNING' AND m.data->>'incident_id' IS NOT NULL AND m.data->>'connection_id' IS NOT NULL
ON CONFLICT DO NOTHING;
ALTER TABLE eshop.bank_sync_health DROP COLUMN IF EXISTS notified_at;
