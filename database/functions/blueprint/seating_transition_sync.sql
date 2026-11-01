WITH readiness AS MATERIALIZED (
 SELECT coalesce(bool_and(cutover_ready),false) ready FROM public.client_sync_component_sources WHERE registry_version=1
)
INSERT INTO public.client_sync_component_sources
(registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
(1,'private_inventory','public.form_seating_transitions','form_seating_transitions.occasion',ARRAY['form','blueprint','state','revision'],
 ARRAY['save_occasion_client_sync_v1','start_seating_configuration','cancel_seating_configuration','set_ticket_seat_assignments','publish_seating_transitions'],'{}','migrate','database/tests/blueprint/seating_transition_test.sql',(SELECT ready FROM readiness)),
(1,'private_inventory','eshop.spots','spots.occasion',ARRAY['order_product_ticket','state'],
 ARRAY['set_ticket_seat_assignments'],'{}','migrate','database/tests/blueprint/seating_assignment_test.sql',(SELECT ready FROM readiness)),
(1,'private_inventory','public.forms','forms.occasion',ARRAY['blueprint','participant_capacity','waitlist_enabled','capacity_revision'],
 ARRAY['publish_seating_transitions','save_occasion_client_sync_v1'],'{}','migrate','database/tests/blueprint/seating_publication_test.sql',(SELECT ready FROM readiness))
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
