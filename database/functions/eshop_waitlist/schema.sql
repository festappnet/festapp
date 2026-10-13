-- Additive ledger. Domain transitions are explicit commands, never triggers.
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS participant_capacity integer,
 ADD COLUMN IF NOT EXISTS waitlist_enabled boolean NOT NULL DEFAULT false,
 ADD COLUMN IF NOT EXISTS show_remaining_capacity boolean NOT NULL DEFAULT true,
 ADD COLUMN IF NOT EXISTS waitlist_offer_duration_seconds integer,
 ADD COLUMN IF NOT EXISTS capacity_revision bigint NOT NULL DEFAULT 0;
ALTER TABLE eshop.orders ADD COLUMN IF NOT EXISTS source_waitlist_order_id bigint REFERENCES eshop.orders(id);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='forms_capacity_configuration') THEN
  ALTER TABLE public.forms ADD CONSTRAINT forms_capacity_configuration CHECK (
   (participant_capacity IS NULL OR participant_capacity>0) AND
   (waitlist_offer_duration_seconds IS NULL OR waitlist_offer_duration_seconds>0) AND
   (NOT waitlist_enabled OR (participant_capacity IS NOT NULL AND waitlist_offer_duration_seconds IS NOT NULL AND waitlist_offer_duration_seconds>0)) AND
   (blueprint IS NULL OR (participant_capacity IS NULL AND NOT waitlist_enabled)));
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='orders_waitlist_finance') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_waitlist_finance CHECK
   (state IS DISTINCT FROM 'waitlisted' OR (price IS NULL AND payment_info IS NULL));
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS eshop.order_participants (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 current_order_id bigint NOT NULL REFERENCES eshop.orders(id),
 origin_order_id bigint NOT NULL REFERENCES eshop.orders(id),
 form_id bigint NOT NULL REFERENCES public.forms(id),
 answers jsonb NOT NULL DEFAULT '{}', ticket_id bigint UNIQUE REFERENCES eshop.tickets(id),
 lifecycle text NOT NULL CHECK(lifecycle IN ('waiting','offered','offer_expired','offer_declined','offer_cancelled','withdrawn','admitted','cancelled')),
 registered_at timestamptz NOT NULL DEFAULT now(), queue_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(id,form_id));
CREATE INDEX IF NOT EXISTS participants_form_queue ON eshop.order_participants(form_id,lifecycle,queue_at,id);
CREATE INDEX IF NOT EXISTS participants_current_order ON eshop.order_participants(current_order_id,id);
CREATE TABLE IF NOT EXISTS eshop.waitlist_offers (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), order_id bigint NOT NULL REFERENCES eshop.orders(id),
 form_id bigint NOT NULL REFERENCES public.forms(id), created_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 revision bigint NOT NULL, UNIQUE(id,form_id), CHECK(expires_at>created_at));
CREATE TABLE IF NOT EXISTS eshop.waitlist_offer_slots (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), offer_id uuid NOT NULL,
 participant_id uuid NOT NULL, form_id bigint NOT NULL,
 outcome text NOT NULL DEFAULT 'pending' CHECK(outcome IN ('pending','accepted','declined','expired','cancelled')),
 resulting_order_id bigint REFERENCES eshop.orders(id), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(offer_id,form_id) REFERENCES eshop.waitlist_offers(id,form_id),
 FOREIGN KEY(participant_id,form_id) REFERENCES eshop.order_participants(id,form_id));
CREATE UNIQUE INDEX IF NOT EXISTS waitlist_one_pending_slot ON eshop.waitlist_offer_slots(participant_id) WHERE outcome='pending';
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
 participant_ids uuid[] NOT NULL, slot_ids uuid[] NOT NULL,
 previous_order_data jsonb NOT NULL, previous_participants jsonb NOT NULL, previous_slots jsonb NOT NULL,
 state text NOT NULL DEFAULT 'preparing' CHECK(state IN ('preparing','completed','aborted')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE eshop.waitlist_acceptance_attempts ADD COLUMN IF NOT EXISTS previous_slots jsonb NOT NULL DEFAULT '[]';
CREATE INDEX IF NOT EXISTS waitlist_attempt_target ON eshop.waitlist_acceptance_attempts(target_order_id,state);
CREATE TABLE IF NOT EXISTS eshop.form_participant_backfill_issues (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id), form_id bigint NOT NULL REFERENCES public.forms(id),
 reason text NOT NULL, detected_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS orders_waitlist_source ON eshop.orders(source_waitlist_order_id);
-- Operational backfill requires an explicit single-organization scope from the
-- migration operator: SET LOCAL festapp.waitlist_backfill_organization = '3'.
-- Missing/empty scope intentionally inserts nothing. There is no all-tenant default.
-- One ticket is one person even when several product rows refer to it.
INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,ticket_id,lifecycle,registered_at,queue_at,answers)
 SELECT DISTINCT o.id,o.id,o.form,t.id,CASE WHEN o.state='storno' OR t.state='storno' THEN 'cancelled' ELSE 'admitted' END,
 o.created_at,o.created_at,coalesce((SELECT x FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) x WHERE x->>'id'=t.id::text LIMIT 1),'{}')
 FROM eshop.orders o JOIN eshop.order_product_ticket opt ON opt."order"=o.id JOIN eshop.tickets t ON t.id=opt.ticket
 WHERE o.form IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions backfill_scope
   WHERE backfill_scope.id=o.occasion AND backfill_scope.organization=
     NULLIF(current_setting('festapp.waitlist_backfill_organization',true),'')::bigint) AND o.state IS DISTINCT FROM 'waitlisted'
 AND (SELECT count(DISTINCT other."order") FROM eshop.order_product_ticket other WHERE other.ticket=t.id)=1
 ON CONFLICT(ticket_id) DO NOTHING;
INSERT INTO eshop.form_participant_backfill_issues(order_id,form_id,reason)
 SELECT o.id,o.form,'No unambiguous ticket/person linkage'
 FROM eshop.orders o WHERE o.form IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions backfill_scope
   WHERE backfill_scope.id=o.occasion AND backfill_scope.organization=
     NULLIF(current_setting('festapp.waitlist_backfill_organization',true),'')::bigint) AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted'
 AND (NOT EXISTS(SELECT 1 FROM eshop.order_participants p WHERE p.current_order_id=o.id)
 OR (jsonb_typeof(o.data->'tickets')='array' AND jsonb_array_length(o.data->'tickets')<>(SELECT count(*) FROM eshop.order_participants p WHERE p.current_order_id=o.id)))
 ON CONFLICT(order_id) DO NOTHING;
INSERT INTO eshop.form_participant_backfill_issues(order_id,form_id,reason)
 SELECT DISTINCT o.id,o.form,'Ticket linked to multiple orders' FROM eshop.orders o JOIN eshop.order_product_ticket opt ON opt."order"=o.id
 WHERE o.form IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions backfill_scope
   WHERE backfill_scope.id=o.occasion AND backfill_scope.organization=
     NULLIF(current_setting('festapp.waitlist_backfill_organization',true),'')::bigint) AND (SELECT count(DISTINCT x."order") FROM eshop.order_product_ticket x WHERE x.ticket=opt.ticket)>1
 ON CONFLICT(order_id) DO UPDATE SET reason=excluded.reason;
DO $$ DECLARE n text; BEGIN
 FOREACH n IN ARRAY ARRAY['order_participants','waitlist_offers','waitlist_offer_slots','waitlist_capabilities','waitlist_acceptance_attempts','form_participant_backfill_issues'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',n);
  EXECUTE format('REVOKE ALL ON TABLE eshop.%I FROM PUBLIC,anon,authenticated',n);
 END LOOP;
END $$;

-- Composite references prevent accidental cross-form ledger links even for private callers.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='orders_id_form_scope') THEN
  ALTER TABLE eshop.orders ADD CONSTRAINT orders_id_form_scope UNIQUE(id,form);
  ALTER TABLE eshop.order_participants ADD CONSTRAINT participants_current_scope FOREIGN KEY(current_order_id,form_id) REFERENCES eshop.orders(id,form);
  ALTER TABLE eshop.order_participants ADD CONSTRAINT participants_origin_scope FOREIGN KEY(origin_order_id,form_id) REFERENCES eshop.orders(id,form);
  ALTER TABLE eshop.waitlist_offers ADD CONSTRAINT offer_order_scope FOREIGN KEY(order_id,form_id) REFERENCES eshop.orders(id,form);
 END IF;
END $$;
