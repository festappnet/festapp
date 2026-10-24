-- Canonical ticket model. Domain transitions are explicit commands, never triggers.
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS participant_capacity integer,
 ADD COLUMN IF NOT EXISTS waitlist_enabled boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS show_remaining_capacity boolean NOT NULL DEFAULT true,
 ADD COLUMN IF NOT EXISTS waitlist_offer_duration_seconds integer,
 ADD COLUMN IF NOT EXISTS capacity_revision bigint NOT NULL DEFAULT 0;
ALTER TABLE eshop.orders ADD COLUMN IF NOT EXISTS source_waitlist_order_id bigint REFERENCES eshop.orders(id);
-- Cross-table blueprint compatibility is enforced by the form and occasion commands.
ALTER TABLE public.forms DROP CONSTRAINT IF EXISTS forms_capacity_configuration;
ALTER TABLE public.forms ADD CONSTRAINT forms_capacity_configuration CHECK (
   (participant_capacity IS NULL OR participant_capacity>0) AND
   (waitlist_offer_duration_seconds IS NULL OR waitlist_offer_duration_seconds>0) AND
   (NOT waitlist_enabled OR (participant_capacity IS NOT NULL AND waitlist_offer_duration_seconds IS NOT NULL AND waitlist_offer_duration_seconds>0)));
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='orders_waitlist_finance') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_waitlist_finance CHECK
   (state IS DISTINCT FROM 'waitlisted' OR (price IS NULL AND payment_info IS NULL));
 END IF;
END $$;
-- Tickets are the only live identity. No participant backfill or shadow state.
ALTER TABLE eshop.tickets ADD COLUMN IF NOT EXISTS data jsonb NOT NULL DEFAULT '{}',
 ADD COLUMN IF NOT EXISTS waitlist_queue_at timestamptz;
ALTER TABLE eshop.tickets DROP CONSTRAINT IF EXISTS tickets_state_check;
ALTER TABLE eshop.tickets ADD CONSTRAINT tickets_state_check CHECK(state IN ('ordered','paid','sent','used','storno','waitlisted'));
ALTER TABLE eshop.tickets DROP CONSTRAINT IF EXISTS tickets_waitlist_non_admission;
ALTER TABLE eshop.tickets ADD CONSTRAINT tickets_waitlist_non_admission CHECK(state IS DISTINCT FROM 'waitlisted' OR ticket_symbol IS NULL);
CREATE INDEX IF NOT EXISTS tickets_waitlist_queue ON eshop.tickets(waitlist_queue_at,id) WHERE state='waitlisted';
CREATE TABLE IF NOT EXISTS eshop.waitlist_offers (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), order_id bigint NOT NULL REFERENCES eshop.orders(id),
 form_id bigint NOT NULL REFERENCES public.forms(id), created_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 revision bigint NOT NULL, UNIQUE(id,form_id), CHECK(expires_at>created_at));
CREATE TABLE IF NOT EXISTS eshop.waitlist_offer_slots (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), offer_id uuid NOT NULL,
 ticket_id bigint NOT NULL REFERENCES eshop.tickets(id), form_id bigint NOT NULL,
 outcome text NOT NULL DEFAULT 'pending' CHECK(outcome IN ('pending','accepted','declined','expired','cancelled')),
 resulting_order_id bigint REFERENCES eshop.orders(id), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(offer_id,form_id) REFERENCES eshop.waitlist_offers(id,form_id));
CREATE UNIQUE INDEX IF NOT EXISTS waitlist_one_pending_slot ON eshop.waitlist_offer_slots(ticket_id) WHERE outcome='pending';
CREATE INDEX IF NOT EXISTS waitlist_slots_offer ON eshop.waitlist_offer_slots(offer_id,outcome);
CREATE INDEX IF NOT EXISTS waitlist_offers_expiry ON eshop.waitlist_offers(expires_at,form_id);
CREATE TABLE IF NOT EXISTS eshop.waitlist_capabilities (
 token_hash text PRIMARY KEY CHECK(token_hash ~ '^[0-9a-f]{64}$'),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 form_id bigint NOT NULL REFERENCES public.forms(id), order_id bigint NOT NULL REFERENCES eshop.orders(id),
 offer_id uuid REFERENCES eshop.waitlist_offers(id), kind text NOT NULL CHECK(kind IN ('manage','offer')),
 expires_at timestamptz, revoked_at timestamptz,
 CHECK((kind='offer' AND offer_id IS NOT NULL AND expires_at IS NOT NULL) OR (kind='manage' AND offer_id IS NULL)));
CREATE TABLE IF NOT EXISTS eshop.waitlist_acceptance_attempts (
 command_id uuid PRIMARY KEY, source_order_id bigint NOT NULL REFERENCES eshop.orders(id),
 target_order_id bigint NOT NULL REFERENCES eshop.orders(id), offer_id uuid NOT NULL REFERENCES eshop.waitlist_offers(id),
 conversion text NOT NULL CHECK(conversion IN ('in_place','split')),
 ticket_ids bigint[] NOT NULL, slot_ids uuid[] NOT NULL,
 previous_order_data jsonb NOT NULL, previous_tickets jsonb NOT NULL, previous_links jsonb NOT NULL, previous_slots jsonb NOT NULL,
 state text NOT NULL DEFAULT 'preparing' CHECK(state IN ('preparing','completed','aborted')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE eshop.waitlist_acceptance_attempts ADD COLUMN IF NOT EXISTS previous_slots jsonb NOT NULL DEFAULT '[]';
CREATE INDEX IF NOT EXISTS waitlist_attempt_target ON eshop.waitlist_acceptance_attempts(target_order_id,state);
CREATE INDEX IF NOT EXISTS orders_waitlist_source ON eshop.orders(source_waitlist_order_id);
DO $$ DECLARE n text; BEGIN
 FOREACH n IN ARRAY ARRAY['waitlist_offers','waitlist_offer_slots','waitlist_capabilities','waitlist_acceptance_attempts'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',n);
  EXECUTE format('REVOKE ALL ON TABLE eshop.%I FROM PUBLIC,anon,authenticated',n);
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='orders_id_form_scope') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_id_form_scope UNIQUE(id,form);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='offer_order_scope') THEN
  ALTER TABLE eshop.waitlist_offers ADD CONSTRAINT offer_order_scope FOREIGN KEY(order_id,form_id) REFERENCES eshop.orders(id,form);
 END IF;
END $$;
