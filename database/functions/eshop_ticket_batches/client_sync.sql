-- New sources inherit the installed global cutover phase. A fresh additive
-- bootstrap remains inactive; a fully activated production registry stays ready.
WITH readiness AS MATERIALIZED (
 SELECT coalesce(bool_and(cutover_ready),false) AS inherited_ready
 FROM public.client_sync_component_sources WHERE registry_version=1
)
INSERT INTO public.client_sync_component_sources
 (registry_version,component,source_relation,scope_resolver,tracked_columns,canonical_writers,legacy_writers,disposition,test_factory,cutover_ready)
VALUES
 (1,'private_inventory','eshop.ticket_batches','ticket_batches.occasion',ARRAY['stock_order_id','snapshot','manifest_hash'],
 ARRAY['create_ticket_batch_client_sync_v1','complete_ticket_batch_resources_internal'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness)),
 (1,'private_inventory','eshop.ticket_batch_items','batch_id -> ticket_batches.occasion',ARRAY['ticket_id','ordinal','sale_order_id'],
 ARRAY['create_ticket_batch_client_sync_v1','sell_ticket_batch_items_client_sync_v1','void_ticket_batch_items_client_sync_v1'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness)),
 (1,'private_inventory','eshop.ticket_batch_document_parts','batch_id -> ticket_batches.occasion',ARRAY['state','content_digest','byte_count'],
 ARRAY['complete_ticket_batch_resources_internal','claim_ticket_batch_document','complete_ticket_batch_document_internal','fail_ticket_batch_document_internal'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness)),
 (1,'private_inventory','eshop.orders','orders.occasion',ARRAY['state','data'],
 ARRAY['create_ticket_batch_client_sync_v1','sell_ticket_batch_items_client_sync_v1'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness)),
 (1,'private_inventory','eshop.order_product_ticket','order -> orders.occasion',ARRAY['order','ticket','product'],
 ARRAY['create_ticket_batch_client_sync_v1','sell_ticket_batch_items_client_sync_v1','void_ticket_batch_items_client_sync_v1'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness)),
 (1,'private_inventory','eshop.tickets','tickets.occasion',ARRAY['state'],
 ARRAY['create_ticket_batch_client_sync_v1','sell_ticket_batch_items_client_sync_v1','void_ticket_batch_items_client_sync_v1'],'{}','migrate','database/tests/eshop/ticket_batches/lifecycle_test.sql',(SELECT inherited_ready FROM readiness))
ON CONFLICT(registry_version,component,source_relation) DO UPDATE SET
 tracked_columns=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.tracked_columns||excluded.tracked_columns)),
 canonical_writers=ARRAY(SELECT DISTINCT unnest(public.client_sync_component_sources.canonical_writers||excluded.canonical_writers));
