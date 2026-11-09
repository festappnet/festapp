-- The participant-based slot table was retired and then recreated for tickets.
-- regclass keeps the old OID after DROP; remove only that exact obsolete source.
-- Keep the live ticket-based registration and all unrelated inventory sources.
DELETE FROM public.client_sync_component_sources
WHERE registry_version = 1
  AND component = 'private_inventory'
  AND scope_resolver = 'form -> forms.occasion'
  AND test_factory = 'waitlist_slot_factory'
  AND tracked_columns = ARRAY['offer_id','participant_id','outcome','resulting_order_id']::text[]
  AND source_relation IS DISTINCT FROM to_regclass('eshop.waitlist_offer_slots');
