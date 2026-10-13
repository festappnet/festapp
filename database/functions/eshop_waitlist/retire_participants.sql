-- Forward correction is safe only before the rejected model has live customers.
-- On a canonical bootstrap/reload the rejected table is absent: do nothing to
-- existing ticket-based offers or journals.
DO $$ BEGIN
 IF to_regclass('eshop.order_participants') IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE state='waitlisted')
  OR EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots) OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts) THEN
   RAISE EXCEPTION 'Canonical ticket cutover requires an unused waitlist deployment';
  END IF;
  DELETE FROM public.client_sync_component_sources WHERE source_relation='eshop.order_participants'::regclass;
  DROP TABLE eshop.waitlist_acceptance_attempts;
  DROP TABLE eshop.waitlist_offer_slots;
  DROP TABLE eshop.form_participant_backfill_issues;
  DROP TABLE eshop.order_participants;
 END IF;
END $$;
DROP FUNCTION IF EXISTS public.snapshot_waitlist_participants_internal(bigint);
DROP FUNCTION IF EXISTS public.get_effective_waitlist_participant_lifecycle_internal(uuid);
DROP FUNCTION IF EXISTS public.normalize_form_participant_answers_internal(bigint,jsonb);
DROP FUNCTION IF EXISTS public.extract_participant_answers_internal(bigint,jsonb);
