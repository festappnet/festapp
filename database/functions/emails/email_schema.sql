-- Cutover only under maintenance: old senders must be stopped first.
-- Invoker producers use extensions.digest under the runtime role, not postgres.
GRANT USAGE ON SCHEMA extensions TO service_role;
ALTER TABLE public.queue_emails RENAME TO email_messages;
ALTER SEQUENCE public.queue_emails_id_seq RENAME TO email_messages_id_seq;
REVOKE ALL ON SEQUENCE public.email_messages_id_seq FROM PUBLIC,anon,authenticated;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_pkey TO email_messages_pkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_occasion_fkey TO email_messages_occasion_fkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_organization_fkey TO email_messages_organization_fkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_unit_fkey TO email_messages_unit_fkey;
ALTER INDEX public.queue_emails_ticket_order_command_idx RENAME TO email_messages_ticket_order_command_idx;
ALTER TABLE public.email_messages
  ADD COLUMN message_id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  ADD COLUMN message_kind text,
  ADD COLUMN dedupe_key text,
  ADD COLUMN input_hash text,
  ADD COLUMN workflow_state text NOT NULL DEFAULT 'pending',
  ADD COLUMN recipient text,
  ADD COLUMN recipient_user uuid,
  ADD COLUMN order_id bigint,
  ADD COLUMN source_version bigint,
  ADD COLUMN priority integer NOT NULL DEFAULT 50,
  ADD COLUMN expires_at timestamptz,
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_until timestamptz,
  ADD COLUMN prepared jsonb,
  ADD COLUMN prepared_hash text,
  ADD COLUMN prepared_at timestamptz,
  ADD COLUMN provider_message_id text,
  ADD COLUMN accepted_at timestamptz,
  ADD COLUMN delivered_at timestamptz,
  ADD COLUMN bounced_at timestamptz,
  ADD COLUMN complained_at timestamptz,
  ADD COLUMN opened_at timestamptz,
  ADD COLUMN clicked_at timestamptz,
  ADD COLUMN provider_failure text,
  ADD COLUMN feedback_pending boolean NOT NULL DEFAULT false,
  ADD COLUMN tracking_policy text NOT NULL DEFAULT 'disabled',
  ADD COLUMN post_action jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN post_action_state text NOT NULL DEFAULT 'pending';
ALTER TABLE eshop.orders ADD COLUMN email_payment_version bigint NOT NULL DEFAULT 0;
ALTER TABLE eshop.payment_info ADD COLUMN email_reminder_version bigint NOT NULL DEFAULT 0;
UPDATE public.email_messages SET
  message_id = (substr(md5('festapp:email:'||id),1,8)||'-'||substr(md5('festapp:email:'||id),9,4)||'-4'||substr(md5('festapp:email:'||id),14,3)||'-8'||substr(md5('festapp:email:'||id),18,3)||'-'||substr(md5('festapp:email:'||id),21,12))::uuid,
  dedupe_key='legacy:'||id,
  message_kind=CASE code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation'
    WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
    WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder'
    WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
    ELSE 'legacy_unknown' END,
  order_id=coalesce((data->>'order_id')::bigint,(data#>>'{ticket_order,order,id}')::bigint),
  workflow_state=CASE WHEN target_time='infinity' THEN 'blocked'
    WHEN code NOT IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO') OR processing_at IS NOT NULL OR attempt_count>0 THEN 'unknown' ELSE 'pending' END,
  tracking_policy=CASE WHEN code IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO') THEN 'open' ELSE 'disabled' END,
  input_hash=encode(extensions.digest(coalesce(data,'{}')::text,'sha256'),'hex');
UPDATE public.email_messages m SET recipient=o.data->>'email',source_version=CASE WHEN m.message_kind='order_reminder' THEN pi.email_reminder_version ELSE o.email_payment_version END
 FROM eshop.orders o LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=m.order_id;
ALTER TABLE public.email_messages ALTER COLUMN message_kind SET NOT NULL;
ALTER TABLE public.email_messages ALTER COLUMN dedupe_key SET NOT NULL;
ALTER TABLE public.email_messages ALTER COLUMN input_hash SET NOT NULL;
ALTER TABLE public.email_messages ADD CONSTRAINT email_workflow CHECK(workflow_state IN
 ('blocked','pending','preparing','sending','accepted','retry_wait','unknown','dead','cancelled','suppressed','expired'));
CREATE UNIQUE INDEX email_message_uuid ON public.email_messages(message_id);
CREATE UNIQUE INDEX email_message_dedupe ON public.email_messages(organization,message_kind,dedupe_key);
CREATE INDEX email_due ON public.email_messages(priority,target_time,id) WHERE workflow_state IN ('pending','retry_wait');
CREATE INDEX email_active_leases ON public.email_messages(lease_until) WHERE workflow_state IN ('preparing','sending');
CREATE INDEX email_order_summary ON public.email_messages(occasion,order_id,created_at DESC);
CREATE UNIQUE INDEX email_provider_message ON public.email_messages(provider_message_id) WHERE provider_message_id IS NOT NULL;
CREATE TABLE public.email_attempts (
 attempt_id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), message_id uuid NOT NULL REFERENCES public.email_messages(message_id),
 lease_token uuid NOT NULL, state text NOT NULL CHECK(state IN ('preparing','sending','accepted','not_accepted','unknown','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(), began_at timestamptz, finished_at timestamptz, provider_message_id text,
 error_code text, UNIQUE(message_id,lease_token));
CREATE TABLE public.email_delivery_events (
 event_key text PRIMARY KEY, provider_message_id text NOT NULL, attempt_id uuid, recipient text NOT NULL,
 event_type text NOT NULL CHECK(event_type IN ('send','delivery','delay','bounce','complaint','reject','rendering_failure','open','click')),
 provider_time timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(), hard_bounce boolean NOT NULL DEFAULT false, invalid_recipient boolean NOT NULL DEFAULT false,
 message_id uuid REFERENCES public.email_messages(message_id));
CREATE INDEX email_event_history ON public.email_delivery_events(message_id,provider_time);
CREATE INDEX email_attempt_history ON public.email_attempts(created_at);
CREATE INDEX email_unmatched ON public.email_delivery_events(provider_message_id) WHERE message_id IS NULL;
CREATE TABLE public.email_suppressions (recipient text PRIMARY KEY, reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
-- One account/region authority for all tenants and gateway instances. No tenant key.
CREATE TABLE public.email_capacity (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), account_id text, region text,
 paused boolean NOT NULL DEFAULT true, worker_url text, quota_refresh_until timestamptz, quota_at timestamptz, max_rate numeric, daily_quota numeric,
 provider_sent_24h numeric, shared_account boolean NOT NULL DEFAULT true, allocated_rate numeric, allocated_daily numeric,
 provider_outage_streak integer NOT NULL DEFAULT 0 CHECK(provider_outage_streak>=0), probe_until timestamptz, probe_attempt uuid,
 next_send_at timestamptz NOT NULL DEFAULT now(), circuit_until timestamptz, rate_factor numeric NOT NULL DEFAULT 1 CHECK(rate_factor>0 AND rate_factor<=1),
 max_preparing integer NOT NULL DEFAULT 2 CHECK(max_preparing BETWEEN 1 AND 8), max_sending integer NOT NULL DEFAULT 2 CHECK(max_sending BETWEEN 1 AND 8),
 wake_error text, heartbeat_at timestamptz);
INSERT INTO public.email_capacity(singleton) VALUES(true);
ALTER TABLE public.email_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_capacity ENABLE ROW LEVEL SECURITY;
-- Remove inherited queue policies: internal-only tables, explicit read RPCs.
DO $$ DECLARE p record; BEGIN FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='email_messages' LOOP
 EXECUTE format('DROP POLICY %I ON public.email_messages',p.policyname); END LOOP; END $$;
REVOKE ALL ON public.email_messages,public.email_attempts,public.email_delivery_events,public.email_suppressions,public.email_capacity FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.email_messages,public.email_attempts,public.email_delivery_events,public.email_suppressions,public.email_capacity TO service_role;
CREATE TABLE public.email_confirmation_receipts (
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),message_id uuid NOT NULL REFERENCES public.email_messages(message_id),
 expires_at timestamptz NOT NULL,reads integer NOT NULL DEFAULT 0);
ALTER TABLE public.email_confirmation_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.email_confirmation_receipts FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.email_confirmation_receipts TO service_role;

-- A public client must not mint or read the machine proof used by email/other system workers.
REVOKE ALL ON public.request_secrets FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.request_secrets TO service_role;
REVOKE ALL ON FUNCTION public.generate_request_secret(integer),public.check_request_secret(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.generate_request_secret(integer),public.check_request_secret(text) TO service_role;
