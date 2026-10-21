-- Restrictive policies supplement, rather than replace, ordinary grants.
-- They protect direct authenticated/anonymous writes; SECURITY DEFINER/service
-- paths additionally use explicit domain guards. No application triggers.
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_account_requests'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_account_requests;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_account_requests AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_account_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_account_requests;
CREATE POLICY demo_read_only_insert ON eshop.bank_account_requests AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('order',"order")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_account_requests;
CREATE POLICY demo_read_only_update ON eshop.bank_account_requests AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('order',"order"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('order',"order")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_account_requests;
CREATE POLICY demo_read_only_delete ON eshop.bank_account_requests AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('order',"order"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_account_users'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_account_users;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_account_users AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_account_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_account_users;
CREATE POLICY demo_read_only_insert ON eshop.bank_account_users AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_account_users;
CREATE POLICY demo_read_only_update ON eshop.bank_account_users AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_account_users;
CREATE POLICY demo_read_only_delete ON eshop.bank_account_users AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_accounts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_accounts;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_accounts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_accounts;
CREATE POLICY demo_read_only_insert ON eshop.bank_accounts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_bank_account(id)));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_accounts;
CREATE POLICY demo_read_only_update ON eshop.bank_accounts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_bank_account(id))) WITH CHECK (NOT (public.is_demo_bank_account(id)));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_accounts;
CREATE POLICY demo_read_only_delete ON eshop.bank_accounts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_bank_account(id))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_sync_account_aliases'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_sync_account_aliases;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_sync_account_aliases AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_sync_account_aliases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_sync_account_aliases;
CREATE POLICY demo_read_only_insert ON eshop.bank_sync_account_aliases AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_sync_account_aliases;
CREATE POLICY demo_read_only_update ON eshop.bank_sync_account_aliases AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_sync_account_aliases;
CREATE POLICY demo_read_only_delete ON eshop.bank_sync_account_aliases AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_sync_connections'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_sync_connections;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_sync_connections AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_sync_connections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_sync_connections;
CREATE POLICY demo_read_only_insert ON eshop.bank_sync_connections AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_sync_connections;
CREATE POLICY demo_read_only_update ON eshop.bank_sync_connections AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_sync_connections;
CREATE POLICY demo_read_only_delete ON eshop.bank_sync_connections AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.bank_sync_operations'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.bank_sync_operations;
  CREATE POLICY demo_preserve_existing_access ON eshop.bank_sync_operations AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.bank_sync_operations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.bank_sync_operations;
CREATE POLICY demo_read_only_insert ON eshop.bank_sync_operations AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.bank_sync_operations;
CREATE POLICY demo_read_only_update ON eshop.bank_sync_operations AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.bank_sync_operations;
CREATE POLICY demo_read_only_delete ON eshop.bank_sync_operations AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.blueprints'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.blueprints;
  CREATE POLICY demo_preserve_existing_access ON eshop.blueprints AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.blueprints ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.blueprints;
CREATE POLICY demo_read_only_insert ON eshop.blueprints AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.blueprints;
CREATE POLICY demo_read_only_update ON eshop.blueprints AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.blueprints;
CREATE POLICY demo_read_only_delete ON eshop.blueprints AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.external_services'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.external_services;
  CREATE POLICY demo_preserve_existing_access ON eshop.external_services AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.external_services ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.external_services;
CREATE POLICY demo_read_only_insert ON eshop.external_services AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.external_services;
CREATE POLICY demo_read_only_update ON eshop.external_services AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.external_services;
CREATE POLICY demo_read_only_delete ON eshop.external_services AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.order_product_ticket'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.order_product_ticket;
  CREATE POLICY demo_preserve_existing_access ON eshop.order_product_ticket AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.order_product_ticket ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.order_product_ticket;
CREATE POLICY demo_read_only_insert ON eshop.order_product_ticket AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('order',"order") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('ticket',"ticket")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.order_product_ticket;
CREATE POLICY demo_read_only_update ON eshop.order_product_ticket AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('order',"order") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('ticket',"ticket"))) WITH CHECK (NOT (public.demo_entity_is_protected('order',"order") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('ticket',"ticket")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.order_product_ticket;
CREATE POLICY demo_read_only_delete ON eshop.order_product_ticket AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('order',"order") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('ticket',"ticket"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.orders'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.orders;
  CREATE POLICY demo_preserve_existing_access ON eshop.orders AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.orders;
CREATE POLICY demo_read_only_insert ON eshop.orders AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('form',"form") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('payment',"payment_info")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.orders;
CREATE POLICY demo_read_only_update ON eshop.orders AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',"form") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('payment',"payment_info"))) WITH CHECK (NOT (public.demo_entity_is_protected('form',"form") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('payment',"payment_info")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.orders;
CREATE POLICY demo_read_only_delete ON eshop.orders AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',"form") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('payment',"payment_info"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.orders_history'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.orders_history;
  CREATE POLICY demo_preserve_existing_access ON eshop.orders_history AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.orders_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.orders_history;
CREATE POLICY demo_read_only_insert ON eshop.orders_history AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('order',"order")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.orders_history;
CREATE POLICY demo_read_only_update ON eshop.orders_history AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('order',"order"))) WITH CHECK (NOT (public.demo_entity_is_protected('order',"order")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.orders_history;
CREATE POLICY demo_read_only_delete ON eshop.orders_history AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('order',"order"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.payment_info'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.payment_info;
  CREATE POLICY demo_preserve_existing_access ON eshop.payment_info AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.payment_info ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.payment_info;
CREATE POLICY demo_read_only_insert ON eshop.payment_info AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.payment_info;
CREATE POLICY demo_read_only_update ON eshop.payment_info AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.payment_info;
CREATE POLICY demo_read_only_delete ON eshop.payment_info AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.planned_changes'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.planned_changes;
  CREATE POLICY demo_preserve_existing_access ON eshop.planned_changes AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.planned_changes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.planned_changes;
CREATE POLICY demo_read_only_insert ON eshop.planned_changes AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.planned_changes;
CREATE POLICY demo_read_only_update ON eshop.planned_changes AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.planned_changes;
CREATE POLICY demo_read_only_delete ON eshop.planned_changes AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.product_inventory_contexts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.product_inventory_contexts;
  CREATE POLICY demo_preserve_existing_access ON eshop.product_inventory_contexts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.product_inventory_contexts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.product_inventory_contexts;
CREATE POLICY demo_read_only_insert ON eshop.product_inventory_contexts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('product',product) OR public.demo_entity_is_protected('context',inventory_context)));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.product_inventory_contexts;
CREATE POLICY demo_read_only_update ON eshop.product_inventory_contexts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('product',product) OR public.demo_entity_is_protected('context',inventory_context))) WITH CHECK (NOT (public.demo_entity_is_protected('product',product) OR public.demo_entity_is_protected('context',inventory_context)));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.product_inventory_contexts;
CREATE POLICY demo_read_only_delete ON eshop.product_inventory_contexts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('product',product) OR public.demo_entity_is_protected('context',inventory_context))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.product_price_waves'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.product_price_waves;
  CREATE POLICY demo_preserve_existing_access ON eshop.product_price_waves AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.product_price_waves ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.product_price_waves;
CREATE POLICY demo_read_only_insert ON eshop.product_price_waves AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.product_price_waves;
CREATE POLICY demo_read_only_update ON eshop.product_price_waves AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.product_price_waves;
CREATE POLICY demo_read_only_delete ON eshop.product_price_waves AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.product_types'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.product_types;
  CREATE POLICY demo_preserve_existing_access ON eshop.product_types AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.product_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.product_types;
CREATE POLICY demo_read_only_insert ON eshop.product_types AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.product_types;
CREATE POLICY demo_read_only_update ON eshop.product_types AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.product_types;
CREATE POLICY demo_read_only_delete ON eshop.product_types AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.products'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.products;
  CREATE POLICY demo_preserve_existing_access ON eshop.products AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.products;
CREATE POLICY demo_read_only_insert ON eshop.products AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.products;
CREATE POLICY demo_read_only_update ON eshop.products AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.products;
CREATE POLICY demo_read_only_delete ON eshop.products AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.spots'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.spots;
  CREATE POLICY demo_preserve_existing_access ON eshop.spots AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.spots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.spots;
CREATE POLICY demo_read_only_insert ON eshop.spots AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('context',"inventory_context") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('resource',"resource")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.spots;
CREATE POLICY demo_read_only_update ON eshop.spots AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('context',"inventory_context") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('resource',"resource"))) WITH CHECK (NOT (public.demo_entity_is_protected('context',"inventory_context") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('resource',"resource")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.spots;
CREATE POLICY demo_read_only_delete ON eshop.spots AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('context',"inventory_context") OR public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('product',"product") OR public.demo_entity_is_protected('resource',"resource"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.tickets'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.tickets;
  CREATE POLICY demo_preserve_existing_access ON eshop.tickets AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.tickets;
CREATE POLICY demo_read_only_insert ON eshop.tickets AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.tickets;
CREATE POLICY demo_read_only_update ON eshop.tickets AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.tickets;
CREATE POLICY demo_read_only_delete ON eshop.tickets AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.transactions'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.transactions;
  CREATE POLICY demo_preserve_existing_access ON eshop.transactions AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.transactions;
CREATE POLICY demo_read_only_insert ON eshop.transactions AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id") OR public.demo_entity_is_protected('payment',"payment_info")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.transactions;
CREATE POLICY demo_read_only_update ON eshop.transactions AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id") OR public.demo_entity_is_protected('payment',"payment_info"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id") OR public.demo_entity_is_protected('payment',"payment_info")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.transactions;
CREATE POLICY demo_read_only_delete ON eshop.transactions AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id") OR public.demo_entity_is_protected('payment',"payment_info"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.transactions_parser_log'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.transactions_parser_log;
  CREATE POLICY demo_preserve_existing_access ON eshop.transactions_parser_log AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.transactions_parser_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.transactions_parser_log;
CREATE POLICY demo_read_only_insert ON eshop.transactions_parser_log AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.transactions_parser_log;
CREATE POLICY demo_read_only_update ON eshop.transactions_parser_log AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account_id")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.transactions_parser_log;
CREATE POLICY demo_read_only_delete ON eshop.transactions_parser_log AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account_id"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.unit_bank_accounts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.unit_bank_accounts;
  CREATE POLICY demo_preserve_existing_access ON eshop.unit_bank_accounts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.unit_bank_accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.unit_bank_accounts;
CREATE POLICY demo_read_only_insert ON eshop.unit_bank_accounts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.unit_bank_accounts;
CREATE POLICY demo_read_only_update ON eshop.unit_bank_accounts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.unit_bank_accounts;
CREATE POLICY demo_read_only_delete ON eshop.unit_bank_accounts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.waitlist_capabilities'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.waitlist_capabilities;
  CREATE POLICY demo_preserve_existing_access ON eshop.waitlist_capabilities AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.waitlist_capabilities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.waitlist_capabilities;
CREATE POLICY demo_read_only_insert ON eshop.waitlist_capabilities AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.waitlist_capabilities;
CREATE POLICY demo_read_only_update ON eshop.waitlist_capabilities AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.waitlist_capabilities;
CREATE POLICY demo_read_only_delete ON eshop.waitlist_capabilities AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.waitlist_offer_slots'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.waitlist_offer_slots;
  CREATE POLICY demo_preserve_existing_access ON eshop.waitlist_offer_slots AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.waitlist_offer_slots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.waitlist_offer_slots;
CREATE POLICY demo_read_only_insert ON eshop.waitlist_offer_slots AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.waitlist_offer_slots;
CREATE POLICY demo_read_only_update ON eshop.waitlist_offer_slots AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.waitlist_offer_slots;
CREATE POLICY demo_read_only_delete ON eshop.waitlist_offer_slots AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='eshop.waitlist_offers'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON eshop.waitlist_offers;
  CREATE POLICY demo_preserve_existing_access ON eshop.waitlist_offers AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE eshop.waitlist_offers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON eshop.waitlist_offers;
CREATE POLICY demo_read_only_insert ON eshop.waitlist_offers AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_update ON eshop.waitlist_offers;
CREATE POLICY demo_read_only_update ON eshop.waitlist_offers AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) WITH CHECK (NOT (public.demo_entity_is_protected('form',form_id)));
DROP POLICY IF EXISTS demo_read_only_delete ON eshop.waitlist_offers;
CREATE POLICY demo_read_only_delete ON eshop.waitlist_offers AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',form_id))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.activities'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.activities;
  CREATE POLICY demo_preserve_existing_access ON public.activities AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.activities;
CREATE POLICY demo_read_only_insert ON public.activities AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.activities;
CREATE POLICY demo_read_only_update ON public.activities AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.activities;
CREATE POLICY demo_read_only_delete ON public.activities AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.cleaning_public_state'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.cleaning_public_state;
  CREATE POLICY demo_preserve_existing_access ON public.cleaning_public_state AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.cleaning_public_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.cleaning_public_state;
CREATE POLICY demo_read_only_insert ON public.cleaning_public_state AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.cleaning_public_state;
CREATE POLICY demo_read_only_update ON public.cleaning_public_state AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.cleaning_public_state;
CREATE POLICY demo_read_only_delete ON public.cleaning_public_state AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.cleaning_reports'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.cleaning_reports;
  CREATE POLICY demo_preserve_existing_access ON public.cleaning_reports AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.cleaning_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.cleaning_reports;
CREATE POLICY demo_read_only_insert ON public.cleaning_reports AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.cleaning_reports;
CREATE POLICY demo_read_only_update ON public.cleaning_reports AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.cleaning_reports;
CREATE POLICY demo_read_only_delete ON public.cleaning_reports AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.client_commits'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.client_commits;
  CREATE POLICY demo_preserve_existing_access ON public.client_commits AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.client_commits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.client_commits;
CREATE POLICY demo_read_only_insert ON public.client_commits AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.client_commits;
CREATE POLICY demo_read_only_update ON public.client_commits AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.client_commits;
CREATE POLICY demo_read_only_delete ON public.client_commits AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.client_mutation_receipts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.client_mutation_receipts;
  CREATE POLICY demo_preserve_existing_access ON public.client_mutation_receipts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.client_mutation_receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.client_mutation_receipts;
CREATE POLICY demo_read_only_insert ON public.client_mutation_receipts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.client_mutation_receipts;
CREATE POLICY demo_read_only_update ON public.client_mutation_receipts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.client_mutation_receipts;
CREATE POLICY demo_read_only_delete ON public.client_mutation_receipts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.client_sync_private_scopes'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.client_sync_private_scopes;
  CREATE POLICY demo_preserve_existing_access ON public.client_sync_private_scopes AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.client_sync_private_scopes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.client_sync_private_scopes;
CREATE POLICY demo_read_only_insert ON public.client_sync_private_scopes AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.client_sync_private_scopes;
CREATE POLICY demo_read_only_update ON public.client_sync_private_scopes AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.client_sync_private_scopes;
CREATE POLICY demo_read_only_delete ON public.client_sync_private_scopes AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.email_messages'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.email_messages;
  CREATE POLICY demo_preserve_existing_access ON public.email_messages AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.email_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.email_messages;
CREATE POLICY demo_read_only_insert ON public.email_messages AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.email_messages;
CREATE POLICY demo_read_only_update ON public.email_messages AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.email_messages;
CREATE POLICY demo_read_only_delete ON public.email_messages AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.email_templates'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.email_templates;
  CREATE POLICY demo_preserve_existing_access ON public.email_templates AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.email_templates;
CREATE POLICY demo_read_only_insert ON public.email_templates AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.email_templates;
CREATE POLICY demo_read_only_update ON public.email_templates AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.email_templates;
CREATE POLICY demo_read_only_delete ON public.email_templates AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.email_wrappers'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.email_wrappers;
  CREATE POLICY demo_preserve_existing_access ON public.email_wrappers AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.email_wrappers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.email_wrappers;
CREATE POLICY demo_read_only_insert ON public.email_wrappers AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.email_wrappers;
CREATE POLICY demo_read_only_update ON public.email_wrappers AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.email_wrappers;
CREATE POLICY demo_read_only_delete ON public.email_wrappers AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_feedback'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_feedback;
  CREATE POLICY demo_preserve_existing_access ON public.event_feedback AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_feedback;
CREATE POLICY demo_read_only_insert ON public.event_feedback AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_feedback;
CREATE POLICY demo_read_only_update ON public.event_feedback AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_feedback;
CREATE POLICY demo_read_only_delete ON public.event_feedback AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_groups'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_groups;
  CREATE POLICY demo_preserve_existing_access ON public.event_groups AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_groups;
CREATE POLICY demo_read_only_insert ON public.event_groups AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event_child") OR public.demo_entity_is_protected('event',"event_parent")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_groups;
CREATE POLICY demo_read_only_update ON public.event_groups AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event_child") OR public.demo_entity_is_protected('event',"event_parent"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event_child") OR public.demo_entity_is_protected('event',"event_parent")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_groups;
CREATE POLICY demo_read_only_delete ON public.event_groups AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event_child") OR public.demo_entity_is_protected('event',"event_parent"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_public_state'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_public_state;
  CREATE POLICY demo_preserve_existing_access ON public.event_public_state AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_public_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_public_state;
CREATE POLICY demo_read_only_insert ON public.event_public_state AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_public_state;
CREATE POLICY demo_read_only_update ON public.event_public_state AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_public_state;
CREATE POLICY demo_read_only_delete ON public.event_public_state AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event") OR public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_roles'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_roles;
  CREATE POLICY demo_preserve_existing_access ON public.event_roles AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_roles;
CREATE POLICY demo_read_only_insert ON public.event_roles AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_roles;
CREATE POLICY demo_read_only_update ON public.event_roles AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_roles;
CREATE POLICY demo_read_only_delete ON public.event_roles AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_speakers'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_speakers;
  CREATE POLICY demo_preserve_existing_access ON public.event_speakers AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_speakers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_speakers;
CREATE POLICY demo_read_only_insert ON public.event_speakers AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_speakers;
CREATE POLICY demo_read_only_update ON public.event_speakers AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_speakers;
CREATE POLICY demo_read_only_delete ON public.event_speakers AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_users'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_users;
  CREATE POLICY demo_preserve_existing_access ON public.event_users AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_users;
CREATE POLICY demo_read_only_insert ON public.event_users AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_users;
CREATE POLICY demo_read_only_update ON public.event_users AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_users;
CREATE POLICY demo_read_only_delete ON public.event_users AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.event_users_saved'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.event_users_saved;
  CREATE POLICY demo_preserve_existing_access ON public.event_users_saved AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.event_users_saved ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.event_users_saved;
CREATE POLICY demo_read_only_insert ON public.event_users_saved AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_update ON public.event_users_saved;
CREATE POLICY demo_read_only_update ON public.event_users_saved AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.event_users_saved;
CREATE POLICY demo_read_only_delete ON public.event_users_saved AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.events'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.events;
  CREATE POLICY demo_preserve_existing_access ON public.events AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.events;
CREATE POLICY demo_read_only_insert ON public.events AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.events;
CREATE POLICY demo_read_only_update ON public.events AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.events;
CREATE POLICY demo_read_only_delete ON public.events AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.exclusive_events'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.exclusive_events;
  CREATE POLICY demo_preserve_existing_access ON public.exclusive_events AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.exclusive_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.exclusive_events;
CREATE POLICY demo_read_only_insert ON public.exclusive_events AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_update ON public.exclusive_events;
CREATE POLICY demo_read_only_update ON public.exclusive_events AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) WITH CHECK (NOT (public.demo_entity_is_protected('event',"event")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.exclusive_events;
CREATE POLICY demo_read_only_delete ON public.exclusive_events AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('event',"event"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.exclusive_groups'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.exclusive_groups;
  CREATE POLICY demo_preserve_existing_access ON public.exclusive_groups AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.exclusive_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.exclusive_groups;
CREATE POLICY demo_read_only_insert ON public.exclusive_groups AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.exclusive_groups;
CREATE POLICY demo_read_only_update ON public.exclusive_groups AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.exclusive_groups;
CREATE POLICY demo_read_only_delete ON public.exclusive_groups AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.form_fields'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.form_fields;
  CREATE POLICY demo_preserve_existing_access ON public.form_fields AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.form_fields ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.form_fields;
CREATE POLICY demo_read_only_insert ON public.form_fields AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('form',"form")));
DROP POLICY IF EXISTS demo_read_only_update ON public.form_fields;
CREATE POLICY demo_read_only_update ON public.form_fields AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',"form"))) WITH CHECK (NOT (public.demo_entity_is_protected('form',"form")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.form_fields;
CREATE POLICY demo_read_only_delete ON public.form_fields AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('form',"form"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.forms'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.forms;
  CREATE POLICY demo_preserve_existing_access ON public.forms AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.forms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.forms;
CREATE POLICY demo_read_only_insert ON public.forms AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.forms;
CREATE POLICY demo_read_only_update ON public.forms AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.forms;
CREATE POLICY demo_read_only_delete ON public.forms AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('bank',"bank_account") OR public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.icons'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.icons;
  CREATE POLICY demo_preserve_existing_access ON public.icons AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.icons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.icons;
CREATE POLICY demo_read_only_insert ON public.icons AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.icons;
CREATE POLICY demo_read_only_update ON public.icons AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.icons;
CREATE POLICY demo_read_only_delete ON public.icons AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.images'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.images;
  CREATE POLICY demo_preserve_existing_access ON public.images AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.images ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.images;
CREATE POLICY demo_read_only_insert ON public.images AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.images;
CREATE POLICY demo_read_only_update ON public.images AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.images;
CREATE POLICY demo_read_only_delete ON public.images AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.information'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.information;
  CREATE POLICY demo_preserve_existing_access ON public.information AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.information ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.information;
CREATE POLICY demo_read_only_insert ON public.information AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.information;
CREATE POLICY demo_read_only_update ON public.information AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.information;
CREATE POLICY demo_read_only_delete ON public.information AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.information_hidden'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.information_hidden;
  CREATE POLICY demo_preserve_existing_access ON public.information_hidden AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.information_hidden ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.information_hidden;
CREATE POLICY demo_read_only_insert ON public.information_hidden AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.information_hidden;
CREATE POLICY demo_read_only_update ON public.information_hidden AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.information_hidden;
CREATE POLICY demo_read_only_delete ON public.information_hidden AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.inventory_contexts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.inventory_contexts;
  CREATE POLICY demo_preserve_existing_access ON public.inventory_contexts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.inventory_contexts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.inventory_contexts;
CREATE POLICY demo_read_only_insert ON public.inventory_contexts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('pool',"inventory_pool")));
DROP POLICY IF EXISTS demo_read_only_update ON public.inventory_contexts;
CREATE POLICY demo_read_only_update ON public.inventory_contexts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('pool',"inventory_pool"))) WITH CHECK (NOT (public.demo_entity_is_protected('pool',"inventory_pool")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.inventory_contexts;
CREATE POLICY demo_read_only_delete ON public.inventory_contexts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('pool',"inventory_pool"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.inventory_pools'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.inventory_pools;
  CREATE POLICY demo_preserve_existing_access ON public.inventory_pools AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.inventory_pools ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.inventory_pools;
CREATE POLICY demo_read_only_insert ON public.inventory_pools AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.inventory_pools;
CREATE POLICY demo_read_only_update ON public.inventory_pools AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.inventory_pools;
CREATE POLICY demo_read_only_delete ON public.inventory_pools AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.log_emails'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.log_emails;
  CREATE POLICY demo_preserve_existing_access ON public.log_emails AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.log_emails ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.log_emails;
CREATE POLICY demo_read_only_insert ON public.log_emails AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.log_emails;
CREATE POLICY demo_read_only_update ON public.log_emails AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.log_emails;
CREATE POLICY demo_read_only_delete ON public.log_emails AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.log_notifications'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.log_notifications;
  CREATE POLICY demo_preserve_existing_access ON public.log_notifications AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.log_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.log_notifications;
CREATE POLICY demo_read_only_insert ON public.log_notifications AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.log_notifications;
CREATE POLICY demo_read_only_update ON public.log_notifications AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.log_notifications;
CREATE POLICY demo_read_only_delete ON public.log_notifications AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.news'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.news;
  CREATE POLICY demo_preserve_existing_access ON public.news AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.news;
CREATE POLICY demo_read_only_insert ON public.news AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.news;
CREATE POLICY demo_read_only_update ON public.news AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.news;
CREATE POLICY demo_read_only_delete ON public.news AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.news_notification_outbox'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.news_notification_outbox;
  CREATE POLICY demo_preserve_existing_access ON public.news_notification_outbox AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.news_notification_outbox ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.news_notification_outbox;
CREATE POLICY demo_read_only_insert ON public.news_notification_outbox AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.news_notification_outbox;
CREATE POLICY demo_read_only_update ON public.news_notification_outbox AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.news_notification_outbox;
CREATE POLICY demo_read_only_delete ON public.news_notification_outbox AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.occasion_setup_drafts'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.occasion_setup_drafts;
  CREATE POLICY demo_preserve_existing_access ON public.occasion_setup_drafts AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.occasion_setup_drafts;
CREATE POLICY demo_read_only_insert ON public.occasion_setup_drafts AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.occasion_setup_drafts;
CREATE POLICY demo_read_only_update ON public.occasion_setup_drafts AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.occasion_setup_drafts;
CREATE POLICY demo_read_only_delete ON public.occasion_setup_drafts AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.occasion_users'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.occasion_users;
  CREATE POLICY demo_preserve_existing_access ON public.occasion_users AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.occasion_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.occasion_users;
CREATE POLICY demo_read_only_insert ON public.occasion_users AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('ticket',"ticket")));
DROP POLICY IF EXISTS demo_read_only_update ON public.occasion_users;
CREATE POLICY demo_read_only_update ON public.occasion_users AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('ticket',"ticket"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('ticket',"ticket")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.occasion_users;
CREATE POLICY demo_read_only_delete ON public.occasion_users AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.demo_entity_is_protected('ticket',"ticket"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.occasions'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.occasions;
  CREATE POLICY demo_preserve_existing_access ON public.occasions AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.occasions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.occasions;
CREATE POLICY demo_read_only_insert ON public.occasions AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_occasion(id) OR public.is_demo_unit(unit)));
DROP POLICY IF EXISTS demo_read_only_update ON public.occasions;
CREATE POLICY demo_read_only_update ON public.occasions AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_occasion(id) OR public.is_demo_unit(unit))) WITH CHECK (NOT (public.is_demo_occasion(id) OR public.is_demo_unit(unit)));
DROP POLICY IF EXISTS demo_read_only_delete ON public.occasions;
CREATE POLICY demo_read_only_delete ON public.occasions AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_occasion(id) OR public.is_demo_unit(unit))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.path_groups'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.path_groups;
  CREATE POLICY demo_preserve_existing_access ON public.path_groups AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.path_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.path_groups;
CREATE POLICY demo_read_only_insert ON public.path_groups AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.path_groups;
CREATE POLICY demo_read_only_update ON public.path_groups AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.path_groups;
CREATE POLICY demo_read_only_delete ON public.path_groups AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.place_types'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.place_types;
  CREATE POLICY demo_preserve_existing_access ON public.place_types AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.place_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.place_types;
CREATE POLICY demo_read_only_insert ON public.place_types AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.place_types;
CREATE POLICY demo_read_only_update ON public.place_types AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.place_types;
CREATE POLICY demo_read_only_delete ON public.place_types AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.places'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.places;
  CREATE POLICY demo_preserve_existing_access ON public.places AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.places;
CREATE POLICY demo_read_only_insert ON public.places AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.places;
CREATE POLICY demo_read_only_update ON public.places AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.places;
CREATE POLICY demo_read_only_delete ON public.places AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.reception_registrations'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.reception_registrations;
  CREATE POLICY demo_preserve_existing_access ON public.reception_registrations AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.reception_registrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.reception_registrations;
CREATE POLICY demo_read_only_insert ON public.reception_registrations AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.reception_registrations;
CREATE POLICY demo_read_only_update ON public.reception_registrations AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.reception_registrations;
CREATE POLICY demo_read_only_delete ON public.reception_registrations AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.resource_slots'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.resource_slots;
  CREATE POLICY demo_preserve_existing_access ON public.resource_slots AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.resource_slots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.resource_slots;
CREATE POLICY demo_read_only_insert ON public.resource_slots AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('resource',"resource")));
DROP POLICY IF EXISTS demo_read_only_update ON public.resource_slots;
CREATE POLICY demo_read_only_update ON public.resource_slots AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('resource',"resource"))) WITH CHECK (NOT (public.demo_entity_is_protected('resource',"resource")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.resource_slots;
CREATE POLICY demo_read_only_delete ON public.resource_slots AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('resource',"resource"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.resources'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.resources;
  CREATE POLICY demo_preserve_existing_access ON public.resources AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.resources;
CREATE POLICY demo_read_only_insert ON public.resources AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('pool',"inventory_pool") OR public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.resources;
CREATE POLICY demo_read_only_update ON public.resources AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('pool',"inventory_pool") OR public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) WITH CHECK (NOT (public.demo_entity_is_protected('pool',"inventory_pool") OR public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.resources;
CREATE POLICY demo_read_only_delete ON public.resources AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('pool',"inventory_pool") OR public.demo_entity_is_protected('occasion',"occasion") OR public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.role_info'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.role_info;
  CREATE POLICY demo_preserve_existing_access ON public.role_info AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.role_info ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.role_info;
CREATE POLICY demo_read_only_insert ON public.role_info AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.role_info;
CREATE POLICY demo_read_only_update ON public.role_info AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.role_info;
CREATE POLICY demo_read_only_delete ON public.role_info AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.speaker_topics'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.speaker_topics;
  CREATE POLICY demo_preserve_existing_access ON public.speaker_topics AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.speaker_topics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.speaker_topics;
CREATE POLICY demo_read_only_insert ON public.speaker_topics AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.speaker_topics;
CREATE POLICY demo_read_only_update ON public.speaker_topics AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.speaker_topics;
CREATE POLICY demo_read_only_delete ON public.speaker_topics AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.speakers'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.speakers;
  CREATE POLICY demo_preserve_existing_access ON public.speakers AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.speakers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.speakers;
CREATE POLICY demo_read_only_insert ON public.speakers AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.speakers;
CREATE POLICY demo_read_only_update ON public.speakers AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.speakers;
CREATE POLICY demo_read_only_delete ON public.speakers AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.unit_users'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.unit_users;
  CREATE POLICY demo_preserve_existing_access ON public.unit_users AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.unit_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.unit_users;
CREATE POLICY demo_read_only_insert ON public.unit_users AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_update ON public.unit_users;
CREATE POLICY demo_read_only_update ON public.unit_users AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) WITH CHECK (NOT (public.is_demo_unit("unit")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.unit_users;
CREATE POLICY demo_read_only_delete ON public.unit_users AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_unit("unit"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.units'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.units;
  CREATE POLICY demo_preserve_existing_access ON public.units AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.units;
CREATE POLICY demo_read_only_insert ON public.units AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.is_demo_unit(id)));
DROP POLICY IF EXISTS demo_read_only_update ON public.units;
CREATE POLICY demo_read_only_update ON public.units AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.is_demo_unit(id))) WITH CHECK (NOT (public.is_demo_unit(id)));
DROP POLICY IF EXISTS demo_read_only_delete ON public.units;
CREATE POLICY demo_read_only_delete ON public.units AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.is_demo_unit(id))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_companions'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.user_companions;
  CREATE POLICY demo_preserve_existing_access ON public.user_companions AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.user_companions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.user_companions;
CREATE POLICY demo_read_only_insert ON public.user_companions AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.user_companions;
CREATE POLICY demo_read_only_update ON public.user_companions AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.user_companions;
CREATE POLICY demo_read_only_delete ON public.user_companions AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_group_info'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.user_group_info;
  CREATE POLICY demo_preserve_existing_access ON public.user_group_info AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.user_group_info ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.user_group_info;
CREATE POLICY demo_read_only_insert ON public.user_group_info AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.user_group_info;
CREATE POLICY demo_read_only_update ON public.user_group_info AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.user_group_info;
CREATE POLICY demo_read_only_delete ON public.user_group_info AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_login_qr_credentials'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.user_login_qr_credentials;
  CREATE POLICY demo_preserve_existing_access ON public.user_login_qr_credentials AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.user_login_qr_credentials ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.user_login_qr_credentials;
CREATE POLICY demo_read_only_insert ON public.user_login_qr_credentials AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.user_login_qr_credentials;
CREATE POLICY demo_read_only_update ON public.user_login_qr_credentials AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.user_login_qr_credentials;
CREATE POLICY demo_read_only_delete ON public.user_login_qr_credentials AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;
-- Preserve existing direct grants on tables that previously had no RLS.
DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.user_news'::regclass) THEN
  DROP POLICY IF EXISTS demo_preserve_existing_access ON public.user_news;
  CREATE POLICY demo_preserve_existing_access ON public.user_news AS PERMISSIVE FOR ALL TO anon,authenticated USING(true) WITH CHECK(true);
 END IF;
END $$;
ALTER TABLE public.user_news ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_read_only_insert ON public.user_news;
CREATE POLICY demo_read_only_insert ON public.user_news AS RESTRICTIVE FOR INSERT TO anon,authenticated WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_update ON public.user_news;
CREATE POLICY demo_read_only_update ON public.user_news AS RESTRICTIVE FOR UPDATE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) WITH CHECK (NOT (public.demo_entity_is_protected('occasion',"occasion")));
DROP POLICY IF EXISTS demo_read_only_delete ON public.user_news;
CREATE POLICY demo_read_only_delete ON public.user_news AS RESTRICTIVE FOR DELETE TO anon,authenticated USING (NOT (public.demo_entity_is_protected('occasion',"occasion"))) ;

DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_account_requests;
CREATE POLICY demo_read_fence ON eshop.bank_account_requests AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account")) OR ((NOT public.is_demo_bank_account(eshop.bank_account_requests."bank_account") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_account_requests."bank_account" AND public.can_read_orders(demo_bank.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.bank_account_requests."occasion") OR public.can_read_orders(eshop.bank_account_requests."occasion")))) AND (NOT (public.demo_entity_is_protected('order',"order")) OR (EXISTS (SELECT 1 FROM eshop.orders demo_row WHERE demo_row.id=eshop.bank_account_requests."order" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_account_users;
CREATE POLICY demo_read_fence ON eshop.bank_account_users AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account")) OR ((NOT public.is_demo_bank_account(eshop.bank_account_users."bank_account") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_account_users."bank_account" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_accounts;
CREATE POLICY demo_read_fence ON eshop.bank_accounts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_bank_account(id)) OR (EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_accounts.id AND public.can_read_orders(demo_bank.occasion)))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_sync_account_aliases;
CREATE POLICY demo_read_fence ON eshop.bank_sync_account_aliases AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account_id")) OR ((NOT public.is_demo_bank_account(eshop.bank_sync_account_aliases."bank_account_id") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_sync_account_aliases."bank_account_id" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_sync_connections;
CREATE POLICY demo_read_fence ON eshop.bank_sync_connections AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account_id")) OR ((NOT public.is_demo_bank_account(eshop.bank_sync_connections."bank_account_id") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_sync_connections."bank_account_id" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.bank_sync_operations;
CREATE POLICY demo_read_fence ON eshop.bank_sync_operations AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account_id")) OR ((NOT public.is_demo_bank_account(eshop.bank_sync_operations."bank_account_id") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_sync_operations."bank_account_id" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.blueprints;
CREATE POLICY demo_read_fence ON eshop.blueprints AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.blueprints."occasion") OR public.can_read_orders(eshop.blueprints."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.external_services;
CREATE POLICY demo_read_fence ON eshop.external_services AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.order_product_ticket;
CREATE POLICY demo_read_fence ON eshop.order_product_ticket AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('order',"order")) OR (EXISTS (SELECT 1 FROM eshop.orders demo_row WHERE demo_row.id=eshop.order_product_ticket."order" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('product',"product")) OR (EXISTS (SELECT 1 FROM eshop.products demo_row WHERE demo_row.id=eshop.order_product_ticket."product" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('ticket',"ticket")) OR (EXISTS (SELECT 1 FROM eshop.tickets demo_row WHERE demo_row.id=eshop.order_product_ticket."ticket" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.orders;
CREATE POLICY demo_read_fence ON eshop.orders AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('form',"form")) OR (EXISTS (SELECT 1 FROM public.forms demo_row WHERE demo_row.id=eshop.orders."form" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.orders."occasion") OR public.can_read_orders(eshop.orders."occasion")))) AND (NOT (public.demo_entity_is_protected('payment',"payment_info")) OR (EXISTS (SELECT 1 FROM eshop.payment_info demo_payment WHERE demo_payment.id=eshop.orders."payment_info" AND (NOT public.is_demo_bank_account(demo_payment.bank_account) OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=demo_payment.bank_account AND public.can_read_orders(demo_bank.occasion)))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.orders_history;
CREATE POLICY demo_read_fence ON eshop.orders_history AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('order',"order")) OR (EXISTS (SELECT 1 FROM eshop.orders demo_row WHERE demo_row.id=eshop.orders_history."order" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.payment_info;
CREATE POLICY demo_read_fence ON eshop.payment_info AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account")) OR ((NOT public.is_demo_bank_account(eshop.payment_info."bank_account") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.payment_info."bank_account" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.planned_changes;
CREATE POLICY demo_read_fence ON eshop.planned_changes AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.planned_changes."occasion") OR public.can_read_orders(eshop.planned_changes."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.product_inventory_contexts;
CREATE POLICY demo_read_fence ON eshop.product_inventory_contexts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('product',product)) OR (EXISTS (SELECT 1 FROM eshop.products demo_row WHERE demo_row.id=eshop.product_inventory_contexts.product AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('context',inventory_context)) OR (EXISTS (SELECT 1 FROM public.inventory_contexts demo_context JOIN public.inventory_pools demo_pool ON demo_pool.id=demo_context.inventory_pool WHERE demo_context.id=eshop.product_inventory_contexts.inventory_context AND (NOT public.is_demo_occasion(demo_pool.occasion) OR public.can_read_orders(demo_pool.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.product_price_waves;
CREATE POLICY demo_read_fence ON eshop.product_price_waves AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.product_price_waves."occasion") OR public.can_read_orders(eshop.product_price_waves."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.product_types;
CREATE POLICY demo_read_fence ON eshop.product_types AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.product_types."occasion") OR public.can_read_orders(eshop.product_types."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.products;
CREATE POLICY demo_read_fence ON eshop.products AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.products."occasion") OR public.can_read_orders(eshop.products."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.spots;
CREATE POLICY demo_read_fence ON eshop.spots AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('context',"inventory_context")) OR (EXISTS (SELECT 1 FROM public.inventory_contexts demo_context JOIN public.inventory_pools demo_pool ON demo_pool.id=demo_context.inventory_pool WHERE demo_context.id=eshop.spots."inventory_context" AND (NOT public.is_demo_occasion(demo_pool.occasion) OR public.can_read_orders(demo_pool.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.spots."occasion") OR public.can_read_orders(eshop.spots."occasion")))) AND (NOT (public.demo_entity_is_protected('product',"product")) OR (EXISTS (SELECT 1 FROM eshop.products demo_row WHERE demo_row.id=eshop.spots."product" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('resource',"resource")) OR (EXISTS (SELECT 1 FROM public.resources demo_row WHERE demo_row.id=eshop.spots."resource" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.tickets;
CREATE POLICY demo_read_fence ON eshop.tickets AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(eshop.tickets."occasion") OR public.can_read_orders(eshop.tickets."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.transactions;
CREATE POLICY demo_read_fence ON eshop.transactions AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account_id")) OR ((NOT public.is_demo_bank_account(eshop.transactions."bank_account_id") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.transactions."bank_account_id" AND public.can_read_orders(demo_bank.occasion))))) AND (NOT (public.demo_entity_is_protected('payment',"payment_info")) OR (EXISTS (SELECT 1 FROM eshop.payment_info demo_payment WHERE demo_payment.id=eshop.transactions."payment_info" AND (NOT public.is_demo_bank_account(demo_payment.bank_account) OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=demo_payment.bank_account AND public.can_read_orders(demo_bank.occasion)))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.transactions_parser_log;
CREATE POLICY demo_read_fence ON eshop.transactions_parser_log AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account_id")) OR ((NOT public.is_demo_bank_account(eshop.transactions_parser_log."bank_account_id") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.transactions_parser_log."bank_account_id" AND public.can_read_orders(demo_bank.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.unit_bank_accounts;
CREATE POLICY demo_read_fence ON eshop.unit_bank_accounts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account")) OR ((NOT public.is_demo_bank_account(eshop.unit_bank_accounts."bank_account") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.unit_bank_accounts."bank_account" AND public.can_read_orders(demo_bank.occasion))))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.waitlist_capabilities;
CREATE POLICY demo_read_fence ON eshop.waitlist_capabilities AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('form',form_id)) OR (EXISTS (SELECT 1 FROM public.forms demo_row WHERE demo_row.id=eshop.waitlist_capabilities.form_id AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.waitlist_offer_slots;
CREATE POLICY demo_read_fence ON eshop.waitlist_offer_slots AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('form',form_id)) OR (EXISTS (SELECT 1 FROM public.forms demo_row WHERE demo_row.id=eshop.waitlist_offer_slots.form_id AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON eshop.waitlist_offers;
CREATE POLICY demo_read_fence ON eshop.waitlist_offers AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('form',form_id)) OR (EXISTS (SELECT 1 FROM public.forms demo_row WHERE demo_row.id=eshop.waitlist_offers.form_id AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.activities;
CREATE POLICY demo_read_fence ON public.activities AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.activities."occasion") OR public.can_read_orders(public.activities."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.cleaning_public_state;
CREATE POLICY demo_read_fence ON public.cleaning_public_state AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.cleaning_public_state."occasion") OR public.can_read_orders(public.cleaning_public_state."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.cleaning_reports;
CREATE POLICY demo_read_fence ON public.cleaning_reports AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.cleaning_reports."occasion") OR public.can_read_orders(public.cleaning_reports."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.client_commits;
CREATE POLICY demo_read_fence ON public.client_commits AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.client_commits."occasion") OR public.can_read_orders(public.client_commits."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.client_mutation_receipts;
CREATE POLICY demo_read_fence ON public.client_mutation_receipts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.client_mutation_receipts."occasion") OR public.can_read_orders(public.client_mutation_receipts."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.client_sync_private_scopes;
CREATE POLICY demo_read_fence ON public.client_sync_private_scopes AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.client_sync_private_scopes."occasion") OR public.can_read_orders(public.client_sync_private_scopes."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.email_messages;
CREATE POLICY demo_read_fence ON public.email_messages AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.email_messages."occasion") OR public.can_read_orders(public.email_messages."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.email_templates;
CREATE POLICY demo_read_fence ON public.email_templates AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.email_templates."occasion") OR public.can_read_orders(public.email_templates."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.email_wrappers;
CREATE POLICY demo_read_fence ON public.email_wrappers AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.email_wrappers."occasion") OR public.can_read_orders(public.email_wrappers."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_feedback;
CREATE POLICY demo_read_fence ON public.event_feedback AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_feedback."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.event_feedback."occasion") OR public.can_read_orders(public.event_feedback."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_groups;
CREATE POLICY demo_read_fence ON public.event_groups AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event_child")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_groups."event_child" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('event',"event_parent")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_groups."event_parent" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_public_state;
CREATE POLICY demo_read_fence ON public.event_public_state AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_public_state."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.event_public_state."occasion") OR public.can_read_orders(public.event_public_state."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_roles;
CREATE POLICY demo_read_fence ON public.event_roles AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_roles."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_speakers;
CREATE POLICY demo_read_fence ON public.event_speakers AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_speakers."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_users;
CREATE POLICY demo_read_fence ON public.event_users AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_users."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.event_users_saved;
CREATE POLICY demo_read_fence ON public.event_users_saved AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.event_users_saved."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.events;
CREATE POLICY demo_read_fence ON public.events AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.events."occasion") OR public.can_read_orders(public.events."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.exclusive_events;
CREATE POLICY demo_read_fence ON public.exclusive_events AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('event',"event")) OR (EXISTS (SELECT 1 FROM public.events demo_row WHERE demo_row.id=public.exclusive_events."event" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.exclusive_groups;
CREATE POLICY demo_read_fence ON public.exclusive_groups AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.exclusive_groups."occasion") OR public.can_read_orders(public.exclusive_groups."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.form_fields;
CREATE POLICY demo_read_fence ON public.form_fields AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('form',"form")) OR (EXISTS (SELECT 1 FROM public.forms demo_row WHERE demo_row.id=public.form_fields."form" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.forms;
CREATE POLICY demo_read_fence ON public.forms AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('bank',"bank_account")) OR ((NOT public.is_demo_bank_account(public.forms."bank_account") OR EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=public.forms."bank_account" AND public.can_read_orders(demo_bank.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.forms."occasion") OR public.can_read_orders(public.forms."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.icons;
CREATE POLICY demo_read_fence ON public.icons AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.images;
CREATE POLICY demo_read_fence ON public.images AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.images."occasion") OR public.can_read_orders(public.images."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.information;
CREATE POLICY demo_read_fence ON public.information AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.information."occasion") OR public.can_read_orders(public.information."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.information_hidden;
CREATE POLICY demo_read_fence ON public.information_hidden AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.information_hidden."occasion") OR public.can_read_orders(public.information_hidden."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.inventory_contexts;
CREATE POLICY demo_read_fence ON public.inventory_contexts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('pool',"inventory_pool")) OR (EXISTS (SELECT 1 FROM public.inventory_pools demo_row WHERE demo_row.id=public.inventory_contexts."inventory_pool" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.inventory_pools;
CREATE POLICY demo_read_fence ON public.inventory_pools AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.inventory_pools."occasion") OR public.can_read_orders(public.inventory_pools."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.log_emails;
CREATE POLICY demo_read_fence ON public.log_emails AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.log_emails."occasion") OR public.can_read_orders(public.log_emails."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.log_notifications;
CREATE POLICY demo_read_fence ON public.log_notifications AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.log_notifications."occasion") OR public.can_read_orders(public.log_notifications."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.news;
CREATE POLICY demo_read_fence ON public.news AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.news."occasion") OR public.can_read_orders(public.news."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.news_notification_outbox;
CREATE POLICY demo_read_fence ON public.news_notification_outbox AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.news_notification_outbox."occasion") OR public.can_read_orders(public.news_notification_outbox."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.occasion_setup_drafts;
CREATE POLICY demo_read_fence ON public.occasion_setup_drafts AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.occasion_users;
CREATE POLICY demo_read_fence ON public.occasion_users AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.occasion_users."occasion") OR public.can_read_orders(public.occasion_users."occasion")))) AND (NOT (public.demo_entity_is_protected('ticket',"ticket")) OR (EXISTS (SELECT 1 FROM eshop.tickets demo_row WHERE demo_row.id=public.occasion_users."ticket" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.occasions;
CREATE POLICY demo_read_fence ON public.occasions AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_occasion(id)) OR (public.can_read_demo_occasion(id))) AND (NOT (public.is_demo_unit(unit)) OR (public.demo_unit_can_read(unit))));
DROP POLICY IF EXISTS demo_read_fence ON public.path_groups;
CREATE POLICY demo_read_fence ON public.path_groups AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.path_groups."occasion") OR public.can_read_orders(public.path_groups."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.place_types;
CREATE POLICY demo_read_fence ON public.place_types AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.place_types."occasion") OR public.can_read_orders(public.place_types."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.places;
CREATE POLICY demo_read_fence ON public.places AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.places."occasion") OR public.can_read_orders(public.places."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.reception_registrations;
CREATE POLICY demo_read_fence ON public.reception_registrations AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.reception_registrations."occasion") OR public.can_read_orders(public.reception_registrations."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.resource_slots;
CREATE POLICY demo_read_fence ON public.resource_slots AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('resource',"resource")) OR (EXISTS (SELECT 1 FROM public.resources demo_row WHERE demo_row.id=public.resource_slots."resource" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))));
DROP POLICY IF EXISTS demo_read_fence ON public.resources;
CREATE POLICY demo_read_fence ON public.resources AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('pool',"inventory_pool")) OR (EXISTS (SELECT 1 FROM public.inventory_pools demo_row WHERE demo_row.id=public.resources."inventory_pool" AND (NOT public.is_demo_occasion(demo_row.occasion) OR public.can_read_orders(demo_row.occasion))))) AND (NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.resources."occasion") OR public.can_read_orders(public.resources."occasion")))) AND (NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.role_info;
CREATE POLICY demo_read_fence ON public.role_info AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.role_info."occasion") OR public.can_read_orders(public.role_info."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.speaker_topics;
CREATE POLICY demo_read_fence ON public.speaker_topics AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.speaker_topics."occasion") OR public.can_read_orders(public.speaker_topics."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.speakers;
CREATE POLICY demo_read_fence ON public.speakers AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.speakers."occasion") OR public.can_read_orders(public.speakers."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.unit_users;
CREATE POLICY demo_read_fence ON public.unit_users AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_unit("unit")) OR (public.demo_unit_can_read("unit"))));
DROP POLICY IF EXISTS demo_read_fence ON public.units;
CREATE POLICY demo_read_fence ON public.units AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.is_demo_unit(id)) OR (public.demo_unit_can_read(id))));
DROP POLICY IF EXISTS demo_read_fence ON public.user_companions;
CREATE POLICY demo_read_fence ON public.user_companions AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.user_companions."occasion") OR public.can_read_orders(public.user_companions."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.user_group_info;
CREATE POLICY demo_read_fence ON public.user_group_info AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.user_group_info."occasion") OR public.can_read_orders(public.user_group_info."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.user_login_qr_credentials;
CREATE POLICY demo_read_fence ON public.user_login_qr_credentials AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.user_login_qr_credentials."occasion") OR public.can_read_orders(public.user_login_qr_credentials."occasion")))));
DROP POLICY IF EXISTS demo_read_fence ON public.user_news;
CREATE POLICY demo_read_fence ON public.user_news AS RESTRICTIVE FOR SELECT TO anon,authenticated USING ((NOT (public.demo_entity_is_protected('occasion',"occasion")) OR ((NOT public.is_demo_occasion(public.user_news."occasion") OR public.can_read_orders(public.user_news."occasion")))));
DROP POLICY IF EXISTS demo_bank_read ON eshop.bank_accounts;
CREATE POLICY demo_bank_read ON eshop.bank_accounts FOR SELECT TO authenticated USING(EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.bank_accounts.id AND public.can_read_orders(demo_bank.occasion)));
DROP POLICY IF EXISTS demo_bank_transaction_read ON eshop.transactions;
CREATE POLICY demo_bank_transaction_read ON eshop.transactions FOR SELECT TO authenticated USING(EXISTS (SELECT 1 FROM public.demo_occasions demo_bank WHERE demo_bank.bank_account=eshop.transactions.bank_account_id AND public.can_read_orders(demo_bank.occasion)));
