CREATE OR REPLACE FUNCTION public.update_ticket_to_unused_ws(
    ticket_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    updated_count integer;
BEGIN
    SELECT occasion
    INTO STRICT occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

    UPDATE eshop.tickets
    SET
        -- `sent` is the canonical unused state that can be scanned again.
        state = 'sent',
        updated_at = now()
    WHERE id = ticket_id
      AND state = 'used';

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    IF updated_count <> 1 THEN
        RAISE EXCEPTION 'Ticket % is not used.', ticket_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_ticket_to_unused_ws(bigint)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_ticket_to_unused_ws(bigint)
TO authenticated, service_role;
