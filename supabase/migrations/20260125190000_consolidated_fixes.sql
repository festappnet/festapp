-- Fix missing updates and logic errors found during verification of 20260125 logic
BEGIN;

---------------------------------------------------------------------------
-- 1. Ensure `pairing_code` exists (Case where manual patch didn't run)
---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='eshop' AND table_name='bank_accounts' AND column_name='pairing_code') THEN
        ALTER TABLE eshop.bank_accounts ADD COLUMN pairing_code text DEFAULT encode(gen_random_bytes(5), 'hex');
        ALTER TABLE eshop.bank_accounts ADD CONSTRAINT bank_accounts_pairing_code_key UNIQUE (pairing_code);
        ALTER TABLE eshop.bank_accounts ADD CONSTRAINT check_pairing_code_length CHECK (pairing_code IS NULL OR length(pairing_code) = 10);
    END IF;
END $$;

---------------------------------------------------------------------------
-- 2. Function: regenerate_bank_account_pairing_code (Missing in previous)
---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.regenerate_bank_account_pairing_code(bigint);

CREATE OR REPLACE FUNCTION public.regenerate_bank_account_pairing_code(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Logic: Generate new 10-char hex code (5 bytes)
  -- Security: Check if user is admin or manager
  IF NOT EXISTS (
      SELECT 1 FROM eshop.bank_account_users 
      WHERE bank_account = p_id AND "user" = auth.uid() AND is_admin = true
  ) THEN
      RAISE EXCEPTION 'User is not an admin of this bank account.';
  END IF;

  UPDATE eshop.bank_accounts
  SET pairing_code = encode(gen_random_bytes(5), 'hex')
  WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.regenerate_bank_account_pairing_code(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.regenerate_bank_account_pairing_code(bigint) TO service_role;

---------------------------------------------------------------------------
-- 3. Function: get_transactions_for_order_all_available (Fix Manual Filter)
---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_transactions_for_order_all_available(bigint);

CREATE OR REPLACE FUNCTION public.get_transactions_for_order_all_available(payment_info_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    bank_acc bigint;
BEGIN
    SELECT pi.bank_account INTO bank_acc
    FROM eshop.payment_info pi
    WHERE pi.id = payment_info_id
    LIMIT 1;

    PERFORM public.check_is_admin_for_bank_account(bank_acc);

    RETURN (
        SELECT jsonb_agg(t ORDER BY t.date DESC)
        FROM eshop.transactions t
        WHERE t.bank_account_id = bank_acc
        AND t.payment_info IS NULL
        -- Removed: AND t.transaction_type != 'manual' (Allow manual pairing)
    );
END;
$function$;

---------------------------------------------------------------------------
-- 4. Function: update_order_and_tickets_to_paid (Fix Expired Check)
---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.update_order_and_tickets_to_paid(bigint);

CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now()
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state != 'storno';

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;

---------------------------------------------------------------------------
-- 5. Function: delete_manual_transaction_ws (Fix Recalculate Call)
---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_manual_transaction_ws(bigint, bigint);

CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(
    p_transaction_id bigint,
    p_payment_info_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    transaction_type text;
    payment_info_currency character(3);
    payment_info_record eshop.payment_info%ROWTYPE;
    associated_order_id bigint;
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    --- Retrieve the associated order_id from payment_info
     SELECT pi.bank_account INTO bank_acc
     FROM eshop.payment_info pi
     WHERE pi.id = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_admin_for_bank_account(bank_acc);

     -- FIX: Retrieve ID as well (stored in associated_order_id)
     SELECT o.occasion, o.id
     INTO occasion_id, associated_order_id
     FROM eshop.orders o
     WHERE o.payment_info = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_editor_order_on_occasion(occasion_id);
    
    -- Check if the transaction is linked to the specified payment_info
    IF NOT EXISTS (
        SELECT 1
        FROM eshop.transactions
        WHERE id = p_transaction_id
          AND payment_info = p_payment_info_id
    ) THEN
        RAISE EXCEPTION 'Transaction % is not linked to Payment Info %.', p_transaction_id, p_payment_info_id;
    END IF;

    -- Retrieve the transaction amount, currency and TYPE
    SELECT t.amount, t.currency, t.transaction_type
    INTO transaction_amount, transaction_currency, transaction_type
    FROM eshop.transactions t
    WHERE t.id = p_transaction_id
      AND t.payment_info = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % not found.', p_transaction_id;
    END IF;

    IF transaction_type != 'manual' THEN
         RAISE EXCEPTION 'Transaction % is not of type manual (cash). Cannot delete non-manual transactions via this operation.', p_transaction_id;
    END IF;

    -- Retrieve the payment_info currency_code
    SELECT pi.currency_code
    INTO payment_info_currency
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment Info % does not exist.', p_payment_info_id;
    END IF;

    -- Check if currencies match
    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch: Transaction currency (%) does not match Payment Info currency (%)', transaction_currency, payment_info_currency;
    END IF;

    -- Adjust the paid or returned column based on the transaction amount
    IF transaction_amount > 0 THEN
        -- Ensure that the payment_info has enough 'paid' amount to deduct
        IF (SELECT COALESCE(paid, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient paid amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) - transaction_amount
        WHERE id = p_payment_info_id;
    ELSE
        -- Transaction was a return; ensure enough 'returned' amount to deduct
        IF (SELECT COALESCE(returned, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient returned amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + transaction_amount
        WHERE id = p_payment_info_id;
    END IF;

    -- Fetch the updated payment_info record
    SELECT *
    INTO payment_info_record
    FROM eshop.payment_info
    WHERE id = p_payment_info_id;

    -- DELETE the transaction entirely
    DELETE FROM eshop.transactions
    WHERE id = p_transaction_id;

    -- FIX: Recalculate Order Status!
    IF associated_order_id IS NOT NULL THEN
        PERFORM public.recalculate_order_payment_status(associated_order_id);
    END IF;

    RAISE NOTICE 'Manual Transaction % successfully deleted from Payment Info %.', p_transaction_id, p_payment_info_id;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to delete Transaction % from Payment Info %: %', p_transaction_id, p_payment_info_id, SQLERRM;
END;
$$;

COMMIT;

INSERT INTO supabase_migrations.schema_migrations (version) VALUES ('20260125190000');
