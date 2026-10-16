CREATE OR REPLACE FUNCTION public.get_occasion_by_scan_code(scan_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    found_occasion_record RECORD;
BEGIN
    IF NOT public.check_scan_attempt_budget_v1(NULL) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    SELECT o.id, o.title, o.features
    INTO found_occasion_record
    FROM public.occasions o
    JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
    WHERE oh.secret = scan_code
    LIMIT 1;

    IF found_occasion_record IS NULL THEN
        PERFORM public.admit_scan_access_v1(NULL,false);
        RETURN jsonb_build_object('code',401,'message','invalid_scan_code');
    END IF;

    IF NOT public.admit_scan_access_v1(found_occasion_record.id,true) THEN
        RETURN jsonb_build_object('code',429,'message','abuse_limit_exceeded');
    END IF;
    RETURN jsonb_build_object(
        'id', found_occasion_record.id,
        'title', found_occasion_record.title,
        'features', found_occasion_record.features
    );
END;
$$;
