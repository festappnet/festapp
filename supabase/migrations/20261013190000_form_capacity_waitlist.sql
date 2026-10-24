-- Canonical form-capacity and waitlist expansion. Additive defaults keep existing forms unlimited.

-- Source: database/functions/eshop_waitlist/schema.sql
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


-- Source: database/functions/eshop_waitlist/form_capacity.sql
CREATE OR REPLACE FUNCTION public.get_form_capacity_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH counts AS (
 SELECT f.*, (SELECT count(*) FROM eshop.order_participants p JOIN eshop.orders o ON o.id=p.current_order_id
  WHERE p.form_id=f.id AND p.lifecycle='admitted' AND o.state IS DISTINCT FROM 'storno') occupied,
 (SELECT count(*) FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.form_id=f.id AND s.outcome='pending' AND w.expires_at>p_at) reserved,
 (SELECT count(*) FROM eshop.order_participants p WHERE p.form_id=f.id AND p.lifecycle='waiting') waiting
 FROM public.forms f WHERE f.id=p_form), free AS (
 SELECT *,greatest(participant_capacity-occupied-reserved,0) available FROM counts)
 SELECT jsonb_build_object('enabled',participant_capacity IS NOT NULL,'limit',participant_capacity,
 'remainingPublic',CASE WHEN participant_capacity IS NOT NULL THEN greatest(available-waiting,0) END,
 'showRemaining',show_remaining_capacity,'occupiedPeople',occupied,'offeredPlaces',reserved,'waitingPeople',waiting,
 'offerablePlaces',available,'heldForWaiting',least(available,waiting),'revision',capacity_revision,
 'canSendOffers',waitlist_enabled AND available>0,'blockedReason',CASE WHEN NOT waitlist_enabled THEN 'WAITLIST_NOT_AVAILABLE'
 WHEN available=0 THEN 'FORM_CAPACITY_EXCEEDED' END,'serverTime',p_at) FROM free;
$$;
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; d jsonb; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form; d:=public.get_effective_form_data(p_form);
 IF NOT f.is_open OR p_at < nullif(coalesce(d#>>'{schedule,start_time}',d->>'start_time'),'')::timestamptz
 OR p_at > nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL THEN RETURN 'blueprint'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF f.participant_capacity IS NULL OR (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;
CREATE OR REPLACE FUNCTION public.check_form_capacity_settings_internal(p_form bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; n integer; enabled boolean; bp bigint;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 c:=public.get_form_capacity_snapshot_internal(p_form);
 n:=CASE WHEN p_input ? 'participant_capacity' THEN (p_input->>'participant_capacity')::integer ELSE f.participant_capacity END;
 enabled:=CASE WHEN p_input ? 'waitlist_enabled' THEN (p_input->>'waitlist_enabled')::boolean ELSE f.waitlist_enabled END;
 bp:=CASE WHEN p_input ? 'blueprint' THEN nullif(p_input->>'blueprint','')::bigint ELSE f.blueprint END;
 IF n IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.form_participant_backfill_issues WHERE form_id=p_form) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','PARTICIPANT_BACKFILL_REQUIRED','message','Participant data requires repair')::text; END IF;
 IF n IS NOT NULL AND n<(c->>'occupiedPeople')::bigint+(c->>'offeredPlaces')::bigint THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','CAPACITY_BELOW_COMMITTED','capacity',c)::text; END IF;
 IF ((NOT enabled) OR n IS NULL OR bp IS NOT NULL) AND
 ((c->>'waitingPeople')::bigint>0 OR (c->>'offeredPlaces')::bigint>0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','WAITLIST_HAS_ACTIVE_ENTRIES','capacity',c)::text; END IF;
 IF bp IS NOT NULL AND (n IS NOT NULL OR enabled) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','BLUEPRINT_CONFLICT')::text; END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_form_capacity_snapshot_internal(bigint,timestamptz),
 public.get_form_registration_mode_internal(bigint,timestamptz),public.check_form_capacity_settings_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_waitlist/participants.sql
CREATE OR REPLACE FUNCTION public.allocate_ticket_order_identity_internal(p_form bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o bigint; occ bigint; seq bigint; attempt integer;
BEGIN
 SELECT occasion INTO STRICT occ FROM public.forms WHERE id=p_form FOR UPDATE;
 seq:=public.next_order_sequence(occ);
 FOR attempt IN 1..10 LOOP
  INSERT INTO eshop.orders(form,occasion,order_symbol,order_sequence,state)
   VALUES(p_form,occ,public.generate_order_symbol(),seq,'ordered')
   ON CONFLICT ON CONSTRAINT orders_order_symbol_key DO NOTHING RETURNING id INTO o;
  IF o IS NOT NULL THEN RETURN o; END IF;
 END LOOP;
 RAISE EXCEPTION 'Order symbol allocation exhausted';
END $$;
CREATE OR REPLACE FUNCTION public.lock_order_capacity_scope_internal(p_orders bigint[])
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(p_orders)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.orders WHERE id=ANY(p_orders) ORDER BY id FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.lock_ticket_order_products_internal(p_order bigint,p_input jsonb DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 SELECT coalesce(array_agg(DISTINCT id),'{}') INTO ids FROM (
  SELECT product id FROM eshop.order_product_ticket WHERE "order"=p_order
  UNION ALL SELECT (f->>'product_type')::bigint FROM jsonb_array_elements(coalesce(p_input->'ticket','[]')) t
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) f WHERE f ? 'product_type'
  UNION ALL SELECT s.product FROM jsonb_array_elements(coalesce(p_input->'ticket','[]')) t JOIN eshop.spots s ON s.id=(t->>'spot')::bigint) selected;
 PERFORM 1 FROM eshop.products WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id WHERE pic.product=ANY(ids)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(ids)) ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.allocate_ticket_order_identity_internal(bigint),public.lock_order_capacity_scope_internal(bigint[]),
 public.lock_ticket_order_products_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;

-- One transport normalization for ordinary, offered and waiting people. Older
-- clients identify ticket fields by their exact _subFieldId and typed key;
-- current clients additionally send the stable numeric field ID.
CREATE OR REPLACE FUNCTION public.normalize_form_participant_answers_internal(p_form bigint,p_people jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE people jsonb:='[]'; person jsonb; answer jsonb; fields jsonb; field_id bigint; numeric_keys text[];
 definition public.form_fields; value jsonb; seen bigint[];
BEGIN
 IF jsonb_typeof(p_people) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid participant answers'; END IF;
 FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
  fields:='[]'; seen:='{}';
  IF person ? 'fields' AND jsonb_typeof(person->'fields') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid participant fields'; END IF;
  FOR answer IN SELECT * FROM jsonb_array_elements(coalesce(person->'fields','[]')) LOOP
   IF jsonb_typeof(answer) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid participant field'; END IF;
   SELECT coalesce(array_agg(key),'{}') INTO numeric_keys FROM jsonb_object_keys(answer) key WHERE key ~ '^[0-9]+$';
   IF cardinality(numeric_keys)>1 THEN RAISE EXCEPTION 'FORM_FIELD_AMBIGUOUS'; END IF;
   field_id:=NULL;
   IF answer ? '_subFieldId' THEN
    IF coalesce(answer->>'_subFieldId','') !~ '^[1-9][0-9]{0,17}$' THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    field_id:=(answer->>'_subFieldId')::bigint;
    IF cardinality(numeric_keys)=1 AND numeric_keys[1]<>field_id::text THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
   ELSIF cardinality(numeric_keys)=1 THEN
    IF numeric_keys[1] !~ '^[1-9][0-9]{0,17}$' THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    field_id:=numeric_keys[1]::bigint;
   END IF;
   IF field_id IS NOT NULL THEN
    SELECT * INTO definition FROM public.form_fields WHERE id=field_id AND form=p_form AND is_ticket_field AND NOT is_hidden;
    IF NOT FOUND THEN RAISE EXCEPTION 'FORM_FIELD_SCOPE_MISMATCH'; END IF;
    IF field_id=ANY(seen) THEN RAISE EXCEPTION 'FORM_FIELD_AMBIGUOUS'; END IF;
    seen:=seen||field_id;
    IF NOT answer ? field_id::text AND NOT answer ? definition.type THEN RAISE EXCEPTION 'FORM_FIELD_TYPE_MISMATCH'; END IF;
    IF answer ? field_id::text AND answer ? definition.type AND answer->(field_id::text) IS DISTINCT FROM answer->definition.type THEN
     RAISE EXCEPTION 'FORM_FIELD_VALUE_CONFLICT'; END IF;
    -- A typed name cannot stand in for another field type with the same ID.
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(answer) key WHERE key<>field_id::text AND key<>definition.type
     AND key NOT IN ('_subFieldId','currency_code') AND NOT (definition.type='product_type' AND key='price')) THEN
      RAISE EXCEPTION 'FORM_FIELD_TYPE_MISMATCH'; END IF;
    value:=coalesce(answer->(field_id::text),answer->definition.type);
    IF definition.type='product_type' THEN
     IF NOT EXISTS(SELECT 1 FROM eshop.products product WHERE product.id=(value#>>'{}')::bigint
       AND product.product_type=definition.product_type) THEN RAISE EXCEPTION 'PRODUCT_SCOPE_MISMATCH'; END IF;
     -- Existing product selections carry a UI price hint. Discard it here;
     -- the shared finalizer obtains the authoritative price from the product.
     answer:=answer-'price';
    END IF;
    answer:=answer||jsonb_build_object(field_id::text,value,definition.type,value,'_subFieldId',field_id);
   END IF;
   fields:=fields||jsonb_build_array(answer);
  END LOOP;
  people:=people||jsonb_build_array(jsonb_set(person,'{fields}',fields,true));
 END LOOP;
 RETURN people;
END $$;
REVOKE ALL ON FUNCTION public.normalize_form_participant_answers_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;

-- Domain answers contain stable personal field IDs only. Transport aliases,
-- product choices and client metadata remain outside the participant ledger.
CREATE OR REPLACE FUNCTION public.extract_participant_answers_internal(p_form bigint,p_person jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('fields',coalesce(jsonb_agg(jsonb_build_object(answer.key,answer.value)
   ORDER BY definition."order" NULLS LAST,definition.id),'[]'))
 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_person->'fields')='array' THEN p_person->'fields' ELSE '[]' END) field
 CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(field)='object' THEN field ELSE '{}' END) answer
 JOIN public.form_fields definition ON definition.id::text=answer.key
 WHERE definition.form=p_form AND definition.is_ticket_field AND NOT definition.is_hidden
  AND definition.type NOT IN ('product_type','spot','ticket','html');
$$;
REVOKE ALL ON FUNCTION public.extract_participant_answers_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_waitlist/capabilities.sql
CREATE OR REPLACE FUNCTION public.get_effective_waitlist_participant_lifecycle_internal(p_person uuid)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN person.lifecycle='offered' AND EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.participant_id=person.id AND s.outcome='pending' AND w.expires_at<=clock_timestamp())
 THEN 'offer_expired' ELSE person.lifecycle END
 FROM eshop.order_participants person WHERE person.id=p_person;
$$;
REVOKE ALL ON FUNCTION public.get_effective_waitlist_participant_lifecycle_internal(uuid)
 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.check_waitlist_scope_internal(p_order bigint,p_offer uuid,p_token text,p_actor uuid,p_operation text)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; c eshop.waitlist_capabilities; occ public.occasions;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order; SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 IF o.id IS NULL OR o.form IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=o.occasion AND "user"=p_actor AND is_editor_order) THEN
  IF p_offer IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order AND form_id=o.form) THEN
   RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF; RETURN o.form;
 END IF;
 IF p_operation IN ('send','cancel','proposal') OR p_token IS NULL OR length(p_token)<>64 THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 SELECT * INTO c FROM eshop.waitlist_capabilities WHERE token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 AND organization_id=occ.organization AND form_id=o.form AND order_id=o.id AND (revoked_at IS NULL OR p_operation='read')
 AND ((p_operation='withdraw' AND kind='manage' AND o.state='waitlisted') OR
 (p_operation IN ('read','accept','decline') AND kind='offer' AND offer_id=p_offer));
 IF c.token_hash IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Expired offer links may read their own terminal state; writers recheck time under locks.
 IF p_operation<>'read' AND c.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 RETURN o.form;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_summary_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH effective AS (SELECT public.get_effective_waitlist_participant_lifecycle_internal(person.id) lifecycle
 FROM eshop.order_participants person WHERE current_order_id=p_order), p AS (SELECT lifecycle,count(*) n FROM effective GROUP BY lifecycle),
 s AS (SELECT count(*) n,min(w.expires_at) expiry FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers w ON w.id=x.offer_id
 JOIN eshop.order_participants person ON person.id=x.participant_id WHERE person.current_order_id=p_order AND x.outcome='pending' AND w.expires_at>clock_timestamp())
 SELECT jsonb_build_object('counts',coalesce((SELECT jsonb_object_agg(lifecycle,n) FROM p),'{}'),
 'pendingPlaces',s.n,'earliestExpiry',s.expiry,'isActive',CASE WHEN o.state='waitlisted' THEN
  coalesce((SELECT n>0 FROM p WHERE lifecycle='waiting'),false) OR s.n>0 ELSE o.state IS DISTINCT FROM 'storno' END,
 'allowedActions',CASE WHEN o.state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN o.state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN o.state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END)
 FROM eshop.orders o CROSS JOIN s WHERE o.id=p_order;
$$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_form(p_token text DEFAULT NULL,p_offer_id uuid DEFAULT NULL,p_order_id bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oid bigint; fid bigint; bundle jsonb; w eshop.waitlist_offers;
BEGIN
 PERFORM set_config('response.headers','[{"Cache-Control":"no-store"},{"Referrer-Policy":"no-referrer"}]',true);
 SELECT * INTO w FROM eshop.waitlist_offers WHERE id=p_offer_id;
 oid:=coalesce(w.order_id,p_order_id);
 fid:=public.check_waitlist_scope_internal(oid,p_offer_id,p_token,auth.uid(),CASE WHEN p_offer_id IS NULL THEN 'withdraw' ELSE 'read' END);
 -- Terminal links explain their own outcome without exposing form answers,
 -- contact data, products, or payment details after capability revocation.
 IF p_offer_id IS NOT NULL AND (w.expires_at<=clock_timestamp() OR NOT EXISTS(
  SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending')) THEN
  RETURN jsonb_build_object('code',200,'registrationMode','offer','form',NULL,
   'offerId',w.id,'pendingCount',0,'expiresAt',w.expires_at,'serverTime',clock_timestamp(),
   'offerStatus',CASE WHEN w.expires_at<=clock_timestamp() THEN 'expired'
    WHEN EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome IN ('declined','cancelled')) THEN 'cancelled'
    ELSE 'accepted' END,'participants','[]'::jsonb,'slots','[]'::jsonb);
 END IF;
 bundle:=public.get_form_bundle_internal(fid,true)::jsonb;
 bundle:=jsonb_set(bundle,'{data,registrationMode}',to_jsonb(CASE WHEN p_offer_id IS NOT NULL THEN 'offer'::text ELSE 'waitlist' END),true);
 RETURN jsonb_build_object('code',200,'form',bundle->'data','registrationMode',CASE WHEN p_offer_id IS NOT NULL THEN 'offer' ELSE 'waitlist' END,
  'orderData',(SELECT data FROM eshop.orders WHERE id=oid),'pendingCount',(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending' AND w.expires_at>clock_timestamp()),
  'orderId',oid,'offerId',p_offer_id,'serverTime',clock_timestamp(),'expiresAt',w.expires_at,
  'participants',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'answers',public.extract_participant_answers_internal(fid,answers),'lifecycle',public.get_effective_waitlist_participant_lifecycle_internal(id)) ORDER BY registered_at,id),'[]')
   FROM eshop.order_participants WHERE current_order_id=oid),
  'slots',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'participantId',participant_id,'outcome',CASE WHEN outcome='pending' AND w.expires_at<=clock_timestamp() THEN 'expired' ELSE outcome END)),'[]')
   FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id),'waitlistSummary',public.get_waitlist_summary_internal(oid));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',403,'errorCode','INVALID_CAPABILITY');
END $$;
REVOKE ALL ON FUNCTION public.check_waitlist_scope_internal(bigint,uuid,text,uuid,text),public.get_waitlist_summary_internal(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_form(text,uuid,bigint) TO anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_waitlist_order_detail(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 IF NOT public.get_is_editor_order_view_on_occasion(o.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Order viewer required'; END IF;
 RETURN jsonb_build_object('orderId',o.id,'sourceOrderId',o.source_waitlist_order_id,'waitlistSummary',public.get_waitlist_summary_internal(o.id),
 'capacity',public.get_form_capacity_snapshot_internal(o.form),
 'participants',(SELECT coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('answers',public.extract_participant_answers_internal(o.form,p.answers),
  'lifecycle',public.get_effective_waitlist_participant_lifecycle_internal(p.id)) ORDER BY registered_at,id),'[]') FROM eshop.order_participants p WHERE current_order_id=o.id),
 'offers',(SELECT coalesce(jsonb_agg(to_jsonb(w)||jsonb_build_object('slots',(SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]') FROM eshop.waitlist_offer_slots s WHERE offer_id=w.id)) ORDER BY created_at),'[]')
 FROM eshop.waitlist_offers w WHERE order_id=o.id),
 'linkedOrders',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'orderSymbol',order_symbol,'state',state)),'[]') FROM eshop.orders WHERE source_waitlist_order_id=o.id));
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_order_detail(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_order_detail(bigint) TO authenticated;


-- Source: database/functions/eshop_waitlist/offers.sql
DROP FUNCTION IF EXISTS public.expire_waitlist_form_internal(bigint,timestamptz);
CREATE OR REPLACE FUNCTION public.expire_waitlist_form_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp(),p_limit integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE n integer;
BEGIN
 PERFORM 1 FROM public.forms WHERE id=p_form FOR UPDATE;
 WITH expired AS (UPDATE eshop.waitlist_offer_slots s SET outcome='expired',updated_at=p_at
 FROM eshop.waitlist_offers w WHERE w.id=s.offer_id AND w.form_id=p_form AND w.expires_at<=p_at AND s.outcome='pending'
 AND s.id IN(SELECT x.id FROM eshop.waitlist_offer_slots x JOIN eshop.waitlist_offers y ON y.id=x.offer_id WHERE y.form_id=p_form AND y.expires_at<=p_at AND x.outcome='pending' ORDER BY x.id LIMIT p_limit)
 RETURNING s.participant_id)
 UPDATE eshop.order_participants SET lifecycle='offer_expired',queue_at=p_at,updated_at=p_at WHERE id IN(SELECT participant_id FROM expired);
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n>0 THEN
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=p_form;
  UPDATE eshop.waitlist_capabilities SET revoked_at=p_at WHERE form_id=p_form AND kind='offer' AND expires_at<=p_at AND revoked_at IS NULL;
 END IF;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_proposal(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; proposals jsonb; available integer;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 PERFORM 1 FROM public.forms WHERE id=f.id FOR UPDATE;
 PERFORM public.expire_waitlist_form_internal(f.id);
 c:=public.get_form_capacity_snapshot_internal(f.id); available:=(c->>'offerablePlaces')::integer;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',current_order_id,'count',offered,'waitingCount',total) ORDER BY first_queue,current_order_id),'[]') INTO proposals
 FROM (SELECT current_order_id,min(queue_at) first_queue,count(*) total,
  count(*) FILTER(WHERE position<=available) offered FROM
  (SELECT p.*,row_number() OVER(ORDER BY queue_at,registered_at,id) position FROM eshop.order_participants p
   WHERE form_id=f.id AND lifecycle='waiting') ranked GROUP BY current_order_id) grouped WHERE offered>0;
 RETURN jsonb_build_object('code',200,'formId',f.id,'revision',c->'revision','capacity',c,'recipients',proposals,
 'offerDurationSeconds',f.waitlist_offer_duration_seconds,'serverTime',clock_timestamp());
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_waitlist_email_internal(p_order bigint,p_offer uuid,p_command uuid,p_delivery jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; occ public.occasions; result jsonb; expiry timestamptz; code text; kind text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order; SELECT * INTO STRICT occ FROM public.occasions WHERE id=o.occasion;
 code:=CASE WHEN p_offer IS NULL THEN 'waitlist_confirmation' ELSE 'waitlist_offer' END;
 kind:=code;
 IF p_delivery->>'recipient' IS DISTINCT FROM o.data->>'email' OR p_delivery->>'templateCode' IS DISTINCT FROM code
 OR p_delivery->'sealed' IS NULL OR p_delivery->>'tokenHash' !~ '^[0-9a-f]{64}$'
 OR p_delivery->>'contentHash' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid waitlist delivery binding'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=p_offer AND order_id=p_order;
 INSERT INTO eshop.waitlist_capabilities(token_hash,organization_id,form_id,order_id,offer_id,kind,expires_at)
 VALUES(p_delivery->>'tokenHash',occ.organization,o.form,o.id,p_offer,CASE WHEN p_offer IS NULL THEN 'manage' ELSE 'offer' END,expiry);
 result:=public.enqueue_email(kind,jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit),o.data->>'email',
 jsonb_build_object('order_id',o.id,'offer_id',p_offer,'command_id',p_command,'content_hash',p_delivery->>'contentHash','waitlistEnvelope',p_delivery->'sealed'),
 p_command::text||':'||o.id::text,code,now(),expiry,o.id,NULL);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.expire_waitlist_form_internal(bigint,timestamptz,integer),public.enqueue_waitlist_email_internal(bigint,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_proposal(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_proposal(bigint) TO authenticated;


-- Source: database/functions/eshop_waitlist/accept_offer.sql
CREATE OR REPLACE FUNCTION public.validate_waitlist_answers_internal(p_form bigint,p_input jsonb,p_people jsonb,p_waitlist boolean)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.form_fields; person jsonb; values jsonb; k text; max_people integer;
BEGIN
 IF jsonb_typeof(p_people)<>'array' OR jsonb_array_length(p_people)<1 OR jsonb_array_length(p_people)>public.ticket_order_limit() THEN
  RAISE EXCEPTION 'Invalid participant count'; END IF;
 SELECT min((data->>'max_tickets')::integer) INTO max_people FROM public.form_fields WHERE form=p_form AND type='ticket';
 IF jsonb_array_length(p_people)>coalesce(max_people,public.ticket_order_limit()) THEN RAISE EXCEPTION 'Maximum participants exceeded'; END IF;
 FOR f IN SELECT * FROM public.form_fields WHERE form=p_form AND is_required AND NOT is_hidden
 AND type NOT IN ('ticket','html','product_type') AND (NOT p_waitlist OR product_type IS NULL) LOOP
  k:=f.id::text;
  IF f.is_ticket_field THEN
   FOR person IN SELECT * FROM jsonb_array_elements(p_people) LOOP
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(person->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
     RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
   END LOOP;
  ELSE
   IF nullif(p_input->>f.type,'') IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(p_input->'fields','[]')) answer WHERE answer ? k AND nullif(answer->>k,'') IS NOT NULL) THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','REQUIRED_FIELD_MISSING','fieldId',f.id)::text; END IF;
  END IF;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.accept_waitlist_offer_internal(p_payload jsonb,p_command uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE w eshop.waitlist_offers; o eshop.orders; fid bigint; target bigint; ids uuid[]; selected_slots uuid[];
 n integer; remaining integer; result jsonb; input jsonb; old_people jsonb; old_slots jsonb; conversion text; ticket jsonb; position integer;
 original_group jsonb; remaining_group jsonb; accepted_group jsonb; history_snapshot jsonb;
BEGIN
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=(p_payload->>'offerId')::uuid;
 fid:=public.check_waitlist_scope_internal(w.order_id,w.id,p_payload->>'token',p_actor,'accept');
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[w.order_id]);
 SELECT * INTO STRICT w FROM eshop.waitlist_offers WHERE id=w.id FOR UPDATE;
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=w.order_id;
 PERFORM public.expire_waitlist_form_internal(fid);
 IF w.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
 IF o.state<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 SELECT array_agg(x::uuid) INTO ids FROM jsonb_array_elements_text(p_payload->'personIds') x;
 n:=coalesce(cardinality(ids),0);
 IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(ids) x) THEN RAISE EXCEPTION 'Invalid selected persons'; END IF;
 PERFORM 1 FROM eshop.order_participants WHERE current_order_id=o.id ORDER BY id FOR UPDATE;
 original_group:=public.snapshot_waitlist_participants_internal(o.id);
 IF n<>(SELECT count(*) FROM eshop.order_participants p WHERE p.id=ANY(ids) AND current_order_id=o.id
 AND lifecycle IN ('waiting','offered','offer_expired','offer_declined','offer_cancelled')
 AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.participant_id=p.id AND s.outcome='pending' AND s.offer_id<>w.id)) THEN
  RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 -- Preserve slots already attached to selected people, then exchange only the necessary unused bindings.
 SELECT array_agg(id ORDER BY CASE WHEN participant_id=ANY(ids) THEN 0 ELSE 1 END,id) INTO selected_slots
 FROM (SELECT * FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending'
 ORDER BY CASE WHEN participant_id=ANY(ids) THEN 0 ELSE 1 END,id LIMIT n FOR UPDATE) s;
 IF coalesce(cardinality(selected_slots),0)<>n THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
 -- Journal the exact pre-swap bindings, including displaced offered people.
 SELECT jsonb_agg(to_jsonb(p)) INTO old_people FROM eshop.order_participants p
 WHERE id=ANY(ids) OR id IN(SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots));
 SELECT jsonb_agg(to_jsonb(s)) INTO old_slots FROM eshop.waitlist_offer_slots s WHERE id=ANY(selected_slots);
 -- Release temporary bindings using a terminal outcome so the pending uniqueness invariant never needs deferral.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(selected_slots);
 UPDATE eshop.order_participants SET lifecycle='waiting' WHERE id IN(SELECT participant_id FROM eshop.waitlist_offer_slots WHERE id=ANY(selected_slots)) AND NOT id=ANY(ids);
 WITH persons AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(ids) id), slots AS(SELECT id,row_number() OVER(ORDER BY id) n FROM unnest(selected_slots) id)
 UPDATE eshop.waitlist_offer_slots s SET participant_id=p.id FROM persons p JOIN slots x USING(n) WHERE s.id=x.id;
 SELECT count(*) INTO remaining FROM eshop.order_participants WHERE current_order_id=o.id;
 conversion:=CASE WHEN remaining=n THEN 'in_place' ELSE 'split' END;
 target:=CASE WHEN conversion='in_place' THEN o.id ELSE public.allocate_ticket_order_identity_internal(fid) END;
 IF conversion='split' THEN UPDATE eshop.orders SET source_waitlist_order_id=o.id WHERE id=target; END IF;
 input:=p_payload->'orderDetails';
 input:=jsonb_set(input,'{ticket}',public.normalize_form_participant_answers_internal(fid,input->'ticket'));
 IF (input->>'form')::uuid IS DISTINCT FROM (SELECT key FROM public.forms WHERE id=fid) THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF jsonb_array_length(input->'ticket')<>n THEN RAISE EXCEPTION 'Selected people and tickets differ'; END IF;
 -- Each selected person must explicitly bind their stable ID to their submitted ticket.
 IF n<>(SELECT count(DISTINCT (t->>'participantId')::uuid) FROM jsonb_array_elements(input->'ticket') t WHERE (t->>'participantId')::uuid=ANY(ids)) THEN
  RAISE EXCEPTION 'Invalid participant ticket binding'; END IF;
 PERFORM public.validate_waitlist_answers_internal(fid,input,input->'ticket',false);
 result:=public.finalize_ticket_order_internal_v1(target,input,true);
 IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
 position:=0;
 FOR ticket IN SELECT * FROM jsonb_array_elements(input->'ticket') LOOP
  UPDATE eshop.order_participants SET current_order_id=target,lifecycle='admitted',
   ticket_id=(result#>>ARRAY['order','data','tickets',position::text,'id'])::bigint,
   answers=public.extract_participant_answers_internal(fid,ticket),updated_at=clock_timestamp()
  WHERE id=(ticket->>'participantId')::uuid;
  position:=position+1;
 END LOOP;
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted',resulting_order_id=target,updated_at=clock_timestamp() WHERE id=ANY(selected_slots);
 PERFORM public.enqueue_ticket_order_confirmation_v1(p_command,o.occasion,result,input->>'lang');
 IF (SELECT state='preparing_payment' FROM eshop.orders WHERE id=target) THEN
  INSERT INTO eshop.waitlist_acceptance_attempts(command_id,source_order_id,target_order_id,offer_id,conversion,participant_ids,slot_ids,previous_order_data,previous_participants,previous_slots)
  VALUES(p_command,o.id,target,w.id,conversion,ids,selected_slots,to_jsonb(o),old_people,old_slots);
 ELSE
  UPDATE eshop.waitlist_capabilities SET revoked_at=clock_timestamp() WHERE offer_id=w.id
   AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=w.id AND outcome='pending');
 END IF;
 remaining_group:=CASE WHEN conversion='split' THEN public.snapshot_waitlist_participants_internal(o.id) ELSE '[]'::jsonb END;
 accepted_group:=public.snapshot_waitlist_participants_internal(target);
 history_snapshot:=jsonb_build_object('action','waitlist_accept','commandId',p_command,'sourceOrderId',o.id,
  'targetOrderId',target,'personIds',ids,'conversion',conversion,'participantsBefore',original_group,
  'participantsAfter',remaining_group,'acceptedParticipants',accepted_group);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(o.id,(SELECT state FROM eshop.orders WHERE id=o.id),history_snapshot);
 IF conversion='split' THEN
  INSERT INTO eshop.orders_history("order",state,data) VALUES(target,(SELECT state FROM eshop.orders WHERE id=target),history_snapshot);
 END IF;
 RETURN result||jsonb_build_object('sourceOrderId',o.id,'conversion',conversion,'waitlistSummary',public.get_waitlist_summary_internal(o.id));
END $$;
REVOKE ALL ON FUNCTION public.validate_waitlist_answers_internal(bigint,jsonb,jsonb,boolean),public.accept_waitlist_offer_internal(jsonb,uuid,uuid) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_waitlist/commands.sql
-- Edge is the trusted preparation boundary for random capabilities and sealed email.
-- It verifies the bearer user; SQL still checks the explicit actor's occasion rights.
CREATE OR REPLACE FUNCTION public.sanitize_waitlist_history_internal(p_value jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(key,public.sanitize_waitlist_history_internal(value)),'{}') INTO result
  FROM jsonb_each(p_value) WHERE lower(key) NOT IN
   ('token','secret','password','offertoken','managetoken','capability','waitlistenvelope','sealed','tokenhash');
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(value) ORDER BY ordinal),'[]') INTO result
  FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,ordinal);
  RETURN result;
 END IF;
 RETURN p_value;
END $$;
CREATE OR REPLACE FUNCTION public.snapshot_waitlist_participants_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(public.sanitize_waitlist_history_internal(to_jsonb(p)) ORDER BY registered_at,id),'[]')
 FROM eshop.order_participants p WHERE current_order_id=p_order;
$$;
REVOKE ALL ON FUNCTION public.sanitize_waitlist_history_internal(jsonb),public.snapshot_waitlist_participants_internal(bigint)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.execute_waitlist_command_client_sync_v1(
 p_operation text,p_payload jsonb,p_command_id uuid,p_client_id uuid,p_actor uuid DEFAULT NULL,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; occ bigint; oid bigint; offer uuid; mode text; c jsonb; result jsonb; claim jsonb;
 hash text; selected uuid[]; expected integer; changed integer; recipients jsonb; r jsonb; delivery jsonb;
 person jsonb; slot_ids uuid[]; expiry timestamptz; f public.forms; people jsonb; n integer; before_users uuid[];
 previous_sub text; actor_kind text; o eshop.orders; entity_changes jsonb:='[]';
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation NOT IN ('register','send','accept','decline','cancel','withdraw') OR p_command_id IS NULL OR p_client_id IS NULL
 OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4194304 THEN RAISE EXCEPTION 'Invalid waitlist command'; END IF;
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSIF p_operation='withdraw' THEN oid:=(p_payload->>'orderId')::bigint; SELECT form INTO fid FROM eshop.orders WHERE id=oid;
 ELSE offer:=(p_payload->>'offerId')::uuid; SELECT order_id,form_id INTO oid,fid FROM eshop.waitlist_offers WHERE id=offer; END IF;
 SELECT * INTO f FROM public.forms WHERE id=fid; occ:=f.occasion;
 IF occ IS NULL THEN RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
 IF p_operation IN ('send','cancel') AND NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 previous_sub:=current_setting('request.jwt.claim.sub',true);
 PERFORM set_config('request.jwt.claim.sub',coalesce(p_actor::text,''),true);
 hash:=encode(extensions.digest(jsonb_build_object('operation',p_operation,'payload',p_payload,'actor',p_actor)::text,'sha256'),'hex');
 BEGIN
  IF p_actor IS NULL THEN claim:=public.begin_anonymous_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_client_id,hash); actor_kind:='unknown';
  ELSE claim:=public.begin_client_mutation_v1(p_command_id,'inventory.waitlist.'||p_operation,occ,p_actor,hash); actor_kind:='user'; END IF;
 EXCEPTION WHEN invalid_parameter_value THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
  RETURN jsonb_build_object('code',409,'errorCode','COMMAND_PAYLOAD_CONFLICT');
 END;
 IF claim->>'disposition'='replay' THEN
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN claim->'response'; END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO before_users FROM public.occasion_users WHERE occasion=occ;
 BEGIN
  PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 IF p_operation IN ('accept','decline','cancel','withdraw') THEN
  PERFORM public.check_waitlist_scope_internal(oid,offer,p_payload->>'token',p_actor,p_operation); END IF;

  PERFORM public.expire_waitlist_form_internal(fid);
  c:=public.get_form_capacity_snapshot_internal(fid);
  IF p_operation='register' THEN
   mode:=public.get_form_registration_mode_internal(fid);
   IF mode<>'waitlist' THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   people:=public.normalize_form_participant_answers_internal(fid,p_payload->'people');
   PERFORM public.validate_waitlist_answers_internal(fid,p_payload,people,true);
   IF nullif(p_payload->>'email','') IS NULL THEN RAISE EXCEPTION 'Email required'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(people) p CROSS JOIN LATERAL jsonb_array_elements(coalesce(p->'fields','[]')) a WHERE a ? 'product_type') THEN
    RAISE EXCEPTION 'Waitlist does not accept products'; END IF;
   oid:=public.allocate_ticket_order_identity_internal(fid);
   UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=p_payload-'people'-'token' WHERE id=oid;
   FOR person IN SELECT * FROM jsonb_array_elements(people) LOOP
    INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,answers,lifecycle)
     VALUES(oid,oid,fid,public.extract_participant_answers_internal(fid,person),'waiting'); END LOOP;
   result:=jsonb_build_object('code',200,'order',jsonb_build_object('id',oid,'order_symbol',(SELECT order_symbol FROM eshop.orders WHERE id=oid),'state','waitlisted','payment_info',NULL,'price',NULL),
    'waitlistSummary',public.get_waitlist_summary_internal(oid),'email',public.enqueue_waitlist_email_internal(oid,NULL,p_command_id,p_deliveries->0));
  ELSIF p_operation='send' THEN
   SELECT * INTO f FROM public.forms WHERE id=fid;
   IF NOT f.waitlist_enabled THEN RAISE EXCEPTION 'WAITLIST_NOT_AVAILABLE'; END IF;
   IF f.capacity_revision<>(p_payload->>'revision')::bigint THEN
    RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','OFFER_CHANGED','capacity',c)::text; END IF;
   expiry:=(p_payload->>'expiresAt')::timestamptz;
   IF expiry IS NULL OR expiry<=clock_timestamp() THEN RAISE EXCEPTION 'OFFER_EXPIRED'; END IF;
   recipients:=p_payload->'recipients';
   IF jsonb_typeof(recipients)<>'array' OR jsonb_array_length(recipients)<1 OR
    jsonb_array_length(recipients)<>(SELECT count(DISTINCT x->>'orderId') FROM jsonb_array_elements(recipients) x) THEN RAISE EXCEPTION 'Invalid recipients'; END IF;
   SELECT sum((x->>'count')::integer) INTO n FROM jsonb_array_elements(recipients) x;
   IF n>(c->>'offerablePlaces')::integer THEN RAISE EXCEPTION 'FORM_CAPACITY_EXCEEDED'; END IF;
   PERFORM 1 FROM eshop.orders WHERE id IN(SELECT (x->>'orderId')::bigint FROM jsonb_array_elements(recipients) x) ORDER BY id FOR UPDATE;
   result:=jsonb_build_object('code',200,'offers','[]'::jsonb);
   FOR r IN SELECT * FROM jsonb_array_elements(recipients) ORDER BY (value->>'orderId')::bigint LOOP
    oid:=(r->>'orderId')::bigint; n:=(r->>'count')::integer;
    IF n<1 OR NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=fid AND state='waitlisted') THEN RAISE EXCEPTION 'Invalid recipient scope'; END IF;
    SELECT array_agg(id) INTO selected FROM (SELECT p.id FROM eshop.order_participants p WHERE current_order_id=oid
     AND lifecycle IN ('waiting','offer_expired','offer_declined','offer_cancelled') AND NOT EXISTS
     (SELECT 1 FROM eshop.waitlist_offer_slots s WHERE participant_id=p.id AND outcome='pending')
     ORDER BY queue_at,registered_at,id LIMIT n FOR UPDATE) persons;
    IF coalesce(cardinality(selected),0)<>n THEN RAISE EXCEPTION 'OFFER_CHANGED'; END IF;
    INSERT INTO eshop.waitlist_offers(order_id,form_id,created_by,expires_at,revision) VALUES(oid,fid,p_actor,expiry,f.capacity_revision) RETURNING id INTO offer;
    INSERT INTO eshop.waitlist_offer_slots(offer_id,participant_id,form_id) SELECT offer,id,fid FROM unnest(selected) id;
    UPDATE eshop.order_participants SET lifecycle='offered',updated_at=clock_timestamp() WHERE id=ANY(selected);
    SELECT x INTO delivery FROM jsonb_array_elements(p_deliveries) x WHERE (x->>'orderId')::bigint=oid;
    result:=jsonb_set(result,'{offers}',result->'offers'||jsonb_build_array(jsonb_build_object('orderId',oid,'offerId',offer,'count',n,'expiresAt',expiry,
     'email',public.enqueue_waitlist_email_internal(oid,offer,p_command_id,delivery))));
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,'waitlisted',jsonb_build_object('action','offer_sent','offerId',offer,'count',n,'expiresAt',expiry));
    entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist offer','changedFields',jsonb_build_array('waitlistSummary')));
   END LOOP;
  ELSIF p_operation='accept' THEN
   result:=public.accept_waitlist_offer_internal(p_payload,p_command_id,p_actor);
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','update','safeLabel','Accepted order','changedFields',jsonb_build_array('state','tickets','products','allocations')));
  ELSE
   PERFORM public.lock_order_capacity_scope_internal(ARRAY[oid]);
   IF (SELECT state FROM eshop.orders WHERE id=oid)<>'waitlisted' THEN RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   SELECT array_agg(x::uuid) INTO selected FROM jsonb_array_elements_text(p_payload->'personIds') x; n:=coalesce(cardinality(selected),0);
   IF n<1 OR n<>(SELECT count(DISTINCT x) FROM unnest(selected) x) THEN RAISE EXCEPTION 'Invalid persons'; END IF;
   IF n<>(SELECT count(*) FROM eshop.order_participants WHERE id=ANY(selected) AND current_order_id=oid AND lifecycle IN ('waiting','offered','offer_expired','offer_declined','offer_cancelled')) THEN
    RAISE EXCEPTION 'INVALID_CAPABILITY'; END IF;
   IF p_operation IN ('decline','cancel') AND n<>(SELECT count(*) FROM eshop.waitlist_offer_slots WHERE offer_id=offer AND outcome='pending' AND participant_id=ANY(selected)) THEN
    RAISE EXCEPTION 'OFFER_SLOT_ALREADY_RESOLVED'; END IF;
   UPDATE eshop.waitlist_offer_slots SET outcome=CASE WHEN p_operation='decline' THEN 'declined' ELSE 'cancelled' END,updated_at=clock_timestamp()
    WHERE participant_id=ANY(selected) AND outcome='pending' AND (p_operation='withdraw' OR offer_id=offer);
   UPDATE eshop.order_participants SET lifecycle=CASE p_operation WHEN 'decline' THEN 'offer_declined' WHEN 'cancel' THEN 'offer_cancelled' ELSE 'withdrawn' END,
    queue_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=ANY(selected);
   UPDATE eshop.waitlist_capabilities cap SET revoked_at=clock_timestamp() WHERE cap.order_id=oid AND kind='offer' AND NOT EXISTS
    (SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=cap.offer_id AND outcome='pending');
   result:=jsonb_build_object('code',200,'orderId',oid,'waitlistSummary',public.get_waitlist_summary_internal(oid));
  END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=fid;
  IF p_operation<>'send' THEN
   -- Acceptance owns its richer before/after snapshot at the same transaction
   -- boundary; avoid a second action-only row hiding that record in the detail.
   IF p_operation<>'accept' THEN
    INSERT INTO eshop.orders_history("order",state,data) VALUES(oid,(SELECT state FROM eshop.orders WHERE id=oid),
     jsonb_build_object('action','waitlist_'||p_operation,'commandId',p_command_id,
     'personIds',CASE WHEN p_operation='register' THEN
       (SELECT jsonb_agg(id ORDER BY registered_at,id) FROM eshop.order_participants WHERE current_order_id=oid)
       ELSE to_jsonb(selected) END,
     'participants',public.snapshot_waitlist_participants_internal(oid)));
   END IF;
   entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','order','entityId',oid,'operation','update','safeLabel','Waitlist order','changedFields',jsonb_build_array('waitlistSummary','participants')));
  END IF;
  result:=result||jsonb_build_object('capacity',public.get_form_capacity_snapshot_internal(fid));
 EXCEPTION WHEN OTHERS THEN
  result:=CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',409,'errorCode',SQLERRM,'message',SQLERRM) END;
  result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
   CASE WHEN (result->>'code')::integer BETWEEN 200 AND 599 THEN (result->>'code')::integer ELSE 409 END,result);
  PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RETURN result;
 END;
 entity_changes:=entity_changes||jsonb_build_array(jsonb_build_object('entityType','form','entityId',fid,'operation','update','safeLabel','Form capacity','changedFields',jsonb_build_array('capacity','registrationMode')));
 result:=public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.waitlist.'||p_operation,entity_changes,before_users,result,actor_kind);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_waitlist_command_client_sync_v1(text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;


-- Source: database/functions/eshop_waitlist/email_context.sql
CREATE OR REPLACE FUNCTION public.get_waitlist_email_context_v1(p_operation text,p_payload jsonb,p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE fid bigint; f public.forms; occ public.occasions; contexts jsonb; r jsonb; o eshop.orders;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_operation='register' THEN SELECT id INTO fid FROM public.forms WHERE key=(p_payload->>'form')::uuid;
 ELSIF p_operation='send' THEN fid:=(p_payload->>'formId')::bigint;
 ELSE RAISE EXCEPTION 'Invalid email context operation'; END IF;
 SELECT * INTO STRICT f FROM public.forms WHERE id=fid; SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 IF p_operation='send' AND NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=occ.id AND "user"=p_actor AND is_editor_order) THEN
  RAISE insufficient_privilege USING MESSAGE='Order editor required'; END IF;
 contexts:='[]';
 IF p_operation='register' THEN contexts:=jsonb_build_array(jsonb_build_object('recipient',p_payload->>'email','organization',occ.organization,
  'occasion',occ.id,'unit',occ.unit,'occasionTitle',occ.title,'participantCount',jsonb_array_length(p_payload->'people'),'formLink',f.link));
 ELSE
  FOR r IN SELECT * FROM jsonb_array_elements(p_payload->'recipients') LOOP
   SELECT * INTO STRICT o FROM eshop.orders WHERE id=(r->>'orderId')::bigint AND form=fid;
   contexts:=contexts||jsonb_build_array(jsonb_build_object('orderId',o.id,'recipient',o.data->>'email','organization',occ.organization,
   'occasion',occ.id,'unit',occ.unit,'occasionTitle',occ.title,'orderSymbol',o.order_symbol,
   'participantCount',(SELECT count(*) FROM eshop.order_participants WHERE current_order_id=o.id),
   'offeredCount',(r->>'count')::integer,'formLink',f.link,'expiresAt',p_payload->>'expiresAt'));
  END LOOP;
 END IF;
 RETURN contexts;
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_context_v1(text,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_context_v1(text,jsonb,uuid) TO service_role;


-- Source: database/functions/eshop_waitlist/email_render_context.sql
-- Private queue renderer boundary. Personal capabilities remain encrypted in
-- existing queue sources; the renderer receives only their hashes and envelopes.
CREATE OR REPLACE FUNCTION public.get_waitlist_email_render_context_v1(
 p_order_id bigint,p_offer_id uuid DEFAULT NULL,p_recipient text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE o eshop.orders; f public.forms; occ public.occasions; org public.organizations;
 manage_message public.email_messages; manage_cap eshop.waitlist_capabilities;
 source_cap eshop.waitlist_capabilities; v_recipient text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 SELECT * INTO o FROM eshop.orders WHERE id=p_order_id;
 SELECT * INTO f FROM public.forms WHERE id=o.form;
 SELECT * INTO occ FROM public.occasions WHERE id=o.occasion;
 SELECT * INTO org FROM public.organizations WHERE id=occ.organization;
 IF o.id IS NULL OR f.id IS NULL OR f.occasion<>occ.id OR o.state<>'waitlisted'
 OR (p_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers
  WHERE id=p_offer_id AND order_id=o.id AND form_id=f.id AND expires_at>clock_timestamp()
  AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots WHERE offer_id=p_offer_id AND outcome='pending'))) THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 v_recipient:=coalesce(p_recipient,o.data->>'email');
 SELECT * INTO manage_message FROM public.email_messages m
 WHERE m.order_id=o.id AND m.message_kind='waitlist_confirmation'
 AND m.recipient=v_recipient
 AND m.data ? 'waitlistEnvelope' ORDER BY m.id LIMIT 1;
 SELECT * INTO manage_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id
 AND kind='manage' AND revoked_at IS NULL;
 SELECT * INTO source_cap FROM eshop.waitlist_capabilities
 WHERE order_id=o.id AND form_id=f.id AND organization_id=org.id AND revoked_at IS NULL
 AND CASE WHEN p_offer_id IS NULL THEN kind='manage'
  ELSE kind='offer' AND offer_id=p_offer_id AND expires_at>clock_timestamp() END;
 IF manage_message.id IS NULL OR manage_cap.token_hash IS NULL OR source_cap.token_hash IS NULL THEN
  RAISE EXCEPTION 'waitlist_email_source_invalid';
 END IF;
 RETURN jsonb_build_object('orderId',o.id,'orderSymbol',o.order_symbol,
  'organization',org.id,'occasion',occ.id,'unit',occ.unit,'formLink',f.link,
  'webLink',org.data->>'DEFAULT_URL','replyTo',public.get_reply_to_email_for_order(o.id),
  'participantCount',(SELECT count(*) FROM eshop.order_participants WHERE current_order_id=o.id),
  'offeredCount',(SELECT count(*) FROM eshop.waitlist_offer_slots
    WHERE offer_id=p_offer_id AND outcome='pending'),
  'expiresAt',(SELECT expires_at FROM eshop.waitlist_offers WHERE id=p_offer_id),
  'tokenHash',source_cap.token_hash,'manageTokenHash',manage_cap.token_hash,
  'manageEnvelope',manage_message.data->'waitlistEnvelope',
  'manageContentHash',manage_message.data->>'content_hash');
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_waitlist_email_render_context_v1(bigint,uuid,text)
 TO service_role;


-- Source: database/functions/eshop_waitlist/email_templates.sql
-- Global defaults participate in the existing occasion/unit/organization
-- inheritance. Never overwrite an editor's custom content.
INSERT INTO public.email_templates(code,subject,html)
SELECT v.code,v.subject,v.html FROM (VALUES
 ('waitlist_confirmation','Potvrzení zařazení mezi náhradníky - {{occasion_title}}',
  '<h2>Jste v pořadníku náhradníků</h2><p>Potvrzujeme přihlášení na {{occasion_title}}. Číslo přihlášky: <strong>{{order_symbol}}</strong>. Počet osob: {{participant_count}}.</p><p>Zatím nic neplatíte a nevybíráte produkty. Pokud se uvolní místa, pošleme vám nabídku.</p><p>{{manage_waitlist_button}}</p><p>Vlastní čekání můžete ukončit jednotlivě. Tento odkaz neslouží ke stornu již potvrzené objednávky.</p>'),
 ('waitlist_offer','Nabídka {{offered_count}} míst - {{occasion_title}}',
  '<h2>Máme pro vás volná místa</h2><p>Pro přihlášku <strong>{{order_symbol}}</strong> na {{occasion_title}} nabízíme {{offered_count}} míst z celkových {{participant_count}} osob. Platnost nabídky: {{offer_expires_at}} (UTC).</p><p>Po otevření nabídky vyberete osoby a produkty a objednávku výslovně potvrdíte. Produkty nejsou rezervované; vybíráte je podle aktuální dostupnosti. Samotné otevření odkazu nic nepotvrzuje.</p><p>{{offer_button}}</p><p>Nepřijatá místa zůstávají do konce platnosti nabídky k dispozici. Čekání lze spravovat zde:</p><p>{{manage_waitlist_button}}</p>')
) v(code,subject,html)
WHERE NOT EXISTS (SELECT 1 FROM public.email_templates t WHERE t.code=v.code
 AND t.organization IS NULL AND t.unit IS NULL AND t.occasion IS NULL);


-- Source: database/functions/eshop_waitlist/email_preview.sql
-- An editor preview resolves the same inherited template/wrapper as delivery.
-- It never creates a capability, offer, intent, or reservation.
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_email_preview(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE f public.forms; occ public.occasions; resolved jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 resolved:=public.get_email_template_and_wrapper('waitlist_offer',
  jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit));
 RETURN resolved||jsonb_build_object('code',200,'occasionTitle',occ.title,'formLink',f.link);
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_email_preview(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_email_preview(bigint) TO authenticated;


-- Source: database/functions/eshop_waitlist/fakturoid_recovery.sql
CREATE OR REPLACE FUNCTION public.abort_waitlist_acceptance_internal(p_order bigint,p_command uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE a eshop.waitlist_acceptance_attempts; previous jsonb; s jsonb; p jsonb; expiry timestamptz; ticket_ids bigint[];
 original_person eshop.order_participants; restored_outcome text; original_id uuid;
BEGIN
 SELECT * INTO a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command AND target_order_id=p_order;
 IF a.command_id IS NULL THEN RETURN false; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.source_order_id,a.target_order_id]);
 SELECT * INTO STRICT a FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command FOR UPDATE;
 IF a.state='aborted' THEN RETURN true; END IF;
 IF a.state<>'preparing' THEN RAISE EXCEPTION 'Acceptance attempt already completed'; END IF;
 SELECT expires_at INTO expiry FROM eshop.waitlist_offers WHERE id=a.offer_id FOR UPDATE;
 SELECT array_agg(ticket_id) INTO ticket_ids FROM eshop.order_participants WHERE id=ANY(a.participant_ids);
 PERFORM public.cancel_order_email_intents(p_order);
 PERFORM public.internal_storno_tickets_221(ticket_ids);
 -- The failed ticket records remain historical; detach them from the reusable identity.
 DELETE FROM eshop.order_product_ticket WHERE "order"=a.target_order_id AND ticket=ANY(ticket_ids);
 IF a.conversion='in_place' THEN
  UPDATE eshop.orders SET state='waitlisted',price=NULL,payment_info=NULL,data=a.previous_order_data->'data',updated_at=clock_timestamp()
   WHERE id=a.target_order_id;
 ELSE
  UPDATE eshop.orders SET state='storno',price=0,payment_info=NULL,updated_at=clock_timestamp() WHERE id=a.target_order_id;
 END IF;
 -- Selected people are fenced by the preparing target. Displaced offered people
 -- remain in the source and may legitimately withdraw or receive another offer.
 -- Restore their offer lifecycle below without overwriting their current answers.
 FOR p IN SELECT * FROM jsonb_array_elements(a.previous_participants) LOOP
  IF NOT (p->>'id')::uuid=ANY(a.participant_ids) THEN CONTINUE; END IF;
  UPDATE eshop.order_participants SET current_order_id=(p->>'current_order_id')::bigint,
   lifecycle=p->>'lifecycle',answers=p->'answers',ticket_id=(p->>'ticket_id')::bigint,
   queue_at=(p->>'queue_at')::timestamptz,updated_at=clock_timestamp() WHERE id=(p->>'id')::uuid;
 END LOOP;
 -- Release all consumed bindings first: full acceptance can permute participant
 -- IDs between slots, and immediate pending uniqueness must hold throughout.
 UPDATE eshop.waitlist_offer_slots SET outcome='accepted' WHERE id=ANY(a.slot_ids);
 FOR s IN SELECT * FROM jsonb_array_elements(a.previous_slots) LOOP
  original_id:=(s->>'participant_id')::uuid;
  SELECT * INTO STRICT original_person FROM eshop.order_participants WHERE id=original_id FOR UPDATE;
  restored_outcome:=CASE
   WHEN original_person.lifecycle IN ('withdrawn','cancelled') OR original_person.current_order_id<>a.source_order_id
     OR EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots other WHERE other.participant_id=original_id
       AND other.outcome='pending' AND NOT other.id=ANY(a.slot_ids)) THEN 'cancelled'
   WHEN original_person.lifecycle='offer_declined' THEN 'declined'
   WHEN original_person.lifecycle='offer_cancelled' THEN 'cancelled'
   WHEN expiry<=clock_timestamp() OR original_person.lifecycle='offer_expired' THEN 'expired'
   ELSE 'pending' END;
  UPDATE eshop.waitlist_offer_slots SET participant_id=original_id,
   outcome=restored_outcome,resulting_order_id=NULL,updated_at=clock_timestamp()
  WHERE id=(s->>'id')::uuid;
  IF restored_outcome IN ('pending','expired') AND original_person.lifecycle IN ('waiting','offered','offer_expired') THEN
   UPDATE eshop.order_participants SET lifecycle=CASE WHEN restored_outcome='pending' THEN 'offered' ELSE 'offer_expired' END,
    queue_at=CASE WHEN restored_outcome='pending' THEN queue_at ELSE clock_timestamp() END,updated_at=clock_timestamp()
   WHERE id=original_id;
  END IF;
 END LOOP;
 UPDATE eshop.waitlist_acceptance_attempts SET state='aborted',updated_at=clock_timestamp() WHERE command_id=p_command;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=(SELECT form FROM eshop.orders WHERE id=a.source_order_id);
 INSERT INTO eshop.orders_history("order",state,data) VALUES(a.source_order_id,'waitlisted',
  jsonb_build_object('action','acceptance_aborted','commandId',p_command,'targetOrderId',a.target_order_id));
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.expire_waitlist_offers(p_batch_size integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; affected integer:=0; n integer; occ bigint; impacts jsonb;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_batch_size NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Invalid expiry batch'; END IF;
 FOR f IN SELECT DISTINCT form_id FROM eshop.waitlist_offers w WHERE expires_at<=clock_timestamp() AND EXISTS
  (SELECT 1 FROM eshop.waitlist_offer_slots s WHERE s.offer_id=w.id AND outcome='pending') ORDER BY form_id LIMIT p_batch_size LOOP
  PERFORM 1 FROM public.forms WHERE id=f FOR UPDATE;
  PERFORM 1 FROM eshop.orders WHERE form=f ORDER BY id FOR UPDATE;
  n:=public.expire_waitlist_form_internal(f,clock_timestamp(),p_batch_size-affected); affected:=affected+n;
  IF n>0 THEN
   SELECT occasion INTO occ FROM public.forms WHERE id=f;
   SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,'userId',ou."user")),'[]') INTO impacts
    FROM public.occasion_users ou CROSS JOIN unnest(ARRAY['private_profile','private_inventory']) component WHERE ou.occasion=occ;
   PERFORM public.record_client_sync_commit_v1(occ,'inventory.waitlist.expire','inventory',
    jsonb_build_array(jsonb_build_object('entityType','form','entityId',f,'operation','update','safeLabel','Offer expiry',
    'changedFields',jsonb_build_array('capacity','waitlistSummary'))),'{}',impacts,'[]','service',NULL);
  END IF;
  EXIT WHEN affected>=p_batch_size;
 END LOOP;
 RETURN jsonb_build_object('expiredSlots',affected);
END $$;
REVOKE ALL ON FUNCTION public.abort_waitlist_acceptance_internal(bigint,uuid),public.expire_waitlist_offers(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.expire_waitlist_offers(integer) TO service_role;


-- Source: database/functions/eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_participant_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            INSERT INTO eshop.tickets (state, occasion, ticket_symbol, note, created_at, updated_at)
            VALUES ('ordered', occasion_id, ticket_symbol, ticket_note, now, now)
            RETURNING id INTO ticket_id;

            IF NOT p_offer THEN
              INSERT INTO eshop.order_participants(current_order_id,origin_order_id,form_id,ticket_id,lifecycle,answers)
              VALUES(order_id,order_id,form_id,ticket_id,'admitted',public.extract_participant_answers_internal(form_id,ticket_data));
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        generated_variable_symbol := generate_payment_variable_symbol(bank_account_id, form_id);
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_reminder_interval BIGINT;
                v_reminder_is_enabled BOOLEAN;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- Only queue reminder if deadline is in the future
                    IF v_deposit_deadline_ts > NOW() THEN
                        -- Get reminder interval from occasion form feature
                        SELECT elem->>'reminder_interval_seconds'
                        INTO v_reminder_interval
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        -- Check if reminder is enabled on the form feature
                        SELECT (elem->>'reminder_is_enabled')::boolean
                        INTO v_reminder_is_enabled
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        IF COALESCE(v_reminder_is_enabled, FALSE) AND v_reminder_interval IS NOT NULL THEN
                            PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',
                                jsonb_build_object('order_id',order_id,'is_deposit_reminder',true),organization_id,occasion_id,unit_id,
                                v_deposit_deadline_ts-make_interval(secs=>v_reminder_interval));
                        END IF;
                    END IF;
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop/create_ticket_order.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_internal_v1(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f bigint; target bigint; result jsonb;
BEGIN
 BEGIN
  IF jsonb_typeof(input_data->'ticket')='array' AND jsonb_array_length(input_data->'ticket')>public.ticket_order_limit() THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',1023,'message','Maximum number of tickets per order exceeded','limit',public.ticket_order_limit())::text;
  END IF;
  SELECT id INTO f FROM public.forms WHERE key=(input_data->>'form')::uuid FOR UPDATE;
  IF f IS NULL THEN RAISE EXCEPTION 'Form not found'; END IF;
  target:=public.allocate_ticket_order_identity_internal(f);
  result:=public.finalize_ticket_order_internal_v1(target,input_data,false);
  IF coalesce((result->>'code')::integer,500)<>200 THEN RAISE EXCEPTION '%',result::text; END IF;
  RETURN result;
 EXCEPTION WHEN OTHERS THEN
  RETURN CASE WHEN left(SQLERRM,1)='{' THEN SQLERRM::jsonb ELSE jsonb_build_object('code',1013,'message',SQLERRM) END;
 END;
END $$;
REVOKE ALL ON FUNCTION public.create_ticket_order_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic
        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Ensure user is authorized to edit this occasion
        IF NOT COALESCE(get_is_editor_order_on_occasion(occasion_id), false) THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 403, 'message', 'User is not authorized to edit this occasion')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT (public.get_is_editor_on_unit(occasion_unit) OR public.get_is_editor_on_occasion(occasion_id)) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        -- Validate the link field, which must be unique within the same organization
        link_param := input_data->>'link';
        IF link_param IS NULL OR link_param = '' THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4013, 'message', 'Missing link in input data')::TEXT;
        END IF;

        -- Determine if we are creating a new form or updating an existing one
        form_id := NULLIF(input_data->>'id', '')::BIGINT;

        IF form_id IS NULL THEN
            -- New form: ensure link uniqueness via a join to occasions
            SELECT 1
              INTO conflict_check
              FROM public.forms f
              JOIN public.occasions o ON f.occasion = o.id
             WHERE o.organization = occasion_org
               AND f.link = link_param
             LIMIT 1;

            IF conflict_check IS NOT NULL THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4014,
                        'message', 'Link is already used by another form in the same organization'
                    )::TEXT;
            END IF;

            INSERT INTO public.forms (
                created_at,
                occasion,
                link
            )
            VALUES (
                now_ts,
                occasion_id,
                link_param
            )
            RETURNING id INTO form_id;
        ELSE
            -- Existing form: ensure form belongs to the occasion and link is still unique
            IF NOT EXISTS (
                SELECT 1
                FROM public.forms
                WHERE id = form_id
                  AND occasion = occasion_id
            ) THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4005,
                        'message', 'Form does not exist or does not match the given occasion',
                        'form_id', form_id
                    )::TEXT;
            END IF;

            PERFORM 1 FROM public.forms f WHERE f.id = form_id FOR UPDATE;

            SELECT 1
              INTO conflict_check
              FROM public.forms f
              JOIN public.occasions o ON f.occasion = o.id
             WHERE o.organization = occasion_org
               AND f.link = link_param
               AND f.id <> form_id
             LIMIT 1;

            IF conflict_check IS NOT NULL THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4014,
                        'message', 'Link is already used by another form in the same organization'
                    )::TEXT;
            END IF;
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.order_participants person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.answers->'fields')='array' THEN person.answers->'fields' ELSE '[]' END) answer
            WHERE person.form_id=ff.form AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_participants ledger WHERE ledger.form_id=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                field_id := NULLIF(field_data->>'id', '')::BIGINT;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = field_data->'data',
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = field_product_type,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = input_data->>'title',
               data = input_data->'data',
               header = input_data->>'header',
               header_off = input_data->>'header_off',
               link = link_param,
               blueprint = NULLIF(input_data->>'blueprint','')::BIGINT,
               bank_account = bank_account_val,
               deadline_duration_seconds = deadline_val,
               is_open = COALESCE((input_data->>'is_open')::BOOLEAN, true)
         WHERE id = form_id;

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        IF v_seconds_before_deadline IS NOT NULL THEN
            PERFORM public.queue_payment_reminders(occasion_id, v_seconds_before_deadline);
        END IF;

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'form_fields', form_fields_data
        );

    EXCEPTION WHEN OTHERS THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;


-- Source: database/functions/eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'header_off', f.header_off,
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', f.blueprint,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal((SELECT id FROM public.forms WHERE link=form_link),false);
$$;


-- Source: database/functions/eshop_forms/get_all_forms_with_fields.sql
CREATE OR REPLACE FUNCTION public.get_all_forms_with_fields(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    -- Find the ID of the occasion using its unique link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE link = occasion_link
      AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());

    -- Step 2: If no occasion is found, return a 404 'Not Found' error.
    -- This handles cases where the occasion_link does not exist.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_view_on_occasion` exists to check permissions.
    IF NOT public.get_is_editor_view_on_occasion(v_occasion_id)
       AND NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms and their associated fields for the occasion into a JSONB array.
    -- For each form, a subquery aggregates its related form_fields.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
                'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
                'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'response_count', (
                -- Subquery to count the number of responses (orders) for each form.
                SELECT COUNT(*)
                FROM eshop.orders o
                WHERE (o.data->>'form')::uuid = f.key
            ),
            'fields', (
                -- Subquery to aggregate all form_fields associated with the current form.
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'type', ff.type,
                        'is_ticket_field', ff.is_ticket_field
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                WHERE ff.form = f.id
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found for the occasion, return an empty JSON array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 'OK' status code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$$;


-- Source: database/functions/eshop_forms/get_form_for_edit.sql
-- Fix get_form_for_edit: Remove bigint = uuid comparison and add can_delete
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    v_unit_id BIGINT;
    formData JSONB;
    formFieldsData JSONB;
    productTypesData JSONB;
    productsData JSONB;
    availableBankAccountsData JSONB;
    canDelete BOOLEAN;
BEGIN
    SELECT
        f.id,
        f.occasion,
        o.unit
    INTO
        v_form_id,
        v_occasion_id,
        v_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.link = form_link;

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    -- Calculate can_delete
    -- FIXED: Compare form (bigint) with v_form_id (bigint) directly
    SELECT NOT EXISTS (
        SELECT 1 FROM eshop.orders WHERE form = v_form_id
    ) INTO canDelete;

    SELECT jsonb_build_object(
        'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', f.data,
        'type', f.type,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'occasion', f.occasion,
        'blueprint', f.blueprint,
        'link', f.link,
        'bank_account', f.bank_account,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'can_delete', canDelete -- Added field
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Materialize occasion history once rather than scanning it for every
    -- product and every field. Only current orders and current references determine eligibility.
    WITH occasion_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE occasion = v_occasion_id
    ), snapshots AS MATERIALIZED (
      SELECT data FROM occasion_orders
    ), used_products AS MATERIALIZED (
      SELECT opt.product::text AS product FROM eshop.order_product_ticket opt
      JOIN eshop.products p ON p.id = opt.product WHERE p.occasion = v_occasion_id
      UNION
      SELECT value #>> '{}' FROM snapshots s
      CROSS JOIN LATERAL jsonb_path_query(s.data, '$.tickets[*].products[*].id') ids(value)
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'occasion', p.occasion,
            'title', p.title,
            'description', p.description,
            'price', p.price,
            'currency_code', p.currency_code,
            'is_hidden', p.is_hidden,
            'order', p."order",
            'product_type', p.product_type,
            'ordered_count', (
                SELECT count(*)
                FROM eshop.order_product_ticket opt
                JOIN eshop.orders o ON opt."order" = o.id
                WHERE opt.product = p.id AND o.state <> 'storno'
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    CROSS JOIN LATERAL (SELECT CASE
      WHEN EXISTS (SELECT 1 FROM used_products u WHERE u.product = p.id::text) THEN 'orders'
      WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
      WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
      WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
    END AS reason) usage
    WHERE p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id);

    WITH form_orders AS MATERIALIZED (
      SELECT id, data FROM eshop.orders WHERE form = v_form_id
    ), form_snapshots AS MATERIALIZED (
      SELECT data FROM form_orders
    ), form_tickets AS MATERIALIZED (
      SELECT t.note FROM eshop.order_product_ticket opt
      JOIN form_orders o ON o.id = opt."order"
      JOIN eshop.tickets t ON t.id = opt.ticket
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
            'form', ff.form,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'is_hidden', ff.is_hidden,
            'is_ticket_field', ff.is_ticket_field,
            'order', ff."order",
            'product_type', ff.product_type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    CROSS JOIN LATERAL (SELECT CASE WHEN EXISTS (
      SELECT 1 FROM form_snapshots s WHERE
        EXISTS (SELECT 1 FROM jsonb_array_elements(
          CASE WHEN jsonb_typeof(s.data->'fields') = 'array' THEN s.data->'fields' ELSE '[]'::jsonb END) answer
          WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
        OR (ff.type = 'ticket' AND jsonb_path_exists(s.data, '$.tickets[*]'))
        OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(s.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
    ) OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM form_tickets))
      OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (SELECT 1 FROM form_tickets WHERE NULLIF(note, '') IS NOT NULL))
      OR EXISTS(SELECT 1 FROM eshop.order_participants person CROSS JOIN LATERAL jsonb_array_elements(
        CASE WHEN jsonb_typeof(person.answers->'fields')='array' THEN person.answers->'fields' ELSE '[]' END) answer
        WHERE person.form_id=ff.form AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
      OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_participants WHERE form_id=ff.form))
    THEN 'responses' ELSE (
      SELECT p->>'delete_blocked_reason' FROM public.form_fields member
      JOIN jsonb_array_elements(productsData) p ON (p->>'product_type')::bigint = member.product_type
      WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
        AND p->>'delete_blocked_reason' IS NOT NULL
      ORDER BY (p->>'id')::bigint LIMIT 1
    ) END AS reason) usage
    WHERE ff.form = v_form_id;

    -- FIX: Exclude CASH accounts and ensure deterministic sorting by Priority
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ba.id,
            'account_number', ba.account_number,
            'account_number_human_readable', ba.account_number_human_readable,
            'title', ba.title,
            'supported_currencies', ba.supported_currencies,
            'type', ba.type
        ) ORDER BY uba.priority ASC, ba.id ASC
    ), '[]'::jsonb)
    INTO availableBankAccountsData
    FROM eshop.unit_bank_accounts uba
    JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
    WHERE uba.unit = v_unit_id
      AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'form', formData,
            'form_fields', formFieldsData,
            'product_types', productTypesData,
            'products', productsData,
            'available_bank_accounts', availableBankAccountsData
        )
    );
END;
$$;


-- Source: database/functions/eshop_forms/duplicate_form_to_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_form_to_occasion(
    source_form_id BIGINT,
    target_occasion_link TEXT
)
RETURNS BIGINT -- Returns the ID of the new form
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    user_id UUID := auth.uid();
    target_occasion_id BIGINT;
    target_organization_id BIGINT;
    source_occasion_id BIGINT;
    source_unit_id BIGINT;
    has_source_permission BOOLEAN;
    has_target_permission BOOLEAN;
    new_form_id BIGINT;
    v_new_form_link TEXT;
    form_field_record RECORD;
    new_product_type_id BIGINT;
    product_record RECORD;
BEGIN
    -- Step 1: Resolve the target occasion ID and its organization ID from its link.
    SELECT id, organization INTO target_occasion_id, target_organization_id
    FROM public.occasions WHERE link = target_occasion_link;
    IF target_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Target occasion not found for link: %', target_occasion_link;
    END IF;

    -- Step 2: Get the source occasion and unit IDs for permission checking.
    SELECT f.occasion, o.unit
    INTO source_occasion_id, source_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = source_form_id;

    IF source_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Source form not found.';
    END IF;

    -- Step 3: Check if the user has editor_view rights on the source occasion or its unit.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = source_occasion_id AND "user" = user_id AND is_editor_view = TRUE
    ) OR EXISTS (
        SELECT 1 FROM public.unit_users
        WHERE unit = source_unit_id AND "user" = user_id AND is_editor_view = TRUE
    )
    INTO has_source_permission;

    IF NOT has_source_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to view the source form.';
    END IF;

    -- Step 4: Check if the user has editor rights on the target occasion.
    SELECT EXISTS (
        SELECT 1 FROM public.occasion_users
        WHERE occasion = target_occasion_id AND "user" = user_id AND is_editor = TRUE
    )
    INTO has_target_permission;

    IF NOT has_target_permission THEN
        RAISE EXCEPTION 'Insufficient permissions to create a form in the target occasion.';
    END IF;

    -- Step 5: Generate a unique link for the new form within the same organization.
    -- Try to use the target occasion's link first. If it's taken within the same organization, append a random hash.
    IF EXISTS (
        SELECT 1
        FROM public.forms f
        JOIN public.occasions o ON f.occasion = o.id
        WHERE f.link = target_occasion_link AND o.organization = target_organization_id
    ) THEN
        v_new_form_link := target_occasion_link || '-' || substring(md5(random()::text) from 1 for 8);
    ELSE
        v_new_form_link := target_occasion_link;
    END IF;

    -- Step 6: Copy the main form record to the target occasion.
    INSERT INTO public.forms (title, data, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds)
    SELECT
        title || ' (Copy)',
        data,
        target_occasion_id,
        type,
        bank_account,
        deadline_duration_seconds,
        is_open,
        v_new_form_link, -- Use the generated unique link
        blueprint,
        header,
        header_off,participant_capacity,waitlist_enabled,show_remaining_capacity,waitlist_offer_duration_seconds
    FROM public.forms
    WHERE id = source_form_id
    RETURNING id INTO new_form_id;

    -- Step 7: Loop through each field of the source form and perform a deep copy.
    FOR form_field_record IN
        SELECT * FROM public.form_fields WHERE form = source_form_id
    LOOP
        -- Check if the field is linked to a product type.
        IF form_field_record.product_type IS NOT NULL THEN
            -- A) If yes, perform a deep copy of the product type and its products.
            INSERT INTO eshop.product_types (title, description, type, data, occasion, maximum)
            SELECT title, description, type, data, target_occasion_id, maximum
            FROM eshop.product_types
            WHERE id = form_field_record.product_type
            RETURNING id INTO new_product_type_id;

            FOR product_record IN
                SELECT * FROM eshop.products WHERE product_type = form_field_record.product_type
            LOOP
                INSERT INTO eshop.products (title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
                VALUES (
                    product_record.title, product_record.description, product_record.price, product_record.data,
                    new_product_type_id, target_occasion_id, product_record.is_hidden, product_record.currency_code,
                    product_record.order, product_record.maximum
                );
            END LOOP;

            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                new_product_type_id, form_field_record.is_ticket_field
            );
        ELSE
            -- B) If not, perform a simple copy of the form field.
            INSERT INTO public.form_fields (title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
            VALUES (
                form_field_record.title, form_field_record.description, form_field_record.data, form_field_record.type,
                form_field_record.is_required, new_form_id, form_field_record.is_hidden, form_field_record.order,
                NULL, form_field_record.is_ticket_field
            );
        END IF;
    END LOOP;

    -- Step 8: Return the ID of the newly created form.
    RETURN new_form_id;
END;
$$;

-- Source: database/functions/others/duplicate_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_source_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, is_hidden, is_open, is_promoted, start_time, end_time,
         link || '-copy-' || substring(md5(random()::text) from 1 for 8) AS link,
         title || ' (Copy)', v_organization, services, v_target_unit, features, occasion_hidden, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  RAISE NOTICE 'New occasion id: %', new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, configuration, objects, groups, background_svg
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order"
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order")
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order")
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint))
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- 6. Update blueprints “objects” JSON column if it contains spot objects.
  --    For each blueprint, if its "objects" JSON array contains an object with "type" = 'spot',
  --    replace its "id" with the corresponding new spot id.
  ------------------------------------------------------------------
  FOR rec IN
    SELECT tb.old_id AS old_bp, tb.new_id AS new_bp, b.objects
    FROM tmp_blueprints tb
    JOIN eshop.blueprints b ON b.id = tb.new_id
  LOOP
    IF rec.objects IS NOT NULL THEN
      UPDATE eshop.blueprints
      SET objects = (
        SELECT jsonb_agg(
          CASE
            WHEN obj->>'type' = 'spot' THEN
              obj || jsonb_build_object(
                'id',
                COALESCE(
                  (SELECT ts.new_id FROM tmp_spots ts WHERE ts.old_id = (obj->>'id')::bigint),
                  (obj->>'id')::int
                )
              )
            ELSE obj
          END
        )
        FROM jsonb_array_elements(rec.objects) AS obj
      )
      WHERE id = rec.new_bp;
    END IF;
  END LOOP;


  ------------------------------------------------------------------
  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title,
      participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            replace(uuid_generate_v4()::text, '-', ''),
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  INSERT INTO public.form_fields
    (created_at, title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
  SELECT now(), title, description, data, type, is_required,
         (SELECT tf.new_id FROM tmp_forms AS tf WHERE tf.old_id = form),
         is_hidden, "order",
         CASE WHEN product_type IS NOT NULL
              THEN (SELECT tp.new_id FROM tmp_product_types AS tp WHERE tp.old_id = product_type)
              ELSE NULL END,
         is_ticket_field
  FROM public.form_fields
  WHERE form IN (SELECT old_id FROM tmp_forms);

  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated;


-- Source: database/functions/eshop_orders/check_order_is_mutable.sql
-- Domain commands authorize callers before invoking these private guards.
-- Lock the order through the write so cancellation cannot race with an edit.
CREATE OR REPLACE FUNCTION public.check_order_is_mutable(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
  SELECT state INTO v_state FROM eshop.orders WHERE id=p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state IN ('waitlisted','preparing_payment') THEN
    RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED' USING ERRCODE='55000';
  END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_ticket_is_mutable(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint; v_state text;
BEGIN
  FOR v_order IN SELECT DISTINCT opt."order" FROM eshop.order_product_ticket opt
    WHERE opt.ticket=p_ticket ORDER BY opt."order" LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
  SELECT state INTO v_state FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TICKET_NOT_FOUND' USING ERRCODE='P0002'; END IF;
  IF v_state='storno' THEN
    RAISE EXCEPTION 'TICKET_CANCELLED: Cancelled tickets are read-only' USING ERRCODE='55000';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.check_payment_info_is_mutable(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_order bigint;
BEGIN
  FOR v_order IN SELECT id FROM eshop.orders WHERE payment_info=p_payment ORDER BY id LOOP
    PERFORM public.check_order_is_mutable(v_order);
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.check_order_is_mutable(bigint),
  public.check_ticket_is_mutable(bigint),public.check_payment_info_is_mutable(bigint)
  TO service_role;


-- Source: database/functions/eshop_orders/internal_storno_tickets_221.sql
CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
BEGIN
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE eshop.order_participants SET lifecycle='cancelled',updated_at=clock_timestamp() WHERE ticket_id=ANY(ticket_ids_to_storno);
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT form_id FROM eshop.order_participants WHERE ticket_id=ANY(ticket_ids_to_storno));
    -- 1. Get all related order_product_ticket IDs
    SELECT ARRAY_AGG(opt.id) INTO opt_ids
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ANY(ticket_ids_to_storno);

    -- 2. (NEW) Delete any occasion_users linked to these tickets.
    -- We delete directly because the parent function already
    -- verified the user has 'editor' permissions.
    DELETE FROM public.occasion_users
    WHERE ticket = ANY(ticket_ids_to_storno);

    -- 3. Update the tickets themselves to 'storno'
    UPDATE eshop.tickets
    SET state = 'storno', updated_at = NOW()
    WHERE id = ANY(ticket_ids_to_storno);

    -- 4. Nullify the relevant spots
    IF opt_ids IS NOT NULL THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL,
            secret = NULL,
            secret_expiration_time = NULL,
            updated_at = NOW(),
            resource = NULL,
            state = NULL
        WHERE order_product_ticket = ANY(opt_ids);
    END IF;

    -- 5. Nullify the product link on the order_product_ticket records
    UPDATE eshop.order_product_ticket
    SET product = NULL
    WHERE ticket = ANY(ticket_ids_to_storno);

END;
$$;

-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno_ws.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(order_id bigint)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion INTO occasion_id FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Verify if the user is an editor on the occasion
    IF (SELECT get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Use the same parent lock order as ticket cancellation.
    PERFORM 1 FROM eshop.orders WHERE id=order_id FOR UPDATE;

    -- Call the original function to update the order and tickets
    PERFORM update_order_and_tickets_to_storno_221(order_id);
END;
$$;
REVOKE ALL ON FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(bigint) FROM PUBLIC,anon,authenticated;


-- Source: database/functions/eshop_orders/storno_tickets_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_client_sync_v1(
  p_tickets bigint[],p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[]; v_changed_orders bigint[]; v_cancelled jsonb; v_updated jsonb;
BEGIN
  SELECT min(t.occasion) INTO v_occasion FROM eshop.tickets t
    WHERE t.id=ANY(p_tickets);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_tickets)=0
    OR (SELECT count(*) FROM eshop.tickets t
      WHERE t.id=ANY(p_tickets) AND t.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_tickets) id))
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'tickets',p_tickets)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.tickets.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_tickets)));
  -- Lock in the same order as the bulk mutation, then capture only actual changes.
  PERFORM o.id FROM eshop.orders o WHERE o.id IN (
    SELECT opt."order" FROM eshop.order_product_ticket opt
    JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets)) ORDER BY o.id FOR UPDATE;
  SELECT array_agg(DISTINCT opt."order") INTO v_changed_orders
    FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
    WHERE t.id=ANY(p_tickets) AND t.state IS DISTINCT FROM 'storno';
  PERFORM public.storno_tickets_bulk_internal_v1(p_tickets);
  SELECT coalesce(jsonb_agg(o.id ORDER BY o.id) FILTER(WHERE o.state='storno'),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('id',o.id,'email',o.data->>'email') ORDER BY o.id)
      FILTER(WHERE o.state IS DISTINCT FROM 'storno'),'[]'::jsonb)
    INTO v_cancelled,v_updated FROM eshop.orders o WHERE o.id=ANY(v_changed_orders);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.tickets.cancel',
    jsonb_build_array(jsonb_build_object('entityType','ticket','entityId',NULL,
      'operation','update','safeLabel','Ticket cancellation',
      'changedFields',jsonb_build_array('state','membership','allocations'))),
    v_before_users,jsonb_build_object('ticketIds',to_jsonb(p_tickets),
      'cancelledOrderIds',v_cancelled,'updatedOrders',v_updated));
END; $$;
REVOKE ALL ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_tickets_client_sync_v1(bigint[],uuid)
  TO authenticated;


-- Source: database/functions/eshop_orders/storno_tickets_bulk.sql
CREATE OR REPLACE FUNCTION public.storno_tickets_bulk_internal_v1(p_ticket_ids BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_order_id BIGINT;
    v_occasion_id BIGINT;
    v_tickets_in_order BIGINT[];
    v_tickets_to_cancel_in_order BIGINT[];
    v_remaining_count INT;
    v_ticket_id_to_remove BIGINT;
    v_original_data JSONB;
    v_updated_tickets_json JSONB;
    v_ticket_elem JSONB;
    v_product_elem JSONB;
    v_removed_price NUMERIC(10, 2);
    v_current_price NUMERIC(10, 2);
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(p_ticket_ids)));
    -- 1. Identify all unique orders involved in this batch AND their occasion
    -- We need the occasion ID to perform the security check
    FOR v_order_id, v_occasion_id IN
        SELECT DISTINCT o.id, o.occasion
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE t.id = ANY(p_ticket_ids)
        ORDER BY o.id
    LOOP
        -- 2. SECURITY CHECK
        -- Verify that the current user has editor permissions on the occasion associated with the order.
        IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
            RAISE EXCEPTION 'Permission denied to storno tickets for order % on occasion %', v_order_id, v_occasion_id;
        END IF;

        -- Already-cancelled tickets are an idempotent no-op after authorization.
        -- They must not invoke the edit guard or create a second cancellation intent.
        IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket
          WHERE opt."order"=v_order_id AND t.id=ANY(p_ticket_ids) AND t.state IS DISTINCT FROM 'storno') THEN
          CONTINUE;
        END IF;
        PERFORM public.check_order_is_mutable(v_order_id);
        -- Serialize cancellations on the same order before counting survivors.
        PERFORM 1 FROM eshop.orders WHERE id = v_order_id FOR UPDATE;

        -- 3. Get all active tickets currently in this order
        SELECT ARRAY_AGG(t.id)
        INTO v_tickets_in_order
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        WHERE opt."order" = v_order_id
        AND (t.state IS NULL OR t.state != 'storno');

        -- 4. Get intersection: Tickets in this order that we want to cancel
        SELECT ARRAY_AGG(id)
        INTO v_tickets_to_cancel_in_order
        FROM UNNEST(v_tickets_in_order) AS id
        WHERE id = ANY(p_ticket_ids);

        -- A replay or a selection containing only cancelled tickets has no effect.
        IF coalesce(cardinality(v_tickets_to_cancel_in_order), 0) = 0 THEN
            CONTINUE;
        END IF;

        -- 5. Calculate how many would remain
        v_remaining_count := array_length(v_tickets_in_order, 1) - array_length(v_tickets_to_cancel_in_order, 1);

        -- -----------------------------------------------------
        -- SCENARIO A: Full Order Cancellation
        -- -----------------------------------------------------
        IF v_remaining_count <= 0 THEN
            -- Helper function to cancel the entire order
            PERFORM update_order_and_tickets_to_storno_ws_internal_v1(v_order_id);
            -- Commit cancellation and its durable email intent together. Replays
            -- cannot reach this branch once the active tickets are cancelled.
            IF EXISTS (SELECT 1 FROM eshop.orders WHERE id=v_order_id
                AND position('@' in data->>'email')>0 AND length(data->>'email')<=320) THEN
            PERFORM public.enqueue_order_email('TICKET_ORDER_STORNO',
                jsonb_build_object('order_id', v_order_id),
                (SELECT organization FROM public.occasions WHERE id=v_occasion_id),
                v_occasion_id,
                (SELECT unit FROM public.occasions WHERE id=v_occasion_id),
                now(), 'last-ticket-cancelled:' || v_order_id);
            END IF;


        -- -----------------------------------------------------
        -- SCENARIO B: Partial Cancellation (Modify Order)
        -- -----------------------------------------------------
        ELSE
            -- 1. Mark specific tickets as storno in DB
            PERFORM internal_storno_tickets_221(v_tickets_to_cancel_in_order);

            -- 2. Fetch Order Data
            SELECT data, price INTO v_original_data, v_current_price
            FROM eshop.orders WHERE id = v_order_id;

            v_updated_tickets_json := '[]'::JSONB;
            v_removed_price := 0;

            -- 3. Rebuild JSON data, filtering out cancelled tickets and summing price to remove
            FOR v_ticket_elem IN SELECT * FROM jsonb_array_elements(v_original_data->'tickets')
            LOOP
                v_ticket_id_to_remove := (v_ticket_elem->>'id')::BIGINT;

                -- If this ticket is one of the ones being cancelled
                IF v_ticket_id_to_remove = ANY(v_tickets_to_cancel_in_order) THEN
                    -- Sum up price to deduct
                    FOR v_product_elem IN SELECT * FROM jsonb_array_elements(v_ticket_elem->'products')
                    LOOP
                        v_removed_price := v_removed_price + COALESCE((v_product_elem->>'price')::NUMERIC, 0);
                    END LOOP;
                ELSE
                    -- Keep this ticket in the new JSON
                    v_updated_tickets_json := v_updated_tickets_json || v_ticket_elem;
                END IF;
            END LOOP;

            -- Fence unsent snapshots of the previous ticket set, and keep the
            -- payment amount aligned with the new order total.
            PERFORM public.cancel_order_email_intents(v_order_id);
            UPDATE eshop.payment_info SET amount=GREATEST(0, COALESCE(v_current_price,0)-v_removed_price)
            WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=v_order_id);

            -- 4. Update Order (Data & Price)
            UPDATE eshop.orders
            SET
                data = v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                price = GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                email_payment_version = email_payment_version + 1,
                updated_at = NOW()
            WHERE id = v_order_id;

            -- Refresh only this order's existing reminder schedule for its new amount.
            PERFORM public.set_payment_deadline(pi.id,pi.deadline)
            FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id
            WHERE o.id=v_order_id AND o.state='ordered' AND pi.deadline IS NOT NULL;

            -- Existing delivery policy prepares the surviving tickets if their
            -- paid order has not finished sending yet; sent orders stay untouched.
            PERFORM public.enqueue_paid_order_tickets(v_order_id);

            -- 5. Insert ONE history record for this modification
            INSERT INTO eshop.orders_history (
                "order",
                data,
                state,
                price,
                created_at
            )
            VALUES (
                v_order_id,
                v_original_data || JSONB_BUILD_OBJECT('tickets', v_updated_tickets_json),
                (SELECT state FROM eshop.orders WHERE id=v_order_id),
                GREATEST(0, COALESCE(v_current_price, 0) - v_removed_price),
                NOW()
            );
        END IF;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.storno_tickets_bulk_internal_v1(bigint[]) FROM PUBLIC, anon, authenticated;


-- Source: database/functions/eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_paid             numeric;
  v_price            numeric;
  v_new_state        text;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
  v_current_products_for_compare jsonb;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT public.get_is_editor_order_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  PERFORM public.lock_ticket_order_products_internal(v_order_id,jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',x->'id')),'[]') FROM jsonb_array_elements(p_products) x)))));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) decide new state based on money received */
  SELECT COALESCE(pi.paid,0), o.price
    INTO v_paid, v_price
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON o.payment_info = pi.id
   WHERE o.id = v_order_id;

  v_new_state := CASE
                   WHEN v_paid >= v_price AND v_price > 0 THEN 'paid'
                   WHEN v_price <= 0 THEN 'paid'
                   ELSE 'ordered'
                 END;

  IF v_new_state = 'paid' THEN
    IF NOT EXISTS (
      SELECT 1 FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
      WHERE opt."order" = v_order_id AND t.state <> 'sent'
    ) THEN
      v_new_state := 'sent';
    END IF;
  END IF;

  PERFORM public.cancel_order_email_intents(v_order_id);
  UPDATE eshop.orders
     SET email_payment_version=email_payment_version+1, state      = v_new_state,
         updated_at = now()
   WHERE id = v_order_id;

  -- A price edit can pay off the order without the usual paid transition.
  -- Email acceptance only projects paid tickets to sent, so keep eligible
  -- tickets in step with the order before creating its delivery intent.
  IF v_new_state = 'paid' THEN
    UPDATE eshop.tickets t
       SET state = 'paid', updated_at = now()
      FROM eshop.order_product_ticket opt
     WHERE opt.ticket = t.id AND opt."order" = v_order_id
       AND t.state IN ('ordered', 'expired');
  END IF;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM public.apply_allocations(v_order_id);
  PERFORM public.enqueue_paid_order_tickets(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_new_state,
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;


-- Source: database/functions/eshop_orders/update_order_note_hidden.sql
    CREATE OR REPLACE FUNCTION public.update_order_note_hidden(order_id bigint, new_note_hidden text)
    RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
    DECLARE
        occasion_id bigint;
    BEGIN
        -- Retrieve the occasion_id from the order
        SELECT occasion INTO occasion_id FROM eshop.orders WHERE id = order_id;

        -- Check if occasion_id was successfully retrieved
        IF occasion_id IS NULL THEN
            RETURN jsonb_build_object('code', 404, 'message', 'Order not found or occasion not specified');
        END IF;

        -- Check if the user has the right to edit the given occasion
        IF (get_is_editor_order_on_occasion(occasion_id)) <> TRUE THEN
            -- Return an error if the user is not authorized
            RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
        END IF;

        PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
        IF (SELECT state FROM eshop.orders WHERE id=order_id)<>'waitlisted' THEN
          PERFORM public.check_order_is_mutable(order_id);
        END IF;

        -- Proceed to update note_hidden if the user is authorized
        UPDATE eshop.orders
        SET note_hidden = new_note_hidden, updated_at = now()
        WHERE id = order_id;

        -- Check if the update was successful
        IF FOUND THEN
            RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
        ELSE
            RETURN jsonb_build_object('code', 404, 'message', 'Order not found');
        END IF;
    END;
    $$ LANGUAGE plpgsql;


-- Source: database/functions/eshop_orders/get_orders.sql
CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE link = p_occasion_link
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE link = p_form_link
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT get_is_editor_order_view_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'participant_capacity',f.participant_capacity,
        'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,
        'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),
        'registrationMode',public.get_form_registration_mode_internal(f.id),
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders, conditionally filtering by form link
    IF v_form_id IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id AND o.form = v_form_id;
    ELSE
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN public.get_waitlist_summary_internal(o.id) END,
            'isActive',(public.get_waitlist_summary_internal(o.id)->>'isActive')::boolean,
            'allowedActions',public.get_waitlist_summary_internal(o.id)->'allowedActions',
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'order_sequence', (SELECT o.order_sequence FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;


-- Source: database/functions/eshop/update_product.sql

CREATE OR REPLACE FUNCTION public.update_product_internal_v1(p_input JSONB)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_product_id BIGINT;
  v_occasion_id BIGINT;
  v_product_type_id BIGINT;
  v_existing_price NUMERIC;
  v_input_price NUMERIC;
  v_effective_price NUMERIC;
  v_input_deposit NUMERIC;
BEGIN
  -- Extract product id from the input JSON
  v_product_id := (p_input->>'id')::BIGINT;

  -- Try to find the product to determine if we are updating or creating.
  -- This also gets the *current* occasion for the permission check on UPDATE.
  IF v_product_id IS NOT NULL THEN
    SELECT pt.occasion, p.price
    INTO v_occasion_id, v_existing_price
    FROM eshop.products p
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE p.id = v_product_id FOR UPDATE OF p;
  END IF;

  -- CASE 1: Product was found (v_product_id was not null and existed)
  IF FOUND THEN
    -- We are UPDATING.

    -- Ensure the caller has permission to edit this product's *current* occasion.
    -- This function is expected to raise an exception on failure.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    -- VALIDATION: deposit amount must be less than effective price (input price overrides existing)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_effective_price := COALESCE(v_input_price, v_existing_price);
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_effective_price IS NOT NULL AND v_input_deposit >= v_effective_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_effective_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price_update(v_product_id,v_effective_price,
      COALESCE(p_input->'data',(SELECT data FROM eshop.products WHERE id=v_product_id)),
      COALESCE(p_input->>'currency_code',(SELECT currency_code FROM eshop.products WHERE id=v_product_id)));
    -- A product with schedules cannot silently move to another occasion/type.
    IF EXISTS (SELECT 1 FROM eshop.planned_changes WHERE subject_id=v_product_id
      AND change_type IN('products.price','products.is_hidden') AND NOT applied) AND (
      NULLIF(p_input->>'occasion','')::bigint IS DISTINCT FROM v_occasion_id AND p_input->>'occasion' IS NOT NULL
      OR NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM
        (SELECT product_type FROM eshop.products WHERE id=v_product_id) AND p_input->>'product_type' IS NOT NULL
    ) THEN RAISE EXCEPTION 'CANCEL_PRICE_CHANGES_BEFORE_PRODUCT_MOVE'; END IF;

    IF p_input->>'product_type' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=(p_input->>'product_type')::bigint AND occasion=v_occasion_id) THEN RAISE EXCEPTION 'Product type occasion mismatch'; END IF;
    IF p_input->>'occasion' IS NOT NULL AND (p_input->>'occasion')::bigint<>v_occasion_id THEN RAISE EXCEPTION 'Product occasion cannot change'; END IF;
    -- Update only the fields that are provided in the input JSON.
    -- COALESCE is used to keep the existing value if a new one isn't provided.
    -- NULLIF is added to safely handle empty strings '' during casting.
    PERFORM 1 FROM public.occasions WHERE id=v_occasion_id FOR UPDATE;
    IF p_input ? 'product_type' AND NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM (SELECT product_type FROM eshop.products WHERE id=v_product_id)
      AND EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE product=v_product_id)
    THEN RAISE EXCEPTION 'Purchased product type cannot change'; END IF;
    IF nullif(p_input->>'maximum','')::integer>0 AND
      nullif(p_input->>'maximum','')::integer<(SELECT count(*) FROM eshop.order_product_ticket WHERE product=v_product_id) THEN
      RAISE EXCEPTION 'PRODUCT_CAPACITY_BELOW_COMMITTED'; END IF;
    UPDATE eshop.products p
    SET
      occasion      = COALESCE(NULLIF(p_input->>'occasion', '')::BIGINT, p.occasion),
      title         = COALESCE(p_input->>'title',         p.title),
      description   = COALESCE(p_input->>'description',   p.description),
      price         = COALESCE(NULLIF(p_input->>'price', '')::NUMERIC, p.price),
      currency_code = COALESCE(p_input->>'currency_code', p.currency_code),
      data          = COALESCE(p_input->'data',           p.data),
      product_type  = COALESCE(NULLIF(p_input->>'product_type', '')::BIGINT, p.product_type),
      "order"       = COALESCE(NULLIF(p_input->>'order', '')::INT,  p."order"),
      maximum       = COALESCE(NULLIF(p_input->>'maximum', '')::INT, p.maximum),
      is_hidden     = COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, p.is_hidden),
      updated_at    = NOW()
    WHERE p.id = v_product_id;

    -- Return the ID of the updated product on success.
    RETURN v_product_id;

  -- CASE 2: Product was NOT found (v_product_id was NULL or was an ID that doesn't exist)
  ELSE
    -- We are CREATING, as per the request.

    -- 1. Get the product_type from the JSON.
    v_product_type_id := (p_input->>'product_type')::BIGINT;

    -- 2. Validate product_type is provided (it's required for creation).
    IF v_product_type_id IS NULL THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PRD422',
          'message', 'Field "product_type" is required when creating a new product.'
      )::text;
    END IF;

    -- 3. Find the occasion for the *new* product_type to check permissions.
    SELECT occasion
    INTO v_occasion_id
    FROM eshop.product_types
    WHERE id = v_product_type_id;

    -- 4. Handle invalid product_type.
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PTY404',
          'message', 'Product type with ID ' || v_product_type_id || ' not found.'
      )::text;
    END IF;

    -- 5. Ensure the caller has permission to create a product on this occasion.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    -- 6. VALIDATION: deposit amount must be less than price (both from input on CREATE)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_input_price IS NOT NULL AND v_input_deposit >= v_input_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_input_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price(v_input_price,p_input->'data',p_input->>'currency_code');

    -- 7. Insert the new product.
    -- We ignore the `id` from the JSON (v_product_id) and let the sequence generate a new one.
    -- We use NULLIF to safely cast potentially empty strings.
    INSERT INTO eshop.products (
      occasion,
      title,
      description,
      price,
      currency_code,
      data,
      product_type,
      "order",
      maximum,
      is_hidden
      -- created_at and updated_at are assumed to have defaults (e.g., NOW())
    )
    VALUES (
      v_occasion_id,
      p_input->>'title',
      p_input->>'description',
      NULLIF(p_input->>'price', '')::NUMERIC,
      p_input->>'currency_code',
      p_input->'data',
      v_product_type_id, -- We already extracted and validated this
      NULLIF(p_input->>'order', '')::INT,
      NULLIF(p_input->>'maximum', '')::INT,
      -- Default to 'false' if is_hidden is not provided on create
      COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, false)
    )
    RETURNING id INTO v_product_id; -- Get the newly created ID

    -- Return the ID of the newly created product.
    RETURN v_product_id;

  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_product_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.update_product(p_input jsonb)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN (public.update_product_client_sync_v1(p_input,extensions.gen_random_uuid())->'data'->>'productId')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.update_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product(jsonb) TO authenticated;


-- Source: database/functions/inventory/apply_allocations.sql
CREATE OR REPLACE FUNCTION apply_allocations(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_order_state TEXT;
    v_item_to_allocate RECORD;
    v_existing_spot_count INT;
    v_spots_to_claim INT;
    v_available_spot_id BIGINT;
    v_occasion_id BIGINT;
    v_spots_to_disallocate BIGINT[];
    v_occasion_features JSONB;
    v_is_blueprint_enabled BOOLEAN;
BEGIN
    PERFORM public.lock_ticket_order_products_internal(p_order_id);
    -- Initial check for the order's state.
    SELECT state, occasion INTO v_order_state, v_occasion_id
    FROM eshop.orders
    WHERE id = p_order_id;

    SELECT features INTO v_occasion_features FROM public.occasions WHERE id = v_occasion_id;
    v_is_blueprint_enabled := jsonb_path_exists(v_occasion_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)');

    -- If the order is not found, raise a structured exception.
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'A001', 'message', 'Order with ID ' || p_order_id || ' not found.')::text;
    END IF;

    -- If the order state is 'storno', disallocate all spots and exit.
    IF v_order_state = 'storno' THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = NULL, updated_at = now()
        WHERE order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id);
        RETURN;
    END IF;

    -- Disallocate spots that are no longer required by the order.
    WITH required_spots AS (
        SELECT opt.id as order_product_ticket_id, pic.inventory_context as inventory_context_id, generate_series(1, pic.quantity)
        FROM eshop.order_product_ticket opt
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE opt."order" = p_order_id
    ),
    current_spots AS (
        SELECT s.id, s.order_product_ticket, s.inventory_context
        FROM eshop.spots s
        WHERE s.order_product_ticket IN (SELECT id FROM eshop.order_product_ticket WHERE "order" = p_order_id)
    )
    SELECT array_agg(cs.id)
    INTO v_spots_to_disallocate
    FROM current_spots cs
    LEFT JOIN required_spots rs ON cs.order_product_ticket = rs.order_product_ticket_id AND cs.inventory_context = rs.inventory_context_id
    JOIN eshop.order_product_ticket opt ON cs.order_product_ticket = opt.id
    JOIN eshop.products p ON opt.product = p.id
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE rs.order_product_ticket_id IS NULL
      AND NOT (v_is_blueprint_enabled AND pt.type = 'spot');

    IF v_spots_to_disallocate IS NOT NULL AND array_length(v_spots_to_disallocate, 1) > 0 THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL, state = NULL, resource = NULL, updated_at = now()
        WHERE id = ANY(v_spots_to_disallocate);
    END IF;

    -- Loop through each product in the order that requires an inventory spot to allocate new spots.
    FOR v_item_to_allocate IN
        SELECT
            opt.id AS order_product_ticket_id,
            opt.product AS product_id,
            pic.inventory_context AS inventory_context_id,
            pic.quantity AS required_quantity
        FROM eshop.orders o
        JOIN eshop.order_product_ticket opt ON o.id = opt."order"
        JOIN eshop.products p ON opt.product = p.id
        JOIN eshop.product_inventory_contexts pic ON p.id = pic.product
        WHERE o.id = p_order_id
    LOOP
        -- Check for existing spots for this specific order item AND inventory context.
        SELECT COUNT(*)
        INTO v_existing_spot_count
        FROM eshop.spots s
        WHERE s.order_product_ticket = v_item_to_allocate.order_product_ticket_id
          AND s.inventory_context = v_item_to_allocate.inventory_context_id;

        -- Calculate exactly how many spots are missing.
        v_spots_to_claim := v_item_to_allocate.required_quantity - v_existing_spot_count;

        IF v_spots_to_claim <= 0 THEN
            CONTINUE;
        END IF;

        IF EXISTS(SELECT 1 FROM public.inventory_contexts ic JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
          WHERE ic.id=v_item_to_allocate.inventory_context_id AND ip.sellable_capacity IS NOT NULL AND
          (SELECT count(*) FROM eshop.spots s WHERE s.inventory_context=ic.id AND (s.order_product_ticket IS NOT NULL OR
            (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())))+v_spots_to_claim>ip.sellable_capacity) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',1017,'errorCode','PRODUCT_CAPACITY_EXCEEDED','productId',v_item_to_allocate.product_id)::text;
        END IF;
        -- This loop runs precisely the number of times needed to claim the required spots.
        FOR i IN 1..v_spots_to_claim LOOP
            v_available_spot_id := NULL;

            -- Find an available spot. A spot is available only if it's unassigned.
            WITH available_spot_cte AS (
                SELECT s.id
                FROM eshop.spots s
                WHERE s.inventory_context = v_item_to_allocate.inventory_context_id
                  AND s.order_product_ticket IS NULL
                  AND (s.secret IS NULL OR s.secret_expiration_time IS NULL OR s.secret_expiration_time<=clock_timestamp())
                LIMIT 1
                FOR UPDATE SKIP LOCKED
            )
            SELECT id INTO v_available_spot_id FROM available_spot_cte;

            -- If no available spot is found, we must fail with a structured error.
            IF v_available_spot_id IS NULL THEN
                 DECLARE
                    product_data RECORD;
                 BEGIN
                    -- Fetch the details of the product that could not be allocated.
                    SELECT
                        p.id,
                        p.title,
                        p.description,
                        p.price,
                        pt.type,
                        pt.title as type_title,
                        p.currency_code
                    INTO product_data
                    FROM eshop.products p
                    LEFT JOIN eshop.product_types pt ON p.product_type = pt.id
                    WHERE p.id = v_item_to_allocate.product_id;

                    -- Raise the specific overbooked exception with product details.
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1017,
                        'message', 'Product is overbooked',
                        'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                            'id', product_data.id,
                            'title', product_data.title,
                            'description', product_data.description,
                            'price', product_data.price,
                            'type', product_data.type,
                            'type_title', product_data.type_title,
                            'currency_code', product_data.currency_code
                        ))
                    )::TEXT;
                 END;
            END IF;

            -- Claim the found spot.
            UPDATE eshop.spots
            SET
                order_product_ticket = v_item_to_allocate.order_product_ticket_id,
                occasion = v_occasion_id,
                state = 'ordered',
                secret = NULL,
                secret_expiration_time = NULL,
                updated_at = now()
            WHERE id = v_available_spot_id;

            -- After claiming the spot, check if it should be automatically assigned to a resource.
            DECLARE
                v_is_auto_assign BOOLEAN;
            BEGIN
                -- Get the auto-assignment setting from the pool associated with the context.
                SELECT (ip.data->>'is_auto_resource_assignment')::boolean
                INTO v_is_auto_assign
                FROM public.inventory_contexts ic
                JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
                WHERE ic.id = v_item_to_allocate.inventory_context_id;

                -- If auto-assignment is enabled for this pool, call the assignment function.
                IF v_is_auto_assign IS TRUE THEN
                    PERFORM assign_spot_to_resource(v_available_spot_id, v_item_to_allocate.inventory_context_id);
                END IF;
            END;

        END LOOP;
    END LOOP;
END;
$$;

-- Source: database/functions/inventory/update_product_inventory_contexts.sql
CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts_internal_v1(p_product_id bigint, p_contexts jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion_id BIGINT;
  v_order_id BIGINT;
BEGIN
    -- Get the occasion ID from the product that is being modified.
    SELECT pt.occasion INTO v_occasion_id
    FROM eshop.products p
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE p.id = p_product_id;

    -- If the product is not found, raise an error.
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object(
            'code', 'PI404',
            'message', 'Product with ID ' || p_product_id || ' not found.'
        )::text;
    END IF;

    -- Permission check. This function is expected to throw on failure.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE product=p_product_id));
    PERFORM 1 FROM eshop.products WHERE id=p_product_id FOR UPDATE;
    PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT inventory_pool FROM public.inventory_contexts WHERE id IN
      (SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=p_product_id UNION SELECT (x->>'inventory_context_id')::bigint FROM jsonb_array_elements(p_contexts) x)) ORDER BY id FOR UPDATE;
    PERFORM 1 FROM public.inventory_contexts WHERE id IN
      (SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=p_product_id UNION SELECT (x->>'inventory_context_id')::bigint FROM jsonb_array_elements(p_contexts) x) ORDER BY id FOR UPDATE;
    -- If permission check passes, proceed with the update.
    -- First, remove all existing inventory context associations.
    DELETE FROM eshop.product_inventory_contexts
    WHERE product = p_product_id;

    -- Then, insert the new associations from the provided JSON array.
    IF jsonb_array_length(p_contexts) > 0 THEN
      INSERT INTO eshop.product_inventory_contexts (product, inventory_context, quantity)
      SELECT
        p_product_id,
        (context ->> 'inventory_context_id')::bigint,
        (context ->> 'quantity')::integer
      FROM jsonb_array_elements(p_contexts) AS context;
    END IF;


    -- After updating the product's context associations, re-run allocations
    -- for all orders that contain this product.
    FOR v_order_id IN
      SELECT DISTINCT opt."order"
      FROM eshop.order_product_ticket opt
      WHERE opt.product = p_product_id ORDER BY opt."order"
    LOOP
      -- This will re-evaluate spot allocations for each affected order.
      PERFORM apply_allocations(v_order_id);
    END LOOP;

END;
$$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts(p_product_id bigint,p_contexts jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.update_product_inventory_contexts_client_sync_v1(p_product_id,p_contexts,extensions.gen_random_uuid());
END $$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_inventory_contexts(bigint,jsonb) TO authenticated;


-- Source: database/functions/inventory/update_inventory_pool_bundle.sql
CREATE OR REPLACE FUNCTION update_inventory_pool_bundle(p_bundle_data jsonb)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_pool_data jsonb := p_bundle_data->'pool';
    v_pool_id bigint;
    v_occasion_id bigint;

    -- Context variables
    v_context_data jsonb;
    v_context_id bigint;
    v_context_ids_from_input bigint[] := ARRAY[]::bigint[];

    result jsonb;
BEGIN
    -- Resolve occasion ID from the input data. It's required for both create and update.
    v_occasion_id := (v_pool_data->>'occasion')::bigint;
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'B001', 'message', 'Occasion ID is required.')::text;
    END IF;

    -- Permission check
    IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion.')::text;
    END IF;

    -- 1. Upsert the main inventory_pool record
    v_pool_id := (v_pool_data->>'id')::bigint;

    IF v_pool_id IS NULL THEN
        -- Create a new pool if ID is not provided
        INSERT INTO public.inventory_pools (title, occasion, sellable_capacity, description, type, data, created_at, updated_at)
        VALUES (
            v_pool_data->>'title',
            v_occasion_id,
            (v_pool_data->>'sellable_capacity')::bigint,
            v_pool_data->>'description',
            v_pool_data->>'type',
            v_pool_data->'data',
            now(),
            now()
        ) RETURNING id INTO v_pool_id;
    ELSE
        PERFORM 1 FROM public.inventory_pools WHERE id=v_pool_id AND occasion=v_occasion_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Inventory pool scope mismatch'; END IF;
        PERFORM 1 FROM public.inventory_contexts WHERE inventory_pool=v_pool_id ORDER BY id FOR UPDATE;
        IF (v_pool_data->>'sellable_capacity')::bigint < (SELECT count(*) FROM eshop.spots s JOIN public.inventory_contexts ic ON ic.id=s.inventory_context
          WHERE ic.inventory_pool=v_pool_id AND (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))) THEN
          RAISE EXCEPTION 'INVENTORY_CAPACITY_BELOW_COMMITTED'; END IF;
        -- Update the existing pool
        UPDATE public.inventory_pools
        SET
            title = v_pool_data->>'title',
            sellable_capacity = (v_pool_data->>'sellable_capacity')::bigint,
            description = v_pool_data->>'description',
            type = v_pool_data->>'type',
            data = v_pool_data->'data',
            updated_at = now()
        WHERE id = v_pool_id;
    END IF;

    -- NOTE: Resource and Slot management logic has been removed as requested.

    -- 2. Upsert/Delete Inventory Contexts
    IF jsonb_typeof(p_bundle_data->'contexts') = 'array' THEN
        FOR v_context_data IN SELECT * FROM jsonb_array_elements(p_bundle_data->'contexts')
        LOOP
            v_context_id := (v_context_data->>'id')::bigint;
            IF v_context_id IS NULL THEN
                -- Create new context, now including the 'data' field
                INSERT INTO public.inventory_contexts (inventory_pool, block_date, title, "order", data)
                VALUES (v_pool_id, (v_context_data->>'block_date')::date, v_context_data->>'title', (v_context_data->>'order')::bigint, v_context_data->'data')
                RETURNING id INTO v_context_id;
            ELSE
                -- Update existing context, now including the 'data' field
                UPDATE public.inventory_contexts
                SET
                    block_date = (v_context_data->>'block_date')::date,
                    title = v_context_data->>'title',
                    "order" = (v_context_data->>'order')::bigint,
                    data = v_context_data->'data' -- Added this line
                WHERE id = v_context_id;
            END IF;
            v_context_ids_from_input := array_append(v_context_ids_from_input, v_context_id);
        END LOOP;
        -- Delete contexts that were removed in the UI for this pool
        DELETE FROM public.inventory_contexts WHERE inventory_pool = v_pool_id AND id <> ALL(v_context_ids_from_input);
    END IF;

    -- 3. Create or delete spots for the inventory pool based on its resources and contexts.
    -- The function is executed, and its integer return value is discarded.
    PERFORM adjust_spot_capacity_for_pool(v_pool_id);

    -- Return the fully updated bundle by calling the get function
    RETURN get_inventory_pool_bundle(v_pool_id);
END;
$$ LANGUAGE plpgsql;

-- Source: database/functions/inventory/adjust_spot_capacity_for_pool.sql
CREATE OR REPLACE FUNCTION adjust_spot_capacity_for_pool(p_inventory_pool_id bigint)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_context RECORD;
    v_resource RECORD;
    v_spots_to_create BIGINT;
    v_spots_to_delete BIGINT;
    v_booked_spots_count BIGINT;
    v_total_spots_count BIGINT;
    v_deletable_spot_ids BIGINT[];
    v_net_change INTEGER := 0;
    v_pool_occasion_id BIGINT;
    v_total_pool_capacity BIGINT;
BEGIN
    PERFORM 1 FROM public.inventory_pools WHERE id=p_inventory_pool_id FOR UPDATE;
    PERFORM 1 FROM public.inventory_contexts WHERE inventory_pool=p_inventory_pool_id ORDER BY id FOR UPDATE;
    -- Step 0: Validate input and get occasion ID.
    SELECT occasion INTO v_pool_occasion_id FROM public.inventory_pools WHERE id = p_inventory_pool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'P001', 'message', 'Inventory pool with ID ' || p_inventory_pool_id || ' not found.')::text;
    END IF;

    -- Calculate the total capacity for the entire pool once. This is the target for the generic pool.
    SELECT COALESCE(SUM(capacity), 0) INTO v_total_pool_capacity
    FROM public.resources
    WHERE inventory_pool = p_inventory_pool_id;

    -- =================================================================
    -- Main Synchronization Loop (per context)
    -- =================================================================
    FOR v_context IN
        SELECT id FROM public.inventory_contexts WHERE inventory_pool = p_inventory_pool_id
    LOOP
        -- =============================================================
        -- Part A: Cleanup of RESOURCE-SPECIFIC Spots for this context
        -- =============================================================
        FOR v_resource IN
            SELECT id, capacity FROM public.resources WHERE inventory_pool = p_inventory_pool_id
        LOOP
            -- Count spots for the current resource WITHIN the current context.
            SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND resource = v_resource.id;
            SELECT count(*) INTO v_booked_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND resource = v_resource.id AND order_product_ticket IS NOT NULL;

            IF v_booked_spots_count > v_resource.capacity THEN
                RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'S001',
                    'message', 'Overbooking detected for specific resource. Manual intervention required.',
                    'details', jsonb_build_object(
                        'contextId', v_context.id,
                        'resourceId', v_resource.id,
                        'bookedSpots', v_booked_spots_count,
                        'capacity', v_resource.capacity
                    )
                )::text;
            END IF;

            IF v_total_spots_count > v_resource.capacity THEN
                v_spots_to_delete := v_total_spots_count - v_resource.capacity;
                SELECT array_agg(id) INTO v_deletable_spot_ids FROM (
                    SELECT id FROM eshop.spots
                    WHERE inventory_context = v_context.id AND resource = v_resource.id AND order_product_ticket IS NULL AND (secret IS NULL OR secret_expiration_time<=clock_timestamp())
                    ORDER BY created_at DESC
                    LIMIT v_spots_to_delete
                ) AS sub;

                IF array_length(v_deletable_spot_ids, 1) < v_spots_to_delete THEN
                     RAISE EXCEPTION '%', jsonb_build_object(
                        'code', 'S002',
                        'message', 'Cannot delete excess resource-specific spots. Deletion would require removing a booked spot.',
                        'details', jsonb_build_object(
                            'contextId', v_context.id,
                            'resourceId', v_resource.id
                        )
                    )::text;
                END IF;

                DELETE FROM eshop.spots WHERE id = ANY(v_deletable_spot_ids);
                v_net_change := v_net_change - v_spots_to_delete;
            END IF;
        END LOOP;

        -- =============================================================
        -- Part B: Management of GENERIC Spot Pool for this context
        -- =============================================================
        -- Count total and booked spots for the GENERIC pool (resource IS NULL) within the current context.
        SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id;
        SELECT count(*) INTO v_booked_spots_count FROM eshop.spots WHERE inventory_context = v_context.id AND order_product_ticket IS NOT NULL;

        IF v_booked_spots_count > v_total_pool_capacity THEN
            RAISE EXCEPTION '%', jsonb_build_object(
                'code', 'S003',
                'message', 'Overbooking detected for generic pool. Manual intervention required.',
                'details', jsonb_build_object(
                    'contextId', v_context.id,
                    'bookedSpots', v_booked_spots_count,
                    'capacity', v_total_pool_capacity
                )
            )::text;
        END IF;

        -- DELETION of generic spots
        IF v_total_spots_count > v_total_pool_capacity THEN
            v_spots_to_delete := v_total_spots_count - v_total_pool_capacity;
            SELECT array_agg(id) INTO v_deletable_spot_ids FROM (
                SELECT id FROM eshop.spots
                WHERE inventory_context = v_context.id AND resource IS NULL AND order_product_ticket IS NULL AND (secret IS NULL OR secret_expiration_time<=clock_timestamp())
                ORDER BY created_at DESC
                LIMIT v_spots_to_delete
            ) AS sub;

            IF array_length(v_deletable_spot_ids, 1) < v_spots_to_delete THEN
                 RAISE EXCEPTION '%', jsonb_build_object(
                    'code', 'S004',
                    'message', 'Cannot delete excess generic spots. Deletion would require removing a booked spot.',
                    'details', jsonb_build_object(
                        'contextId', v_context.id
                    )
                )::text;
            END IF;

            DELETE FROM eshop.spots WHERE id = ANY(v_deletable_spot_ids);
            v_net_change := v_net_change - v_spots_to_delete;
        END IF;

        -- CREATION of generic spots
        -- Recount after potential deletion to get the current number.
        SELECT count(*) INTO v_total_spots_count FROM eshop.spots WHERE inventory_context = v_context.id;

        IF v_total_spots_count < v_total_pool_capacity THEN
            v_spots_to_create := v_total_pool_capacity - v_total_spots_count;

            -- Insert the required number of new generic spots.
            -- Per instructions, ONLY occasion and inventory_context are set.
            INSERT INTO eshop.spots (occasion, inventory_context)
            SELECT
                v_pool_occasion_id,
                v_context.id
            FROM generate_series(1, v_spots_to_create);

            v_net_change := v_net_change + v_spots_to_create;
        END IF;
    END LOOP;

    RETURN v_net_change;

END;
$$;

-- Source: database/functions/emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false OR coalesce((v_feature->>'reminder_is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY priority-greatest(0,floor(extract(epoch FROM now()-created_at)/300))::integer,
 (SELECT max(a.created_at) FROM public.email_attempts a JOIN public.email_messages served ON served.message_id=a.message_id WHERE served.organization=m.organization) NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;


-- Source: database/functions/emails/fakturoid_email_gate.sql
-- A Fakturoid checkout is not an accepted order until its proforma exists.
-- Keep its confirmation out of the email worker until checkout finalizes it.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  PERFORM public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'command_id',p_command_id,'ticket_order',p_order_payload,'lang',coalesce(nullif(p_language,''),'cs'),
    'fakturoid_pending',v_await_fakturoid),v_organization,p_occasion,v_unit,
    CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END);

END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_fakturoid_ticket_order_state_v1(p_order_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state INTO v_state FROM eshop.orders o WHERE o.id=p_order_id;
  IF v_state IS NULL THEN
    RAISE no_data_found USING MESSAGE='ticket order not found';
  END IF;
  RETURN v_state;
END;
$$;
REVOKE ALL ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid, p_variable_symbol bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_currency text;
  v_payment_id bigint;
  v_existing_vs bigint;
  v_occasion bigint;
  v_queue_id bigint;
  v_impacts jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='aborted') THEN
    RAISE EXCEPTION 'Acceptance attempt aborted'; END IF;
  SELECT o.state,trim(o.currency_code),o.payment_info,o.occasion,pi.variable_symbol
  INTO v_state,v_currency,v_payment_id,v_occasion,v_existing_vs
  FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
  WHERE o.id=p_order_id FOR UPDATE OF o,pi;
  IF v_state IS NULL OR p_command_id IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid Fakturoid completion';
  END IF;
  IF v_state IN ('ordered','paid') THEN
    RETURN v_existing_vs;
  END IF;
  IF v_state<>'preparing_payment' THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  IF v_currency='CZK' THEN
    UPDATE eshop.payment_info SET variable_symbol=p_variable_symbol
    WHERE id=v_payment_id;
  ELSIF v_currency='EUR' THEN
    IF v_existing_vs IS DISTINCT FROM p_variable_symbol THEN
      RAISE check_violation USING MESSAGE='Fakturoid EUR symbol differs from RF base';
    END IF;
  ELSE
    RAISE check_violation USING MESSAGE='unsupported Fakturoid order currency';
  END IF;
  UPDATE eshop.waitlist_acceptance_attempts SET state='completed',updated_at=clock_timestamp()
   WHERE target_order_id=p_order_id AND command_id=p_command_id AND state='preparing';
  UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
  UPDATE public.email_messages SET target_time=now(),workflow_state='pending',
    data=jsonb_set(data-'fakturoid_pending','{ticket_order,order,payment_info,variable_symbol}',to_jsonb(p_variable_symbol))
  WHERE id=v_queue_id;
  PERFORM public.wake_email_worker();
  SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
  FROM public.occasion_users ou CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component
  WHERE ou.occasion=v_occasion;
  PERFORM public.record_client_sync_commit_v1(v_occasion,
    'fakturoid.order.complete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order_id,'operation','update',
      'safeLabel','Order payment ready','changedFields',
      jsonb_build_array('state','payment_info'))),'{}',v_impacts,'[]',
    'service',NULL);
  RETURN p_variable_symbol;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_occasion bigint;
  v_queue_id bigint;
  v_before_users uuid[];
  v_abort_command uuid := extensions.gen_random_uuid();
  v_hash text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
  IF EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE command_id=p_command_id AND target_order_id=p_order_id AND state='aborted') THEN RETURN; END IF;
  SELECT o.state,o.occasion INTO v_state,v_occasion
  FROM eshop.orders o WHERE o.id=p_order_id FOR UPDATE;
  IF v_state='storno' THEN RETURN; END IF;
  IF v_state IS DISTINCT FROM 'preparing_payment' OR p_command_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
  FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order_id,'reason','fakturoid_failed')::text,'UTF8'),'sha256'),'hex');
  PERFORM public.begin_anonymous_client_mutation_v1(v_abort_command,
    'inventory.order.fakturoid_abort',v_occasion,extensions.gen_random_uuid(),v_hash);
  UPDATE public.email_messages SET workflow_state='cancelled',last_error='fakturoid_aborted' WHERE id=v_queue_id;
  IF NOT public.abort_waitlist_acceptance_internal(p_order_id,p_command_id) THEN
    UPDATE eshop.orders SET state='ordered' WHERE id=p_order_id;
    PERFORM public.update_order_and_tickets_to_storno_221(p_order_id);
  END IF;
  PERFORM public.complete_profile_inventory_membership_mutation_v1(
    v_abort_command,v_occasion,'inventory.order.fakturoid_abort',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',p_order_id,'operation','update','safeLabel','Failed order',
      'changedFields',jsonb_build_array('state','tickets','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order_id),'service');
END;
$$;
REVOKE ALL ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  TO service_role;


-- Source: database/functions/eshop/get_report_ws.sql
CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE r jsonb; invalid_payment boolean;
BEGIN
  WITH scope AS MATERIALIZED (
    SELECT o.id, o.title FROM public.occasions o
    JOIN public.user_info u ON u.organization = o.organization AND u.id = auth.uid()
    WHERE o.link = occasion_link AND public.get_is_editor_order_view_on_occasion(o.id)
  ), orders_scope AS MATERIALIZED (
    SELECT o.* FROM eshop.orders o JOIN scope s ON s.id = o.occasion
  ), payments AS MATERIALIZED (
    SELECT p.* FROM eshop.payment_info p
    WHERE p.id IN (SELECT payment_info FROM orders_scope)
  ), invalid AS (
    SELECT EXISTS (SELECT 1 FROM payments p JOIN eshop.orders o ON o.payment_info = p.id
      WHERE o.occasion IS DISTINCT FROM (SELECT id FROM scope)
         OR o.currency_code IS DISTINCT FROM p.currency_code) AS value
  ), transactions_scope AS MATERIALIZED (
    SELECT t.* FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info
    WHERE t.currency=p.currency_code
  ), order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM orders_scope GROUP BY 1,2
  ), payment_days AS (
    SELECT date::date AS day,currency::text AS currency,
      coalesce(sum(amount) FILTER (WHERE amount>0),0)::text AS received,
      coalesce(-sum(amount) FILTER (WHERE amount<0),0)::text AS returned
    FROM transactions_scope GROUP BY 1,2
  ), manual AS (
    SELECT t.payment_info, sum(t.amount) FILTER (WHERE t.transaction_type = 'manual' AND t.amount > 0) AS received
    FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info GROUP BY t.payment_info
  ), order_money AS (
    SELECT currency_code AS currency, sum(coalesce(price,0)) AS value
    FROM orders_scope GROUP BY currency_code
  ), payment_money AS (
    SELECT p.currency_code AS currency, sum(coalesce(p.paid,0)) AS received,
      sum(coalesce(p.returned,0)) AS returned, sum(coalesce(m.received,0)) AS manual,
      bool_or(p.deposit_amount IS NOT NULL) AS deposits,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN least(coalesce(p.paid,0),p.deposit_amount) ELSE 0 END) AS deposit,
      sum(CASE WHEN p.deposit_amount IS NOT NULL THEN greatest(coalesce(p.paid,0)-p.deposit_amount,0) ELSE 0 END) AS beyond
    FROM payments p LEFT JOIN manual m ON m.payment_info=p.id GROUP BY p.currency_code
  ), money AS (
    SELECT coalesce(o.currency,p.currency)::text AS currency, coalesce(o.value,0) AS value,
      coalesce(p.received,0) AS received, coalesce(p.returned,0) AS returned,
      coalesce(p.manual,0) AS manual, coalesce(p.deposits,false) AS deposits,
      coalesce(p.deposit,0) AS deposit, coalesce(p.beyond,0) AS beyond
    FROM order_money o FULL JOIN payment_money p USING(currency)
  ), ticket_scope AS (
    SELECT t.* FROM eshop.tickets t JOIN scope s ON s.id=t.occasion
    WHERE EXISTS (SELECT 1 FROM eshop.order_product_ticket i WHERE i.ticket=t.id)
  ), valid_orders AS MATERIALIZED (
    SELECT * FROM orders_scope WHERE state IS DISTINCT FROM 'storno' AND state IS DISTINCT FROM 'waitlisted'
  ), valid_tickets AS MATERIALIZED (
    SELECT t.* FROM ticket_scope t
    WHERE t.state IS DISTINCT FROM 'storno' AND EXISTS (
      SELECT 1 FROM eshop.order_product_ticket i JOIN valid_orders o ON o.id=i."order"
      WHERE i.ticket=t.id
    )
  ), valid_order_days AS (
    SELECT (created_at AT TIME ZONE 'Europe/Prague')::date AS day,currency_code::text AS currency,count(*) AS count
    FROM valid_orders GROUP BY 1,2
  ), order_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM orders_scope GROUP BY 1
  ), ticket_states AS (
    SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM ticket_scope GROUP BY 1
  ), spots AS (
    SELECT count(*) AS total,count(*) FILTER (WHERE order_product_ticket IS NOT NULL) AS occupied,
      count(*) FILTER (WHERE order_product_ticket IS NULL) AS free
    FROM eshop.spots WHERE occasion IN (SELECT id FROM scope)
  ), products AS (
    SELECT p.id::text AS product_id,coalesce(p.title,'') AS product_title,
      pt.id::text AS type_id,pt.title AS type_title,count(*) AS confirmed_count
    FROM orders_scope o JOIN eshop.order_product_ticket i ON i."order"=o.id
    JOIN eshop.products p ON p.id=i.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
    WHERE o.state IN ('paid','sent','used') GROUP BY p.id,pt.id
  ), warnings AS (
    SELECT 'missing_order_price' AS code,count(*) AS count FROM orders_scope WHERE price IS NULL AND state IS DISTINCT FROM 'waitlisted' HAVING count(*)>0
    UNION ALL SELECT 'transaction_currency_mismatch',count(*) FROM eshop.transactions t JOIN payments p ON p.id=t.payment_info WHERE t.currency<>p.currency_code HAVING count(*)>0
    UNION ALL SELECT 'negative_other_received',count(*) FROM money WHERE received-manual<0 HAVING count(*)>0
  )
  SELECT jsonb_build_object(
    'schema_version',1,'occasion',jsonb_build_object('id',s.id::text,'title',coalesce(s.title,'')),
    'generated_at',to_char(statement_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'spots',(SELECT to_jsonb(spots) FROM spots),
    'orders',jsonb_build_object('total',(SELECT count(*) FROM orders_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM order_states x),'[]'::jsonb)),
    'tickets',jsonb_build_object('total',(SELECT count(*) FROM ticket_scope),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM ticket_states x),'[]'::jsonb)),
    'valid',jsonb_build_object(
      'orders',jsonb_build_object('total',(SELECT count(*) FROM valid_orders),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_orders GROUP BY 1) x),'[]'::jsonb)),
      'tickets',jsonb_build_object('total',(SELECT count(*) FROM valid_tickets),'by_state',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY state) FROM (SELECT coalesce(state,'unknown') AS state,count(*) AS count FROM valid_tickets GROUP BY 1) x),'[]'::jsonb)),
      'order_days',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM valid_order_days d),'[]'::jsonb)
    ),
    'money_by_currency',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'currency',currency,'current_order_value',value::text,'received',received::text,'returned',returned::text,
      'net_received',(received-returned)::text,'manual_received',manual::text,'other_received',(received-manual)::text,
      'has_deposits',deposits,'deposit_received_gross',deposit::text,'beyond_deposit_received_gross',beyond::text
    ) ORDER BY currency) FROM money),'[]'::jsonb),
    'timeline',jsonb_build_object(
      'order_timezone','Europe/Prague','payment_date_basis','transaction_date',
      'orders',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day) FROM order_days d),'[]'::jsonb),
      'payments',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY day,currency) FROM payment_days d),'[]'::jsonb)
    ),
    'products',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY type_id,product_id) FROM products p),'[]'::jsonb),
    'warnings',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY code) FROM warnings w),'[]'::jsonb)
  ), invalid.value INTO r,invalid_payment FROM scope s CROSS JOIN invalid;
  IF r IS NULL THEN RETURN jsonb_build_object('code',403,'message','Report unavailable or access denied.'); END IF;
  IF invalid_payment THEN RETURN jsonb_build_object('code',409,'message','Report payment allocation is inconsistent.'); END IF;
  RETURN jsonb_build_object('code',200,'data',public.format_occasion_report_text(r),'report',r);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code',500,'message','Report could not be generated.');
END;
$$;
REVOKE ALL ON FUNCTION public.get_report_ws(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_report_ws(text) TO authenticated;


-- Source: database/functions/eshop_forms/get_forms_by_link.sql
CREATE OR REPLACE FUNCTION public.get_forms_by_link(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE link = occasion_link
      AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());

    -- Step 2: If no occasion is found, throw a 'no_data_found' exception.
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link USING ERRCODE = 'PGRST001'; -- Custom error for PostgREST
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- If not, throw an 'insufficient_privilege' exception.
    IF NOT (get_is_editor_view_on_occasion(v_occasion_id) OR get_is_editor_order_view_on_occasion(v_occasion_id)) THEN
        RAISE EXCEPTION 'User is not authorized to view forms for this occasion.' USING ERRCODE = '42501'; -- insufficient_privilege
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The order statistics are nested within a 'stats' JSON object.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'capacity',public.get_form_capacity_snapshot_internal(f.id),'registrationMode',public.get_form_registration_mode_internal(f.id),
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'stats', jsonb_build_object(
                'total', COALESCE(order_stats.total, 0),
                'storno', COALESCE(order_stats.storno, 0),
                'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
                'ordered', COALESCE(order_stats.ordered, 0)
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    LEFT JOIN (
        -- This subquery calculates all required counts in a single pass over the orders table.
        SELECT
            (data->>'form')::uuid AS form_key,
            COUNT(*) AS total,
            COUNT(*) FILTER (WHERE state = 'storno') AS storno,
            COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
            COUNT(*) FILTER (WHERE state = 'ordered') AS ordered
        FROM eshop.orders
        WHERE data->>'form' IS NOT NULL -- Ensure the key exists before casting
        GROUP BY form_key
    ) AS order_stats ON f.key = order_stats.form_key
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, ensure an empty JSON array is returned.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the data directly.
    RETURN forms_data;
END;
$$;


-- Source: database/functions/eshop_forms/get_form.sql
CREATE OR REPLACE FUNCTION public.get_form(form_key uuid)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE link text;
BEGIN
 SELECT f.link INTO link FROM public.forms f WHERE key=form_key;
 IF link IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form not found'); END IF;
 RETURN public.get_form_by_link(link);
END $$;


-- Source: database/functions/eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  unit_id BIGINT;
  ou_record RECORD;
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info
    INTO order_oc, payment_info_id
    FROM eshop.orders
   WHERE id = order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Deletion belongs to unit managers and editors, including cancelled orders.
  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = order_oc;

  IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(unit_id)
      OR public.get_is_editor_on_unit(unit_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager or editor required';
  END IF;
  -- The queue send gate locks global capacity before an order. Deletion must
  -- acquire that outer lock before the form/order helper to avoid inversion.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=order_id AND state IN ('waitlisted','preparing_payment'))
    OR EXISTS(SELECT 1 FROM eshop.waitlist_offers offer WHERE offer.order_id=delete_order_internal_v1.order_id)
    OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=delete_order_internal_v1.order_id)
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts WHERE target_order_id=delete_order_internal_v1.order_id
      OR source_order_id=delete_order_internal_v1.order_id) THEN
    RAISE EXCEPTION 'ORDER_HAS_WAITLIST_HISTORY'; END IF;
  DELETE FROM eshop.order_participants WHERE current_order_id=order_id;
  DELETE FROM eshop.form_participant_backfill_issues issue WHERE issue.order_id=delete_order_internal_v1.order_id;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=order_id);
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(unit_id)
      OR public.get_is_editor_on_unit(unit_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager or editor required';
  END IF;

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_client_sync_v1(
  p_order bigint,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_removed_users uuid[]; v_remaining_users uuid[];
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT o.occasion,oc.unit INTO v_occasion,v_unit FROM eshop.orders o
    JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT (public.get_is_manager_on_unit(v_unit) OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.delete',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
  PERFORM public.lock_activity_aggregate_internal_v1(v_occasion);
  IF auth.uid() IS NULL OR NOT (public.get_is_manager_on_unit(v_unit) OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager or editor required'; END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_removed_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt."order"=p_order;
  PERFORM public.delete_order_internal_v1(p_order);
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=v_occasion
    AND s.user_id=ANY(v_removed_users);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed_users) id));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_remaining_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  IF cardinality(v_removed_users)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=v_occasion;
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,v_occasion,
    'inventory.order.delete',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order,'operation','delete',
      'safeLabel','Order','changedFields',jsonb_build_array(
        'tickets','membership','allocations'))),v_remaining_users,v_public,v_dirty,
    jsonb_build_object('orderId',p_order,'removedUsers',cardinality(v_removed_users)));
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_client_sync_v1(bigint,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;


-- Source: database/functions/seed/crons.sql
CREATE OR REPLACE FUNCTION setup_crons(p_project_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $func$
BEGIN
  -- Security Check
  IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
      RAISE EXCEPTION 'Access Denied: Service role required.';
  END IF;

  -- Schedule the apply_planned_changes cron job (runs every minute)
  PERFORM cron.schedule(
    'apply_planned_changes',
    '*/1 * * * *',
    'SELECT apply_planned_changes()'
  );

  -- BankSync owns bank polling. This job only recovers durable control intents.
  PERFORM cron.schedule('festapp_canonical_bank_sync_reconcile','*/5 * * * *',
    format($$SELECT net.http_post(url:='%s/functions/v1/bank-sync-reconcile',
      body:=jsonb_build_object('requestSecret',public.generate_request_secret(3600)),
      timeout_milliseconds:=360000)$$,p_project_url));

  PERFORM cron.schedule('festapp_canonical_waitlist_expiry','*/1 * * * *','SELECT public.expire_waitlist_offers(100)');
  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
END;
$func$;


-- Source: database/functions/eshop_waitlist/client_sync.sql
INSERT INTO public.client_sync_component_sources
 (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
 (1,'private_inventory','public.forms','forms.occasion',ARRAY['participant_capacity','waitlist_enabled','show_remaining_capacity','waitlist_offer_duration_seconds','capacity_revision'],
  ARRAY['update_form_client_sync_v1','execute_waitlist_command_client_sync_v1','expire_waitlist_offers','storno_tickets_client_sync_v1','storno_order_client_sync_v1'], '{}','migrate','form_capacity_factory',false),
 (1,'private_inventory','eshop.orders','orders.occasion',ARRAY['state','source_waitlist_order_id'],
  ARRAY['create_ticket_order_client_sync_v1','execute_waitlist_command_client_sync_v1','abort_fakturoid_ticket_order_v1','complete_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_order_factory',false),
 (1,'private_inventory','eshop.order_participants','form -> forms.occasion',ARRAY['current_order_id','origin_order_id','form_id','answers','ticket_id','lifecycle','queue_at'],
  ARRAY['create_ticket_order_client_sync_v1','execute_waitlist_command_client_sync_v1','expire_waitlist_offers','storno_tickets_client_sync_v1','storno_order_client_sync_v1','abort_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_participant_factory',false),
 (1,'private_inventory','eshop.waitlist_offers','form -> forms.occasion',ARRAY['order_id','form_id','expires_at','revision'],
  ARRAY['execute_waitlist_command_client_sync_v1'], '{}','migrate','waitlist_offer_factory',false),
 (1,'private_inventory','eshop.waitlist_offer_slots','form -> forms.occasion',ARRAY['offer_id','participant_id','outcome','resulting_order_id'],
  ARRAY['execute_waitlist_command_client_sync_v1','expire_waitlist_offers','abort_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_slot_factory',false)
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 disposition=excluded.disposition,
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
-- Capabilities and encrypted delivery sources never belong to a client projection.


-- Source: database/functions/eshop/product_write_permissions.sql
-- Product configuration and deletion must use the authorized, receipted
-- domain facades. Direct client DML would bypass product limits and type/layout
-- usage guards, including when the form capacity feature is disabled.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON eshop.product_types,eshop.products FROM anon,authenticated;
