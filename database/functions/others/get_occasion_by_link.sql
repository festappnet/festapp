-- Create a function to get occasion by link and check for active orders
CREATE OR REPLACE FUNCTION public.get_occasion_by_link(link_param text)
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
    -- Legacy links may repeat across tenants after the canonical merge.
    -- This RPC supplies editor data, so resolve only inside the caller's tenant.
    SELECT o.* INTO occ_record
    FROM public.occasions o
    WHERE o.link = link_param
      AND o.organization = (
          SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()
      );

    -- Return null if not found
    IF occ_record IS NULL THEN
        RETURN NULL;
    END IF;

    IF public.is_demo_occasion(occ_record.id) AND NOT public.can_read_demo_occasion(occ_record.id) THEN
        RAISE insufficient_privilege USING MESSAGE='Demo access denied';
    END IF;

    IF NOT (public.get_is_editor_view_on_occasion(occ_record.id)
        OR public.get_is_manager_on_occasion(occ_record.id)
        OR public.get_is_admin_on_occasion(occ_record.id)) THEN
        RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
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
