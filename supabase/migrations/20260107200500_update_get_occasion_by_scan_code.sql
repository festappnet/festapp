CREATE OR REPLACE FUNCTION get_occasion_by_scan_code(scan_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    found_occasion_record RECORD;
BEGIN
    SELECT o.id, o.title, o.features
    INTO found_occasion_record
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF found_occasion_record IS NULL THEN
        RAISE EXCEPTION 'Occasion not found for the provided scan code.';
    END IF;

    RETURN jsonb_build_object(
        'id', found_occasion_record.id,
        'title', found_occasion_record.title,
        'features', found_occasion_record.features
    );
END;
$$;
