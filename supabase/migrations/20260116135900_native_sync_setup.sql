-- Enable Extensions (No Vault)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Create Cache Table
CREATE TABLE IF NOT EXISTS public.external_occasions_cache (
    link TEXT PRIMARY KEY,
    remaining_places INTEGER,
    raw_data JSONB,
    last_synced_at TIMESTAMPTZ DEFAULT NOW(),
    source_name TEXT
);

ALTER TABLE public.external_occasions_cache ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow service role full access" ON public.external_occasions_cache;
CREATE POLICY "Allow service role full access" ON public.external_occasions_cache USING (true) WITH CHECK (true);

-- 2. Configuration Table (Source Connection Details)
CREATE TABLE IF NOT EXISTS public.external_sync_sources (
    source_name TEXT PRIMARY KEY,
    
    -- Connection Details
    src_host TEXT NOT NULL,
    src_port INTEGER DEFAULT 5432,
    src_db TEXT DEFAULT 'postgres',
    src_user TEXT DEFAULT 'postgres',
    
    encrypted_password TEXT, -- PGCrypto Encrypted
    cron_schedule TEXT DEFAULT '*/5 * * * *', -- Store schedule for reference
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.external_sync_sources ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow service role full access" ON public.external_sync_sources;
CREATE POLICY "Allow service role full access" ON public.external_sync_sources USING (true) WITH CHECK (true);

-- 3. Mapping Table (Routing Rules)
CREATE TABLE IF NOT EXISTS public.external_sync_maps (
    id SERIAL PRIMARY KEY,
    source_name TEXT NOT NULL REFERENCES public.external_sync_sources(source_name) ON DELETE CASCADE,
    
    target_org_id BIGINT NOT NULL,
    target_unit_id BIGINT NOT NULL,
    remote_link_base TEXT NOT NULL,
    
    remote_org_id BIGINT,
    remote_unit_id BIGINT
);
ALTER TABLE public.external_sync_maps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow service role full access" ON public.external_sync_maps;
CREATE POLICY "Allow service role full access" ON public.external_sync_maps USING (true) WITH CHECK (true);

-- 4. FUNCTION: SYNC (Using pgp_sym_decrypt)
CREATE OR REPLACE FUNCTION public.sync_source_via_dblink(p_target_source_name TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r_source RECORD;
    r_map RECORD;
    v_password TEXT;
    v_conn_str TEXT;
    v_query TEXT;
    r_occ RECORD;
    v_external_link TEXT;
    v_features JSONB;
    v_local_data JSONB;
    v_remaining_places INTEGER;
    v_count INTEGER := 0;
    v_enc_key TEXT := 'festapp_internal_sync_key'; -- Internal Key
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    FOR r_source IN 
        SELECT * FROM public.external_sync_sources 
        WHERE (p_target_source_name IS NULL OR source_name = p_target_source_name)
    LOOP
        -- Decrypt Password
        BEGIN
            v_password := pgp_sym_decrypt(r_source.encrypted_password::bytea, v_enc_key);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Failed to decrypt password for source %', r_source.source_name;
            CONTINUE;
        END;
        
        v_conn_str := format('host=%s port=%s dbname=%s user=%s password=%s', 
                             r_source.src_host, r_source.src_port, r_source.src_db, r_source.src_user, v_password);

        FOR r_map IN SELECT * FROM public.external_sync_maps WHERE source_name = r_source.source_name
        LOOP
             -- Subquery to get Form Link
             v_query := 'SELECT o.link, o.title, o.description, o.data, o.start_time, o.end_time, o.is_open, o.is_hidden, o.is_promoted, o.features, o.created_at, (SELECT f.link FROM public.forms f WHERE f.occasion = o.id ORDER BY f.is_open DESC, f.id LIMIT 1) as form_link FROM public.occasions o WHERE o.is_open = true AND o.is_hidden = false';
             IF r_map.remote_org_id IS NOT NULL THEN
                 v_query := v_query || ' AND o.organization = ' || r_map.remote_org_id;
             END IF;
             IF r_map.remote_unit_id IS NOT NULL THEN
                 v_query := v_query || ' AND o.unit = ' || r_map.remote_unit_id;
             END IF;
             
             FOR r_occ IN 
                SELECT * FROM dblink(v_conn_str, v_query) 
                AS remote_data(
                    link text, title text, description text, data jsonb, 
                    start_time timestamptz, end_time timestamptz, 
                    is_open boolean, is_hidden boolean, is_promoted boolean, 
                    features jsonb, created_at timestamptz,
                    form_link text
                )
             LOOP
                 v_remaining_places := (r_occ.data->>'remaining_places')::INTEGER;
                 INSERT INTO public.external_occasions_cache (link, remaining_places, raw_data, last_synced_at, source_name)
                 VALUES (r_occ.link, v_remaining_places, row_to_json(r_occ)::jsonb, NOW(), r_source.source_name)
                 ON CONFLICT (link) DO UPDATE SET
                    remaining_places = EXCLUDED.remaining_places,
                    raw_data = EXCLUDED.raw_data,
                    last_synced_at = NOW();

                 -- Use Form Link specifically
                 v_external_link := r_map.remote_link_base || '/form/' || COALESCE(r_occ.form_link, r_occ.link);
                 v_features := jsonb_build_array(jsonb_build_object(
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
                    created_at, updated_at
                 )
                 VALUES (
                    r_occ.link, r_occ.title, r_occ.description, v_local_data, 
                    r_occ.start_time, r_occ.end_time,
                    r_occ.is_open, r_occ.is_hidden, r_occ.is_promoted,
                    r_map.target_org_id, r_map.target_unit_id, v_features,
                    r_occ.created_at, NOW()
                 )
                 ON CONFLICT (link) DO UPDATE SET
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
    END LOOP;
    RETURN format('Synced %s occasions from %s.', v_count, COALESCE(p_target_source_name, 'ALL Sources'));
EXCEPTION WHEN OTHERS THEN
    RETURN format('Error: %s', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.sync_source_via_dblink(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_dblink(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_source_via_dblink(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.sync_source_via_dblink(text) TO service_role;

-- 5. FUNCTION: SETUP (Using pgp_sym_encrypt and graceful unschedule)
CREATE OR REPLACE FUNCTION public.setup_external_source_dblink(
    p_source_name TEXT,
    p_host TEXT,
    p_user TEXT,
    p_password TEXT,
    p_port INTEGER DEFAULT 5432,
    p_db TEXT DEFAULT 'postgres',
    p_cron_schedule TEXT DEFAULT '*/5 * * * *'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_job_name TEXT := 'sync_job_' || p_source_name;
    v_enc_key TEXT := 'festapp_internal_sync_key'; -- Internal Key
    v_encrypted_pass TEXT;
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    -- Encrypt Password
    v_encrypted_pass := pgp_sym_encrypt(p_password, v_enc_key);

    INSERT INTO public.external_sync_sources (source_name, src_host, src_user, src_port, src_db, encrypted_password, cron_schedule)
    VALUES (p_source_name, p_host, p_user, p_port, p_db, v_encrypted_pass, p_cron_schedule)
    ON CONFLICT (source_name) DO UPDATE SET
        src_host = EXCLUDED.src_host,
        src_user = EXCLUDED.src_user,
        src_port = EXCLUDED.src_port,
        src_db = EXCLUDED.src_db,
        encrypted_password = EXCLUDED.encrypted_password,
        cron_schedule = EXCLUDED.cron_schedule;

    -- Gracefully Unschedule if exists
    BEGIN
        PERFORM cron.unschedule(v_job_name);
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Ignore if job doesn't exist
    END;

    PERFORM cron.schedule(
        v_job_name,
        p_cron_schedule,
        format('SELECT public.sync_source_via_dblink(%L)', p_source_name)
    );

    RETURN format('Source "%s" configured with %s schedule.', p_source_name, p_cron_schedule);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.setup_external_source_dblink(text, text, text, text, integer, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.setup_external_source_dblink(text, text, text, text, integer, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.setup_external_source_dblink(text, text, text, text, integer, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.setup_external_source_dblink(text, text, text, text, integer, text, text) TO service_role;

-- 6. FUNCTION: ADD MAP
CREATE OR REPLACE FUNCTION public.add_sync_map(
    p_source_name TEXT,
    p_target_org_id BIGINT,
    p_target_unit_id BIGINT,
    p_remote_link_base TEXT,
    p_remote_org_id BIGINT DEFAULT NULL,
    p_remote_unit_id BIGINT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    INSERT INTO public.external_sync_maps 
    (source_name, target_org_id, target_unit_id, remote_link_base, remote_org_id, remote_unit_id)
    VALUES 
    (p_source_name, p_target_org_id, p_target_unit_id, p_remote_link_base, p_remote_org_id, p_remote_unit_id);
    RETURN 'Map added.';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM anon;
REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_sync_map TO service_role;
