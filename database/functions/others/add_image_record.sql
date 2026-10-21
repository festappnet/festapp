-- The existing gallery insertion/admission/sync owner, shared by verified
-- blueprint processing and the original permission-checked public wrapper.
CREATE OR REPLACE FUNCTION public.add_image_record_internal(p_link text,p_occasion_id bigint,p_unit_id bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_image_id bigint;
BEGIN
    -- Insert Record
    PERFORM public.admit_image_record_budget_internal(p_link,p_occasion_id,p_unit_id);
    INSERT INTO public.images (link, occasion, unit)
    VALUES (p_link, p_occasion_id, p_unit_id)
    RETURNING id INTO v_image_id;

    IF p_occasion_id IS NOT NULL THEN
      PERFORM public.record_client_sync_commit_v1(
        p_occasion_id,'image.add','content',jsonb_build_array(jsonb_build_object(
          'entityType','occasion_image','entityId',v_image_id::text,
          'operation','insert','safeLabel',left(p_link,240),
          'changedFields',jsonb_build_array('link'))),
        ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'user',NULL);
    END IF;
 RETURN v_image_id;
END $$;
REVOKE ALL ON FUNCTION public.add_image_record_internal(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.add_image_record(p_link text, p_occasion_id bigint, p_unit_id bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE v_image_id bigint;
BEGIN
    -- Scope is an exclusive owner, never a caller-supplied unit that masks
    -- an unrelated occasion. Check it before any budget or metadata write.
    IF (p_unit_id IS NULL)=(p_occasion_id IS NULL) THEN
        RAISE insufficient_privilege USING MESSAGE='exactly one authorized image owner required';
    END IF;
    -- Permission Check
    IF p_unit_id IS NOT NULL THEN
        -- Unit Editor
        IF (SELECT public.can_upload_unit_media(p_unit_id)) IS NOT TRUE THEN
            RAISE EXCEPTION 'Permission denied: User is not an editor of this unit.';
        END IF;
    ELSIF p_occasion_id IS NOT NULL THEN
        -- Occasion Editor OR Occasion Order Editor
        IF public.can_upload_occasion_media(p_occasion_id) IS NOT TRUE THEN
             RAISE EXCEPTION 'Permission denied: User is not an editor/order-editor of this occasion.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Entity ID (unit or occasion) must be provided.';
    END IF;

    PERFORM public.add_image_record_internal(p_link,p_occasion_id,p_unit_id);

END;
$$;
