CREATE OR REPLACE FUNCTION public.get_report_ws(occasion_link TEXT)
RETURNS jsonb SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
    occasion_id bigint;
    report_data text;
BEGIN
    SELECT o.id
    INTO occasion_id
    FROM public.occasions o
    WHERE o.link = occasion_link
      AND o.organization = (
        SELECT ui.organization
        FROM public.user_info ui
        WHERE ui.id = auth.uid()
      );

    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for link: %', occasion_link;
    END IF;

    IF NOT public.get_is_editor_order_view_on_occasion(occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view this report.';
    END IF;

    report_data := public.get_report_for_occasion(occasion_id);

    RETURN jsonb_build_object(
        'code', 200,
        'data', report_data
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$$ LANGUAGE plpgsql;
