-- Effective pre-change RLS expressions, delegated to canonical operation owners.
ALTER POLICY "demo_read_fence" ON "eshop"."bank_account_requests"
  USING ((((NOT demo_entity_is_protected('bank'::text, bank_account)) OR ((NOT is_demo_bank_account(bank_account)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_account_requests.bank_account) AND can_read_orders(demo_bank.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT demo_entity_is_protected('order'::text, "order")) OR (EXISTS ( SELECT 1
   FROM eshop.orders demo_row
  WHERE ((demo_row.id = bank_account_requests."order") AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."bank_account_users"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account)) OR ((NOT is_demo_bank_account(bank_account)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_account_users.bank_account) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_bank_read" ON "eshop"."bank_accounts"
  USING ((EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_accounts.id) AND can_read_orders(demo_bank.occasion)))));
ALTER POLICY "demo_read_fence" ON "eshop"."bank_accounts"
  USING (((NOT is_demo_bank_account(id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_accounts.id) AND can_read_orders(demo_bank.occasion))))));
ALTER POLICY "demo_read_fence" ON "eshop"."bank_sync_account_aliases"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account_id)) OR ((NOT is_demo_bank_account(bank_account_id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_sync_account_aliases.bank_account_id) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."bank_sync_connections"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account_id)) OR ((NOT is_demo_bank_account(bank_account_id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_sync_connections.bank_account_id) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."bank_sync_operations"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account_id)) OR ((NOT is_demo_bank_account(bank_account_id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = bank_sync_operations.bank_account_id) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."blueprints"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "eshop"."order_product_ticket"
  USING ((((NOT demo_entity_is_protected('order'::text, "order")) OR (EXISTS ( SELECT 1
   FROM eshop.orders demo_row
  WHERE ((demo_row.id = order_product_ticket."order") AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('product'::text, product)) OR (EXISTS ( SELECT 1
   FROM eshop.products demo_row
  WHERE ((demo_row.id = order_product_ticket.product) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('ticket'::text, ticket)) OR (EXISTS ( SELECT 1
   FROM eshop.tickets demo_row
  WHERE ((demo_row.id = order_product_ticket.ticket) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."orders"
  USING ((((NOT demo_entity_is_protected('form'::text, form)) OR (EXISTS ( SELECT 1
   FROM forms demo_row
  WHERE ((demo_row.id = orders.form) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT demo_entity_is_protected('payment'::text, payment_info)) OR (EXISTS ( SELECT 1
   FROM eshop.payment_info demo_payment
  WHERE ((demo_payment.id = orders.payment_info) AND ((NOT is_demo_bank_account(demo_payment.bank_account)) OR (EXISTS ( SELECT 1
           FROM demo_occasions demo_bank
          WHERE ((demo_bank.bank_account = demo_payment.bank_account) AND can_read_orders(demo_bank.occasion)))))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."orders_history"
  USING (((NOT demo_entity_is_protected('order'::text, "order")) OR (EXISTS ( SELECT 1
   FROM eshop.orders demo_row
  WHERE ((demo_row.id = orders_history."order") AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."payment_info"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account)) OR ((NOT is_demo_bank_account(bank_account)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = payment_info.bank_account) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."planned_changes"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "eshop"."product_inventory_contexts"
  USING ((((NOT demo_entity_is_protected('product'::text, product)) OR (EXISTS ( SELECT 1
   FROM eshop.products demo_row
  WHERE ((demo_row.id = product_inventory_contexts.product) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('context'::text, inventory_context)) OR (EXISTS ( SELECT 1
   FROM (inventory_contexts demo_context
     JOIN inventory_pools demo_pool ON ((demo_pool.id = demo_context.inventory_pool)))
  WHERE ((demo_context.id = product_inventory_contexts.inventory_context) AND ((NOT is_demo_occasion(demo_pool.occasion)) OR can_read_orders(demo_pool.occasion))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."product_price_waves"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "eshop"."product_types"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "eshop"."products"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "eshop"."spots"
  USING ((((NOT demo_entity_is_protected('context'::text, inventory_context)) OR (EXISTS ( SELECT 1
   FROM (inventory_contexts demo_context
     JOIN inventory_pools demo_pool ON ((demo_pool.id = demo_context.inventory_pool)))
  WHERE ((demo_context.id = spots.inventory_context) AND ((NOT is_demo_occasion(demo_pool.occasion)) OR can_read_orders(demo_pool.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT demo_entity_is_protected('product'::text, product)) OR (EXISTS ( SELECT 1
   FROM eshop.products demo_row
  WHERE ((demo_row.id = spots.product) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('resource'::text, resource)) OR (EXISTS ( SELECT 1
   FROM resources demo_row
  WHERE ((demo_row.id = spots.resource) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."tickets"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_bank_transaction_read" ON "eshop"."transactions"
  USING ((EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = transactions.bank_account_id) AND can_read_orders(demo_bank.occasion)))));
ALTER POLICY "demo_read_fence" ON "eshop"."transactions"
  USING ((((NOT demo_entity_is_protected('bank'::text, bank_account_id)) OR ((NOT is_demo_bank_account(bank_account_id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = transactions.bank_account_id) AND can_read_orders(demo_bank.occasion)))))) AND ((NOT demo_entity_is_protected('payment'::text, payment_info)) OR (EXISTS ( SELECT 1
   FROM eshop.payment_info demo_payment
  WHERE ((demo_payment.id = transactions.payment_info) AND ((NOT is_demo_bank_account(demo_payment.bank_account)) OR (EXISTS ( SELECT 1
           FROM demo_occasions demo_bank
          WHERE ((demo_bank.bank_account = demo_payment.bank_account) AND can_read_orders(demo_bank.occasion)))))))))));
ALTER POLICY "demo_read_fence" ON "eshop"."transactions_parser_log"
  USING (((NOT demo_entity_is_protected('bank'::text, bank_account_id)) OR ((NOT is_demo_bank_account(bank_account_id)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = transactions_parser_log.bank_account_id) AND can_read_orders(demo_bank.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."unit_bank_accounts"
  USING ((((NOT demo_entity_is_protected('bank'::text, bank_account)) OR ((NOT is_demo_bank_account(bank_account)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = unit_bank_accounts.bank_account) AND can_read_orders(demo_bank.occasion)))))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "eshop"."waitlist_capabilities"
  USING (((NOT demo_entity_is_protected('form'::text, form_id)) OR (EXISTS ( SELECT 1
   FROM forms demo_row
  WHERE ((demo_row.id = waitlist_capabilities.form_id) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."waitlist_offer_slots"
  USING (((NOT demo_entity_is_protected('form'::text, form_id)) OR (EXISTS ( SELECT 1
   FROM forms demo_row
  WHERE ((demo_row.id = waitlist_offer_slots.form_id) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "eshop"."waitlist_offers"
  USING (((NOT demo_entity_is_protected('form'::text, form_id)) OR (EXISTS ( SELECT 1
   FROM forms demo_row
  WHERE ((demo_row.id = waitlist_offers.form_id) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."activities"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."cleaning_public_state"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."cleaning_reports"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."client_commits"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."client_mutation_receipts"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."client_sync_private_scopes"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."email_messages"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."email_templates"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."email_wrappers"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."event_feedback"
  USING ((((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_feedback.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion)))));
ALTER POLICY "demo_read_fence" ON "public"."event_groups"
  USING ((((NOT demo_entity_is_protected('event'::text, event_child)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_groups.event_child) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('event'::text, event_parent)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_groups.event_parent) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion))))))));
ALTER POLICY "demo_read_fence" ON "public"."event_public_state"
  USING ((((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_public_state.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion)))));
ALTER POLICY "demo_read_fence" ON "public"."event_roles"
  USING (((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_roles.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."event_speakers"
  USING (((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_speakers.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."event_users"
  USING (((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_users.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."event_users_saved"
  USING (((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = event_users_saved.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "Enable delete for editors" ON "public"."events"
  USING (can_write_schedule(occasion));
ALTER POLICY "Enable insert for editors" ON "public"."events"
  WITH CHECK (can_write_schedule(occasion));
ALTER POLICY "Enable select for editors" ON "public"."events"
  USING (can_read_schedule_editor(occasion));
ALTER POLICY "Enable update for editors" ON "public"."events"
  USING (can_write_schedule(occasion))
  WITH CHECK (can_write_schedule(occasion));
ALTER POLICY "demo_read_fence" ON "public"."events"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."exclusive_events"
  USING (((NOT demo_entity_is_protected('event'::text, event)) OR (EXISTS ( SELECT 1
   FROM events demo_row
  WHERE ((demo_row.id = exclusive_events.event) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."exclusive_groups"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."form_fields"
  USING (((NOT demo_entity_is_protected('form'::text, form)) OR (EXISTS ( SELECT 1
   FROM forms demo_row
  WHERE ((demo_row.id = form_fields.form) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."forms"
  USING ((((NOT demo_entity_is_protected('bank'::text, bank_account)) OR ((NOT is_demo_bank_account(bank_account)) OR (EXISTS ( SELECT 1
   FROM demo_occasions demo_bank
  WHERE ((demo_bank.bank_account = forms.bank_account) AND can_read_orders(demo_bank.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion)))));
ALTER POLICY "demo_read_fence" ON "public"."images"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "Enable all for editors" ON "public"."information"
  USING (can_write_information(occasion))
  WITH CHECK (can_write_information(occasion));
ALTER POLICY "Enable delete for editors" ON "public"."information"
  USING (can_write_information(occasion));
ALTER POLICY "Enable insert for editors" ON "public"."information"
  WITH CHECK (can_write_information(occasion));
ALTER POLICY "Enable select for editors" ON "public"."information"
  USING (can_read_information_editor_bundle(occasion));
ALTER POLICY "Enable update for editors" ON "public"."information"
  USING (can_write_information(occasion))
  WITH CHECK (can_write_information(occasion));
ALTER POLICY "demo_read_fence" ON "public"."information"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."information_hidden"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."inventory_contexts"
  USING (((NOT demo_entity_is_protected('pool'::text, inventory_pool)) OR (EXISTS ( SELECT 1
   FROM inventory_pools demo_row
  WHERE ((demo_row.id = inventory_contexts.inventory_pool) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."inventory_pools"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."log_emails"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."log_notifications"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "Enable delete for editors" ON "public"."news"
  USING (can_write_news(occasion));
ALTER POLICY "Enable insert for editors" ON "public"."news"
  WITH CHECK (can_write_news(occasion));
ALTER POLICY "Enable update for editors" ON "public"."news"
  USING (can_write_news(occasion))
  WITH CHECK (can_write_news(occasion));
ALTER POLICY "demo_read_fence" ON "public"."news"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."news_notification_outbox"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "Enable all for managers" ON "public"."occasion_users"
  USING (public.can_manage_occasion_participants(occasion))
  WITH CHECK (public.can_manage_occasion_participants(occasion));
ALTER POLICY "demo_read_fence" ON "public"."occasion_users"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT demo_entity_is_protected('ticket'::text, ticket)) OR (EXISTS ( SELECT 1
   FROM eshop.tickets demo_row
  WHERE ((demo_row.id = occasion_users.ticket) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion))))))));
-- Rebind the existing read phase; do not install or bypass its compatibility gate.
DO $authorization_context_read_phase$
DECLARE policy_row record;
BEGIN
 SELECT polcmd,polpermissive,polroles INTO policy_row FROM pg_policy
 WHERE polrelid='public.occasions'::regclass AND polname='data_security_occasion_context_read';
 IF FOUND THEN
  IF policy_row.polcmd<>'r' OR NOT policy_row.polpermissive OR
     policy_row.polroles<>ARRAY['authenticated'::regrole::oid] THEN
   RAISE EXCEPTION 'Unexpected occasion context read-policy contract'; END IF;
  ALTER POLICY "data_security_occasion_context_read" ON "public"."occasions"
  USING (public.can_read_occasion_context_row(id));
 ELSIF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261018102000') THEN
  RAISE EXCEPTION 'Read-ACL phase is recorded but its context policy is missing';
 END IF;
END $authorization_context_read_phase$;
ALTER POLICY "demo_read_fence" ON "public"."path_groups"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."place_types"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."places"
  USING ((((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."reception_registrations"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."resource_slots"
  USING (((NOT demo_entity_is_protected('resource'::text, resource)) OR (EXISTS ( SELECT 1
   FROM resources demo_row
  WHERE ((demo_row.id = resource_slots.resource) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))));
ALTER POLICY "demo_read_fence" ON "public"."resources"
  USING ((((NOT demo_entity_is_protected('pool'::text, inventory_pool)) OR (EXISTS ( SELECT 1
   FROM inventory_pools demo_row
  WHERE ((demo_row.id = resources.inventory_pool) AND ((NOT is_demo_occasion(demo_row.occasion)) OR can_read_orders(demo_row.occasion)))))) AND ((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))) AND ((NOT is_demo_unit(unit)) OR demo_unit_can_read(unit))));
ALTER POLICY "demo_read_fence" ON "public"."role_info"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."speaker_topics"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."speakers"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."user_companions"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."user_group_info"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."user_login_qr_credentials"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
ALTER POLICY "demo_read_fence" ON "public"."user_news"
  USING (((NOT demo_entity_is_protected('occasion'::text, occasion)) OR ((NOT is_demo_occasion(occasion)) OR can_read_orders(occasion))));
