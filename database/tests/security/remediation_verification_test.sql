-- Description: Verify security remediation for Critical findings.
-- 1. duplicate_occasion should be SECURITY DEFINER (true) but have guard in source.
-- 2. Internal helpers should be SECURITY INVOKER (false).

BEGIN;

DO $$ 
DECLARE
    rec boolean;
    src text;
BEGIN
    ----------------------------------------------------------------------------
    -- 1. Check the canonical duplicate command. duplicate_occasion is now a
    -- thin compatibility facade and intentionally delegates this guard.
    ----------------------------------------------------------------------------
    RAISE NOTICE 'Verifying duplicate_occasion_client_sync_v1...';
    
    SELECT prosecdef, prosrc INTO rec, src
    FROM pg_proc 
    WHERE oid = 'public.duplicate_occasion_client_sync_v1(bigint,uuid,bigint,text)'::regprocedure;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Function duplicate_occasion_client_sync_v1 not found';
    END IF;

    IF NOT rec THEN
        RAISE EXCEPTION 'duplicate_occasion_client_sync_v1 MUST be SECURITY DEFINER';
    END IF;

    IF src NOT ILIKE '%can_copy_occasion_target%' THEN
        RAISE EXCEPTION 'duplicate_occasion_client_sync_v1 MUST contain an explicit copy-target operation guard';
    END IF;

    RAISE NOTICE '✅ duplicate_occasion_client_sync_v1 is DEFINER and guarded.';

    ----------------------------------------------------------------------------
    -- 2. Check recalculate_order_payment_status
    ----------------------------------------------------------------------------
    RAISE NOTICE 'Verifying recalculate_order_payment_status...';
    
    SELECT prosecdef INTO rec
    FROM pg_proc 
    WHERE proname = 'recalculate_order_payment_status';

    IF rec THEN
        RAISE EXCEPTION 'recalculate_order_payment_status MUST be SECURITY INVOKER (prosecdef=false)';
    END IF;
    RAISE NOTICE '✅ recalculate_order_payment_status is INVOKER.';

    ----------------------------------------------------------------------------
    -- 3. Check update_order_and_tickets_to_paid
    ----------------------------------------------------------------------------
    RAISE NOTICE 'Verifying update_order_and_tickets_to_paid...';
    
    SELECT prosecdef INTO rec
    FROM pg_proc 
    WHERE proname = 'update_order_and_tickets_to_paid';

    IF rec THEN
        RAISE EXCEPTION 'update_order_and_tickets_to_paid MUST be SECURITY INVOKER (prosecdef=false)';
    END IF;
    RAISE NOTICE '✅ update_order_and_tickets_to_paid is INVOKER.';

    ----------------------------------------------------------------------------
    -- 4. Check internal_storno_tickets_221
    ----------------------------------------------------------------------------
    RAISE NOTICE 'Verifying internal_storno_tickets_221...';
    
    SELECT prosecdef INTO rec
    FROM pg_proc 
    WHERE proname = 'internal_storno_tickets_221';

    IF rec THEN
        RAISE EXCEPTION 'internal_storno_tickets_221 MUST be SECURITY INVOKER (prosecdef=false)';
    END IF;
    RAISE NOTICE '✅ internal_storno_tickets_221 is INVOKER.';

END $$;

ROLLBACK;
