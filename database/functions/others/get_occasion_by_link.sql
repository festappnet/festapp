-- Create a function to get occasion by link and check for active orders
CREATE OR REPLACE FUNCTION get_occasion_by_link(link_param text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occ_record public.occasions;
    has_orders boolean;
    result jsonb;
BEGIN
    -- 1. Fetch the occasion record
    SELECT * INTO occ_record
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(link_param);

    -- Return null if not found
    IF occ_record IS NULL THEN
        RETURN NULL;
    END IF;

    IF public.is_demo_occasion(occ_record.id) AND NOT public.can_read_demo_occasion(occ_record.id) THEN
        RAISE insufficient_privilege USING MESSAGE='Demo access denied';
    END IF;

    -- 2. Check for active orders
    SELECT EXISTS (
        SELECT 1
        FROM eshop.orders
        WHERE occasion = occ_record.id
    ) INTO has_orders;

    -- 3. Merge the occasion record with the new boolean flag
    result := to_jsonb(occ_record) || jsonb_build_object('has_orders', has_orders);

    RETURN result;
END;
$$;