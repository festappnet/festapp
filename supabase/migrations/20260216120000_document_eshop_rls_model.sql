-- ============================================================================
-- ESHOP SCHEMA: RLS SECURITY MODEL DOCUMENTATION
-- ============================================================================
--
-- DESIGN DECISION: All eshop tables have RLS ENABLED with NO permissive policies.
--
-- This is INTENTIONAL. With RLS enabled and no policies:
--   - Direct PostgREST/Supabase client access is DENIED for all roles (anon, authenticated)
--   - Only SECURITY DEFINER functions and service_role can access these tables
--   - All data access goes through audited RPC functions in database/functions/eshop_*/
--
-- This "deny-all + RPC gateway" pattern ensures:
--   1. Every data access path has explicit permission checks
--   2. Business logic (order lifecycle, payment validation) cannot be bypassed
--   3. Complex multi-table operations remain atomic within SQL functions
--
-- CRITICAL: Do NOT add permissive SELECT/INSERT/UPDATE/DELETE policies to eshop
-- tables unless you fully understand the security implications. Adding a policy
-- like USING(true) would bypass all RPC-level permission checks.
--
-- Tables covered by this model:
--   eshop.orders, eshop.payment_info, eshop.bank_accounts, eshop.secrets,
--   eshop.tickets, eshop.products, eshop.spots, eshop.blueprints,
--   eshop.order_product_ticket, eshop.bank_account_users, eshop.transactions,
--   eshop.orders_history, eshop.bank_account_requests, eshop.planned_changes,
--   eshop.unit_bank_accounts, eshop.product_types, eshop.external_services,
--   eshop.product_inventory_contexts
--
-- RPC entry points (SECURITY DEFINER):
--   eshop_orders/:   get_orders, create_ticket_order, update_order_status, delete_order, ...
--   eshop_forms/:    submit_form_order, ...
--   eshop_transactions/: insert_manual_transaction, insert_transactions, process_email_transaction, ...
--   eshop_bank_accounts/: link_bank_account, get_bank_accounts, ...
--
-- All eshop tables follow this model uniformly — no exceptions.
-- ============================================================================

-- Drop stale permissive policy on eshop.transactions that was created in
-- migration 20260122160000. No production code uses direct table access;
-- all reads go through RPC functions. Keeping the policy would break the
-- deny-all invariant documented above.
DROP POLICY IF EXISTS "Managers can view transactions for their units" ON eshop.transactions;

-- Verify RLS is still enabled on all eshop tables (safety net).
DO $$
DECLARE
    tbl TEXT;
    rls_enabled BOOLEAN;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'eshop'
    LOOP
        SELECT relrowsecurity INTO rls_enabled
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'eshop' AND c.relname = tbl;

        IF NOT rls_enabled THEN
            RAISE WARNING 'RLS is NOT enabled on eshop.% — this is a security risk!', tbl;
        END IF;
    END LOOP;
END $$;
