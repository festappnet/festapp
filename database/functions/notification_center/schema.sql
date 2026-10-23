-- Private projections: no business-entity FK may prevent deletion of an order.
CREATE TABLE public.notification_center_activation (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
 enabled boolean NOT NULL DEFAULT false, activated_at timestamptz NOT NULL DEFAULT clock_timestamp(), generation bigint NOT NULL DEFAULT 1,
 timezone text NOT NULL DEFAULT 'Europe/Prague', collection_started_at timestamptz
);
CREATE TABLE public.notification_center_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
 occasion bigint, kind text NOT NULL, source_key text NOT NULL, actor uuid, occurred_at timestamptz NOT NULL,
 created_xid xid8 NOT NULL DEFAULT pg_current_xact_id(),
 data jsonb NOT NULL DEFAULT '{}', status text NOT NULL DEFAULT 'active', attention_revision bigint NOT NULL DEFAULT 1,
 affected_occasions bigint[] NOT NULL DEFAULT '{}', projected_revision bigint NOT NULL DEFAULT 0,
 UNIQUE(organization,source_key)
);
CREATE INDEX notification_center_order_projection ON public.notification_center_events(occasion,(data->>'orderId')) WHERE kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted');
CREATE INDEX notification_center_pending ON public.notification_center_events(organization,occurred_at) WHERE projected_revision<attention_revision;
CREATE TABLE public.notification_center_recipients (
 event_id uuid NOT NULL REFERENCES public.notification_center_events(id) ON DELETE CASCADE, recipient uuid NOT NULL,
 processed_revision bigint NOT NULL DEFAULT 0, eligible_revision bigint NOT NULL DEFAULT 1,
 PRIMARY KEY(event_id,recipient)
);
CREATE TABLE public.notification_center_user_state (
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE, recipient uuid NOT NULL,
 last_delivery_sequence bigint NOT NULL DEFAULT 0, read_through_sequence bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(organization,recipient), CHECK(read_through_sequence<=last_delivery_sequence)
);
CREATE TABLE public.notification_center_deliveries (
 event_id uuid NOT NULL REFERENCES public.notification_center_events(id) ON DELETE CASCADE, recipient uuid NOT NULL,
 organization bigint NOT NULL, attention_revision bigint NOT NULL, sequence bigint NOT NULL, group_key text NOT NULL,
 delivered_at timestamptz NOT NULL DEFAULT clock_timestamp(), PRIMARY KEY(event_id,recipient,attention_revision),
 UNIQUE(organization,recipient,sequence)
);
CREATE INDEX notification_center_personal_history ON public.notification_center_deliveries(organization,recipient,group_key,sequence DESC);
CREATE TABLE public.notification_center_preferences (
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE, recipient uuid NOT NULL, occasion bigint NOT NULL,
 muted boolean NOT NULL DEFAULT false, PRIMARY KEY(organization,recipient,occasion)
);
CREATE TABLE public.notification_center_source_state (
 organization bigint NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE, source_key text NOT NULL,
 state jsonb NOT NULL, episode bigint NOT NULL DEFAULT 0, observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(organization,source_key)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['activation','events','recipients','user_state','deliveries','preferences','source_state'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY','notification_center_'||t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role','notification_center_'||t);
 END LOOP;
END $$;
