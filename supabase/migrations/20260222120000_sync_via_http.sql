-- Migration: Replace dblink-based sync with HTTP-based sync.
-- No more database passwords — uses Supabase URL + public anon key.

-- 0. Enable http extension (for existing deployments)
CREATE EXTENSION IF NOT EXISTS http WITH SCHEMA extensions;

-- 1. Add new columns to external_sync_sources
ALTER TABLE public.external_sync_sources
    ADD COLUMN IF NOT EXISTS supabase_url TEXT,
    ADD COLUMN IF NOT EXISTS anon_key TEXT;

-- 3. Drop old dblink columns (after migration)
ALTER TABLE public.external_sync_sources
    DROP COLUMN IF EXISTS src_host,
    DROP COLUMN IF EXISTS src_port,
    DROP COLUMN IF EXISTS src_db,
    DROP COLUMN IF EXISTS src_user,
    DROP COLUMN IF EXISTS encrypted_password;

-- 4. Drop old dblink-based functions
DROP FUNCTION IF EXISTS public.sync_source_via_dblink(text);
DROP FUNCTION IF EXISTS public.setup_external_source_dblink(text, text, text, text, integer, text, text);

-- 5. Create get_sync_occasions (public RPC — deployed on every instance)
CREATE OR REPLACE FUNCTION public.get_sync_occasions(
    p_organization_id BIGINT DEFAULT NULL,
    p_unit_id BIGINT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', o.id,
            'link', o.link,
            'title', o.title,
            'description', o.description,
            'data', o.data,
            'start_time', o.start_time,
            'end_time', o.end_time,
            'is_open', o.is_open,
            'is_hidden', o.is_hidden,
            'is_promoted', o.is_promoted,
            'features', o.features,
            'created_at', o.created_at,
            'form_link', (
                SELECT f.link
                FROM public.forms f
                WHERE f.occasion = o.id
                ORDER BY f.is_open DESC, f.id
                LIMIT 1
            )
        )
        ORDER BY o.start_time DESC
    ), '[]'::jsonb)
    INTO result
    FROM public.occasions o
    WHERE o.is_open = true
      AND o.is_hidden = false
      AND o.is_promoted = true
      AND (p_organization_id IS NULL OR o.organization = p_organization_id)
      AND (p_unit_id IS NULL OR o.unit = p_unit_id);

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO service_role;

-- 6. Create sync_source_via_http
CREATE OR REPLACE FUNCTION public.sync_source_via_http(p_target_source_name TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    r_source RECORD;
    r_map RECORD;
    r_occ RECORD;
    v_response extensions.http_response;
    v_body jsonb;
    v_external_link TEXT;
    v_features JSONB;
    v_local_data JSONB;
    v_remaining_places INTEGER;
    v_count INTEGER := 0;
    v_synced_ids BIGINT[];
BEGIN
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    FOR r_source IN
        SELECT * FROM public.external_sync_sources
        WHERE (p_target_source_name IS NULL OR source_name = p_target_source_name)
    LOOP
        v_synced_ids := ARRAY[]::BIGINT[];

        FOR r_map IN SELECT * FROM public.external_sync_maps WHERE source_name = r_source.source_name
        LOOP
            SELECT * INTO v_response FROM extensions.http((
                'POST',
                format('%s/rest/v1/rpc/get_sync_occasions', r_source.supabase_url),
                ARRAY[
                    extensions.http_header('apikey', r_source.anon_key),
                    extensions.http_header('Authorization', format('Bearer %s', r_source.anon_key))
                ],
                'application/json',
                json_build_object(
                    'p_organization_id', r_map.remote_org_id,
                    'p_unit_id', r_map.remote_unit_id
                )::text
            )::extensions.http_request);

            IF v_response.status <> 200 THEN
                RAISE NOTICE 'HTTP call failed for source % map %: status=%, body=%',
                    r_source.source_name, r_map.id, v_response.status, left(v_response.content, 200);
                CONTINUE;
            END IF;

            v_body := v_response.content::jsonb;

            FOR r_occ IN
                SELECT
                    (elem->>'id')::bigint AS id,
                    elem->>'link' AS link,
                    elem->>'title' AS title,
                    elem->>'description' AS description,
                    (elem->'data') AS data,
                    (elem->>'start_time')::timestamptz AS start_time,
                    (elem->>'end_time')::timestamptz AS end_time,
                    (elem->>'is_open')::boolean AS is_open,
                    (elem->>'is_hidden')::boolean AS is_hidden,
                    (elem->>'is_promoted')::boolean AS is_promoted,
                    (elem->'features') AS features,
                    (elem->>'created_at')::timestamptz AS created_at,
                    elem->>'form_link' AS form_link
                FROM jsonb_array_elements(v_body) AS elem
            LOOP
                v_synced_ids := array_append(v_synced_ids, r_occ.id);
                v_remaining_places := (r_occ.data->>'remaining_places')::INTEGER;

                INSERT INTO public.external_occasions_cache (external_id, link, remaining_places, raw_data, last_synced_at, source_name)
                VALUES (r_occ.id, r_occ.link, v_remaining_places, row_to_json(r_occ)::jsonb, NOW(), r_source.source_name)
                ON CONFLICT (source_name, external_id) DO UPDATE SET
                    link = EXCLUDED.link,
                    remaining_places = EXCLUDED.remaining_places,
                    raw_data = EXCLUDED.raw_data,
                    last_synced_at = NOW();

                SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_features
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' <> 'form';

                SELECT elem INTO v_local_data
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' = 'form'
                LIMIT 1;

                IF (v_local_data->>'use_external_form')::boolean = true OR
                   (v_local_data->>'formUseExternal')::boolean = true OR
                   (v_local_data->'data'->>'use_external_form')::boolean = true OR
                   (v_local_data->'data'->>'formUseExternal')::boolean = true
                THEN
                    v_external_link := COALESCE(
                        v_local_data->>'external_form_link',
                        v_local_data->>'formExternalLink',
                        v_local_data->'data'->>'external_form_link',
                        v_local_data->'data'->>'formExternalLink'
                    );
                ELSE
                    v_external_link := r_map.remote_link_base || '/form/' || COALESCE(r_occ.form_link, r_occ.link);
                END IF;

                v_features := v_features || jsonb_build_array(jsonb_build_object(
                    'code', 'form',
                    'is_enabled', true,
                    'data', jsonb_build_object(
                        'use_external_form', true,
                        'external_form_link', v_external_link
                    )
                ));

                v_local_data := r_occ.data;
                IF v_local_data IS NULL THEN v_local_data := '{}'::jsonb; END IF;
                IF v_remaining_places IS NOT NULL THEN
                    v_local_data := jsonb_set(v_local_data, '{remaining_places}', to_jsonb(v_remaining_places));
                END IF;

                INSERT INTO public.occasions (
                    link, title, description, data, start_time, end_time,
                    is_open, is_hidden, is_promoted,
                    organization, unit, features,
                    created_at, updated_at,
                    external_source, external_id
                )
                VALUES (
                    r_occ.link, r_occ.title, r_occ.description, v_local_data,
                    r_occ.start_time, r_occ.end_time,
                    r_occ.is_open, r_occ.is_hidden, r_occ.is_promoted,
                    r_map.target_org_id, r_map.target_unit_id, v_features,
                    r_occ.created_at, NOW(),
                    r_source.source_name, r_occ.id
                )
                ON CONFLICT (external_source, external_id) DO UPDATE SET
                    link = EXCLUDED.link,
                    title = EXCLUDED.title,
                    description = EXCLUDED.description,
                    data = EXCLUDED.data,
                    start_time = EXCLUDED.start_time,
                    end_time = EXCLUDED.end_time,
                    is_open = EXCLUDED.is_open,
                    is_hidden = EXCLUDED.is_hidden,
                    features = EXCLUDED.features,
                    organization = EXCLUDED.organization,
                    unit = EXCLUDED.unit,
                    updated_at = NOW();
                v_count := v_count + 1;
            END LOOP;
        END LOOP;

        IF array_length(v_synced_ids, 1) > 0 THEN
            DELETE FROM public.occasions
            WHERE external_source = r_source.source_name
              AND NOT (external_id = ANY(v_synced_ids));
            DELETE FROM public.external_occasions_cache
            WHERE source_name = r_source.source_name
              AND NOT (external_id = ANY(v_synced_ids));
        ELSE
            DELETE FROM public.occasions WHERE external_source = r_source.source_name;
            DELETE FROM public.external_occasions_cache WHERE source_name = r_source.source_name;
        END IF;
    END LOOP;

    RETURN format('Synced %s occasions from %s.', v_count, COALESCE(p_target_source_name, 'ALL Sources'));
EXCEPTION WHEN OTHERS THEN
    RETURN format('Error: %s', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http(text) TO service_role;

-- 7. Create setup_external_source
CREATE OR REPLACE FUNCTION public.setup_external_source(
    p_source_name TEXT,
    p_supabase_url TEXT,
    p_anon_key TEXT,
    p_cron_schedule TEXT DEFAULT '*/5 * * * *'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_job_name TEXT := 'sync_job_' || p_source_name;
BEGIN
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    INSERT INTO public.external_sync_sources (source_name, supabase_url, anon_key, cron_schedule)
    VALUES (p_source_name, p_supabase_url, p_anon_key, p_cron_schedule)
    ON CONFLICT (source_name) DO UPDATE SET
        supabase_url = EXCLUDED.supabase_url,
        anon_key = EXCLUDED.anon_key,
        cron_schedule = EXCLUDED.cron_schedule;

    BEGIN
        PERFORM cron.unschedule(v_job_name);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    PERFORM cron.schedule(
        v_job_name,
        p_cron_schedule,
        format('SELECT public.sync_source_via_http(%L)', p_source_name)
    );

    RETURN format('Source "%s" configured with %s schedule.', p_source_name, p_cron_schedule);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.setup_external_source(text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.setup_external_source(text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.setup_external_source(text, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.setup_external_source(text, text, text, text) TO service_role;

-- 8. Reschedule existing cron jobs to use new function
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT source_name, cron_schedule FROM public.external_sync_sources
    LOOP
        BEGIN
            PERFORM cron.unschedule('sync_job_' || r.source_name);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        PERFORM cron.schedule(
            'sync_job_' || r.source_name,
            r.cron_schedule,
            format('SELECT public.sync_source_via_http(%L)', r.source_name)
        );
    END LOOP;
END;
$$;
