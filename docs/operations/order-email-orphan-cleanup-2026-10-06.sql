-- One-time cleanup for the selected vstupenky.online tenant only.
-- Run with ON_ERROR_STOP=1 against the verified canonical runtime database.
BEGIN;
SET LOCAL lock_timeout = '5s';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=3 AND title='vstupenky.online') THEN
    RAISE EXCEPTION 'cleanup_tenant_mismatch';
  END IF;
END $$;
SELECT singleton FROM public.email_capacity FOR UPDATE;
CREATE TEMP TABLE deleted_order_email_targets ON COMMIT DROP AS
SELECT m.message_id, m.provider_message_id
FROM public.email_messages m
WHERE m.organization=3 AND m.order_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id);
CREATE TEMP TABLE deleted_order_email_attempts ON COMMIT DROP AS
SELECT a.attempt_id,a.provider_message_id FROM public.email_attempts a
JOIN deleted_order_email_targets t USING(message_id);
DELETE FROM public.email_delivery_events e
WHERE e.message_id IN (SELECT message_id FROM deleted_order_email_targets)
   OR e.attempt_id IN (SELECT attempt_id FROM deleted_order_email_attempts)
   OR e.provider_message_id IN (
        SELECT provider_message_id FROM deleted_order_email_targets
        UNION SELECT provider_message_id FROM deleted_order_email_attempts);
DELETE FROM public.email_confirmation_receipts r
WHERE r.message_id IN (SELECT message_id FROM deleted_order_email_targets);
DELETE FROM public.email_attempts a
WHERE a.message_id IN (SELECT message_id FROM deleted_order_email_targets);
DELETE FROM public.email_messages m
WHERE m.message_id IN (SELECT message_id FROM deleted_order_email_targets);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.email_messages m WHERE m.organization=3
    AND m.order_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.orders o WHERE o.id=m.order_id)) THEN
    RAISE EXCEPTION 'cleanup_orphans_remain';
  END IF;
END $$;
COMMIT;
