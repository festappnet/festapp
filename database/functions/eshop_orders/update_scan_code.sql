CREATE OR REPLACE FUNCTION update_scan_code(
    occasion_link TEXT,
    new_scan_code TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    occasions_hidden_id BIGINT;
    previous_scan_code TEXT;
BEGIN
    -- 1. Retrieve occasion_id using occasion_link
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- 2. Check if occasion_link is valid
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion link does not exist.'
        );
    END IF;

    -- 3. Verify if the user is an editor on the occasion
    IF NOT can_write_orders(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to edit this occasion.'
        );
    END IF;

    IF new_scan_code IS NULL OR btrim(new_scan_code)='' THEN
        RETURN jsonb_build_object('code',400,'message','Scan code must not be empty.');
    END IF;

    -- Per-event locking owns rotation; the unique index arbitrates cross-event collisions.
    PERFORM 1 FROM public.occasions WHERE id=v_occasion_id FOR UPDATE;
    PERFORM 1 FROM public.scanner_settings WHERE scanner_settings.occasion_id=v_occasion_id FOR UPDATE;
    -- 4. Check if occasions_hidden exists for the occasion
    SELECT o.occasion_hidden
    INTO occasions_hidden_id
    FROM public.occasions o
    WHERE o.id = v_occasion_id;

    SELECT secret INTO previous_scan_code FROM public.occasions_hidden
    WHERE id=occasions_hidden_id FOR UPDATE;
    -- Do not gradually revive a credential that every copied event already knows.
    -- Historical groups need one explicit repair that retires their shared proof.
    IF EXISTS (SELECT 1 FROM public.occasions o
        WHERE o.occasion_hidden=occasions_hidden_id AND o.id<>v_occasion_id) THEN
        RETURN jsonb_build_object('code',409,'reason','shared_scan_credential',
            'message','Copied occasions require separate scanner links from an administrator.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.scanner_revoked_credentials revoked
        WHERE revoked.secret_hash=encode(extensions.digest(new_scan_code,'sha256'),'hex')) THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.occasions_hidden h WHERE h.secret=new_scan_code
        AND (h.id IS DISTINCT FROM occasions_hidden_id OR EXISTS (
            SELECT 1 FROM public.occasions o
            WHERE o.occasion_hidden=h.id AND o.id<>v_occasion_id
        ))
    ) THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    END IF;

    IF occasions_hidden_id IS NOT NULL THEN
        -- The existing record is exclusively owned by this event.
        -- Rotation must not allow a future event to inherit its old bearer URL.
        IF previous_scan_code IS NOT NULL AND previous_scan_code IS DISTINCT FROM new_scan_code THEN
            INSERT INTO public.scanner_revoked_credentials(secret_hash,reason)
            VALUES(encode(extensions.digest(previous_scan_code,'sha256'),'hex'),'rotated')
            ON CONFLICT(secret_hash) DO NOTHING;
        END IF;
        UPDATE public.occasions_hidden
        SET secret = new_scan_code
        WHERE id = occasions_hidden_id;
    ELSE
        -- Insert new occasions_hidden record
        INSERT INTO public.occasions_hidden (secret)
        VALUES (new_scan_code)
        RETURNING id INTO occasions_hidden_id;

        -- Update the occasion to link to the new occasions_hidden
        UPDATE public.occasions
        SET occasion_hidden = occasions_hidden_id
        WHERE id = v_occasion_id;
    END IF;

    UPDATE public.scanner_settings SET epoch=epoch+1 WHERE scanner_settings.occasion_id=v_occasion_id;

    -- 5. Return a success message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Scan code updated successfully.'
    );

EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object('code',409,'reason','scan_code_collision','message','Scan code is already in use.');
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

REVOKE ALL ON FUNCTION public.update_scan_code(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_scan_code(text,text) TO authenticated,service_role;
