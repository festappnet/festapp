-- The dispatch retains an audit UUID after account deletion; it owns no address.
-- Account deletion removes profiles, memberships and subscriptions, invalidating
-- unsent intents without a queue/identity FK cycle.
ALTER TABLE public.email_messages ALTER COLUMN organization DROP NOT NULL;
ALTER TABLE public.email_messages ADD COLUMN notification_dispatch_id uuid;
ALTER TABLE public.email_messages ADD CONSTRAINT email_recipient_scope CHECK(
 (message_kind='admin_notification_digest' AND organization IS NULL AND recipient_user IS NOT NULL
  AND occasion IS NULL AND unit IS NULL AND order_id IS NULL AND notification_dispatch_id IS NOT NULL AND tracking_policy='disabled')
 OR (message_kind<>'admin_notification_digest' AND organization IS NOT NULL AND notification_dispatch_id IS NULL));
ALTER TABLE public.email_messages ADD CONSTRAINT email_dispatch_recipient FOREIGN KEY(notification_dispatch_id,recipient_user)
 REFERENCES public.notification_center_email_dispatches(id,recipient);
CREATE UNIQUE INDEX email_notification_dedupe ON public.email_messages(recipient_user,message_kind,dedupe_key) WHERE message_kind='admin_notification_digest';
CREATE UNIQUE INDEX email_notification_active ON public.email_messages(recipient_user) WHERE message_kind='admin_notification_digest'
 AND workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown');
ALTER TABLE public.email_messages DROP CONSTRAINT email_messages_admission_class_check;
ALTER TABLE public.email_messages ADD CONSTRAINT email_messages_admission_class_check CHECK(admission_class IN ('ordinary','auth','commitment','notification'));
-- A dispatch can link only its own recipient's queue intent, in both directions.
CREATE UNIQUE INDEX email_notification_dispatch_identity ON public.email_messages(message_id,recipient_user,notification_dispatch_id);
ALTER TABLE public.notification_center_email_dispatches DROP CONSTRAINT notification_center_email_dispatches_message_id_fkey;
ALTER TABLE public.notification_center_email_dispatches ADD CONSTRAINT notification_email_message_owner
 FOREIGN KEY(message_id,recipient,id) REFERENCES public.email_messages(message_id,recipient_user,notification_dispatch_id);
