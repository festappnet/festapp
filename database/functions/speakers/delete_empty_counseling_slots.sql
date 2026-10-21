CREATE OR REPLACE FUNCTION public.delete_empty_counseling_slots_internal_v1(p_speaker BIGINT, p_from TIMESTAMPTZ DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion BIGINT;
    v_deleted INT;
    v_ids bigint[]; v_effects jsonb;
BEGIN
    SELECT occasion INTO v_occasion
    FROM public.speakers
    WHERE id = p_speaker;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404);
    END IF;

    IF NOT public.can_write_speakers(v_occasion) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    SELECT ARRAY(SELECT e.id FROM public.events e JOIN public.event_speakers es ON es.event=e.id
      WHERE es.speaker=p_speaker AND (e.data->>'is_counseling_slot')::boolean IS TRUE
      AND (p_from IS NULL OR e.start_time>=p_from)
      AND NOT EXISTS(SELECT 1 FROM public.event_users WHERE event=e.id) ORDER BY e.id) INTO v_ids;
    v_effects:=public.delete_events_domain_internal_v1(v_occasion,v_ids);
    v_deleted:=(v_effects->>'deleted')::integer;

    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object('deleted', v_deleted)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.delete_empty_counseling_slots_internal_v1(bigint,timestamptz) FROM PUBLIC,anon,authenticated;
