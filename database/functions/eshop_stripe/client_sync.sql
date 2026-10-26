-- Provider facts invalidate the existing private inventory projection. This
-- registry never exposes raw tables, capabilities or sealed payment sources.
INSERT INTO public.client_sync_component_sources
 (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
 (1,'private_inventory','public.forms','forms.occasion',ARRAY['data'],
  ARRAY['complete_stripe_connection_flow_internal'],'{}','migrate','database/tests/eshop/stripe/connections_test.sql',false),
 (1,'private_inventory','eshop.orders','orders.occasion',ARRAY['state','email_payment_version'],
  ARRAY['ingest_stripe_payment_internal','decide_stripe_partial_refund_client_sync_v1'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false),
 (1,'private_inventory','eshop.tickets','tickets.occasion',ARRAY['state'],
  ARRAY['ingest_stripe_payment_internal','decide_stripe_partial_refund_client_sync_v1'],'{}','migrate','database/tests/eshop/stripe/refund_decisions_test.sql',false),
 (1,'private_inventory','eshop.stripe_payment_movements','attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion',
  ARRAY['provider_id','kind','amount_minor','currency','occurred_at'],
  ARRAY['ingest_stripe_payment_internal'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false),
 (1,'private_inventory','eshop.stripe_disputes','attempt_id -> stripe_checkout_attempts.order_id -> orders.occasion',
  ARRAY['provider_id','amount_minor','status','observed_at'],
  ARRAY['ingest_stripe_payment_internal'],'{}','migrate','database/tests/eshop/stripe/create_order_test.sql',false)
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
