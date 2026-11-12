-- Recipient locks precede cursor, dispatch and the existing queue locks.
CREATE TABLE public.notification_center_email_profiles (
 recipient uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 stopped boolean NOT NULL DEFAULT true, locale text NOT NULL DEFAULT 'cs' CHECK(locale IN ('cs','en','de','pl','sk','uk')),
 revision bigint NOT NULL DEFAULT 0, collected_at timestamptz NOT NULL DEFAULT '-infinity'
);
CREATE TABLE public.notification_center_email_subscriptions (
 recipient uuid NOT NULL REFERENCES public.notification_center_email_profiles(recipient) ON DELETE CASCADE,
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 occasion bigint, kinds jsonb NOT NULL DEFAULT '{}', enabled_from timestamptz NOT NULL DEFAULT clock_timestamp(),
 revision bigint NOT NULL DEFAULT 1,
 UNIQUE NULLS NOT DISTINCT(recipient,organization,occasion),
 CHECK(jsonb_typeof(kinds)='object')
);
-- Stored scope must match the real occasion, including direct privileged inserts.
ALTER TABLE public.occasions ADD CONSTRAINT notification_email_occasion_scope UNIQUE(id,organization);
ALTER TABLE public.notification_center_email_subscriptions ADD FOREIGN KEY(occasion,organization)
 REFERENCES public.occasions(id,organization) ON DELETE CASCADE;
ALTER TABLE public.notification_center_organizations ADD COLUMN email_collection_started_at timestamptz;
ALTER TABLE public.notification_center_user_state ADD COLUMN email_scanned_sequence bigint NOT NULL DEFAULT 0,
 ADD CONSTRAINT notification_email_cursor CHECK(email_scanned_sequence>=0 AND email_scanned_sequence<=last_delivery_sequence);
CREATE INDEX notification_email_unscanned ON public.notification_center_user_state(recipient,organization)
 WHERE email_scanned_sequence<last_delivery_sequence;
CREATE TABLE public.notification_center_email_dispatches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 recipient uuid NOT NULL,
 opened_at timestamptz NOT NULL DEFAULT clock_timestamp(), due_at timestamptz NOT NULL,
 next_attempt_at timestamptz NOT NULL DEFAULT '-infinity',
 state text NOT NULL DEFAULT 'collecting' CHECK(state IN ('collecting','queued','omitted')),
 message_id uuid UNIQUE REFERENCES public.email_messages(message_id),
 UNIQUE(id,recipient), CHECK(due_at=opened_at+public.notification_center_email_window_internal()),
 CHECK((state='queued')=(message_id IS NOT NULL))
);
CREATE UNIQUE INDEX notification_email_collecting ON public.notification_center_email_dispatches(recipient) WHERE state='collecting';
CREATE INDEX notification_email_due ON public.notification_center_email_dispatches(due_at,recipient) WHERE state='collecting';
CREATE TABLE public.notification_center_email_items (
 recipient uuid NOT NULL REFERENCES public.notification_center_email_profiles(recipient) ON DELETE CASCADE,
 delivery_key text NOT NULL, admitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 dispatch_id uuid, disposition text CHECK(disposition IN ('omitted','baseline')),
 PRIMARY KEY(recipient,delivery_key),
 FOREIGN KEY(dispatch_id,recipient) REFERENCES public.notification_center_email_dispatches(id,recipient) ON DELETE CASCADE,
 CHECK((dispatch_id IS NOT NULL)<>(disposition IS NOT NULL))
);
ALTER TABLE public.notification_center_events ADD CONSTRAINT notification_email_event_scope UNIQUE(id,organization);
ALTER TABLE public.notification_center_deliveries ADD CONSTRAINT notification_email_delivery_source UNIQUE(event_id,recipient,organization,sequence);
CREATE TABLE public.notification_center_email_item_sources (
 event_id uuid NOT NULL, recipient uuid NOT NULL, organization bigint NOT NULL,
 delivery_key text NOT NULL, first_sequence bigint NOT NULL, enabled_from timestamptz NOT NULL,
 PRIMARY KEY(event_id,recipient),
 FOREIGN KEY(recipient,delivery_key) REFERENCES public.notification_center_email_items(recipient,delivery_key) ON DELETE CASCADE,
 FOREIGN KEY(event_id,recipient) REFERENCES public.notification_center_recipients(event_id,recipient) ON DELETE CASCADE,
 FOREIGN KEY(event_id,organization) REFERENCES public.notification_center_events(id,organization) ON DELETE CASCADE,
 FOREIGN KEY(event_id,recipient,organization,first_sequence)
 REFERENCES public.notification_center_deliveries(event_id,recipient,organization,sequence) ON DELETE CASCADE
);
CREATE INDEX notification_email_item_age ON public.notification_center_email_items(recipient,admitted_at);
CREATE INDEX notification_email_sources_item ON public.notification_center_email_item_sources(recipient,delivery_key);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['profiles','subscriptions','dispatches','items','item_sources'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY','notification_center_email_'||t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role','notification_center_email_'||t);
 END LOOP;
END $$;

DROP INDEX public.notification_center_order_projection;
CREATE INDEX notification_center_order_projection ON public.notification_center_events(occasion,(data->>'orderId'),id)
 WHERE kind IN ('order_created','waitlist_registered','order_cancelled','order_payment_received','payment_problem','offer_accepted','offer_declined','offer_expired');

INSERT INTO public.notification_center_maintenance(name) VALUES('email-collection') ON CONFLICT DO NOTHING;
