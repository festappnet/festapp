INSERT INTO public.client_sync_component_sources
 (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
 (1,'private_inventory','public.forms','forms.occasion',ARRAY['participant_capacity','waitlist_enabled','show_remaining_capacity','waitlist_offer_duration_seconds','capacity_revision'],
  ARRAY['update_form_client_sync_v1','execute_waitlist_command_client_sync_v1','expire_waitlist_offers','storno_tickets_client_sync_v1','storno_order_client_sync_v1'], '{}','migrate','form_capacity_factory',false),
 (1,'private_inventory','eshop.orders','orders.occasion',ARRAY['state','source_waitlist_order_id'],
  ARRAY['create_ticket_order_client_sync_v1','execute_waitlist_command_client_sync_v1','abort_fakturoid_ticket_order_v1','complete_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_order_factory',false),
 (1,'private_inventory','eshop.tickets','tickets.occasion',ARRAY['state','data','waitlist_queue_at'],
  ARRAY['create_ticket_order_client_sync_v1','execute_waitlist_command_client_sync_v1','expire_waitlist_offers','storno_tickets_client_sync_v1','storno_order_client_sync_v1','abort_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_ticket_factory',false),
 (1,'private_inventory','eshop.waitlist_offers','form -> forms.occasion',ARRAY['order_id','form_id','expires_at','revision'],
  ARRAY['execute_waitlist_command_client_sync_v1'], '{}','migrate','waitlist_offer_factory',false),
 (1,'private_inventory','eshop.waitlist_offer_slots','form -> forms.occasion',ARRAY['offer_id','ticket_id','outcome','resulting_order_id'],
  ARRAY['execute_waitlist_command_client_sync_v1','expire_waitlist_offers','abort_fakturoid_ticket_order_v1'], '{}','migrate','waitlist_slot_factory',false)
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 disposition=excluded.disposition,
 tracked_columns=ARRAY(SELECT DISTINCT x FROM unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns) x WHERE x<>'participant_id'),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
-- Capabilities and encrypted delivery sources never belong to a client projection.
