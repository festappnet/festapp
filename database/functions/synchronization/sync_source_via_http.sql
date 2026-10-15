-- Sync occasions from remote Supabase instances via HTTP (replaces dblink version).
-- Uses the `http` PostgreSQL extension to call the remote's get_sync_occasions RPC.
-- No database password needed — only the public Supabase URL and anon key.
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
    v_local_id bigint;
    v_old_org bigint;
    v_count INTEGER := 0;
    v_synced_ids BIGINT[];
BEGIN
    -- Security Check
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
            -- Call remote RPC via HTTP
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

            -- Iterate over returned occasions
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

                -- CACHE UPDATE
                INSERT INTO public.external_occasions_cache (external_id, link, remaining_places, raw_data, last_synced_at, source_name)
                VALUES (r_occ.id, r_occ.link, v_remaining_places, row_to_json(r_occ)::jsonb, NOW(), r_source.source_name)
                ON CONFLICT (source_name, external_id) DO UPDATE SET
                    link = EXCLUDED.link,
                    remaining_places = EXCLUDED.remaining_places,
                    raw_data = EXCLUDED.raw_data,
                    last_synced_at = NOW();

                -- Preserve Features (keep all except form)
                SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_features
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' <> 'form';

                -- Find existing form feature
                SELECT elem INTO v_local_data
                FROM jsonb_array_elements(r_occ.features) elem
                WHERE elem->>'code' = 'form'
                LIMIT 1;

                -- Determine external form link
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

                -- Append enforced external form feature
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

                SELECT id, organization INTO v_local_id,v_old_org FROM public.occasions
                  WHERE external_source=r_source.source_name AND external_id=r_occ.id FOR UPDATE;
                IF v_local_id IS NOT NULL AND v_old_org IS DISTINCT FROM r_map.target_org_id THEN
                  RAISE EXCEPTION 'External occasion tenant cannot change'; END IF;
                -- OCCASION UPSERT
                INSERT INTO public.occasions (
                    link, title, description, data, start_time, end_time,
                    is_open, is_hidden, is_promoted,
                    organization, unit, features,
                    created_at, updated_at,
                    external_source, external_id
                )
                VALUES (
                    '', r_occ.title, r_occ.description, v_local_data,
                    r_occ.start_time, r_occ.end_time,
                    r_occ.is_open, r_occ.is_hidden, r_occ.is_promoted,
                    r_map.target_org_id, r_map.target_unit_id, v_features,
                    r_occ.created_at, NOW(),
                    r_source.source_name, r_occ.id
                )
                ON CONFLICT (external_source, external_id) DO UPDATE SET
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
                    updated_at = NOW()
                RETURNING id INTO v_local_id;
                UPDATE public.occasions SET link=public.reserve_public_link_internal(
                  'occasion',v_local_id,r_occ.link,link IS NULL OR link='') WHERE id=v_local_id;
                v_count := v_count + 1;
            END LOOP;
        END LOOP;

        -- DELETION: Remove occasions no longer present in remote
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

-- Security Hardening
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_http(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_http(text) TO service_role;
