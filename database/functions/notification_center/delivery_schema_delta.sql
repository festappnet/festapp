-- Delivery retry state belongs to the existing durable recipient work owner.
ALTER TABLE public.notification_center_recipients
 ADD COLUMN IF NOT EXISTS pending_since timestamptz NOT NULL DEFAULT clock_timestamp(),
 ADD COLUMN IF NOT EXISTS retry_revision bigint NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS retry_count integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',
 ADD COLUMN IF NOT EXISTS last_error_code text,
 ADD COLUMN IF NOT EXISTS quarantined boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS notification_center_recipient_retry
 ON public.notification_center_recipients(event_id,next_attempt_at,recipient)
 WHERE processed_revision<eligible_revision;

-- Include the deterministic tie-breaker, avoiding a backlog-sized sort per call.
DROP INDEX IF EXISTS public.notification_center_pending;
CREATE INDEX notification_center_pending ON public.notification_center_events(organization,occurred_at,id)
 WHERE projected_revision<attention_revision;

ALTER TABLE public.notification_center_maintenance
 ADD COLUMN IF NOT EXISTS last_scanned integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_processed integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_deferred integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_failed integer NOT NULL DEFAULT 0,
 ADD COLUMN IF NOT EXISTS last_elapsed_ms numeric,
 ADD COLUMN IF NOT EXISTS last_run_at timestamptz;
