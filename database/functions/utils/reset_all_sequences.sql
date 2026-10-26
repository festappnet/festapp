CREATE OR REPLACE FUNCTION public.reset_all_sequences()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    r RECORD;
    v_seq_last_value bigint;
    v_max_id bigint;
    v_sql text;
BEGIN
    FOR r IN 
        SELECT 
            table_schema, 
            table_name, 
            column_name,
            pg_get_serial_sequence('"' || table_schema || '"."' || table_name || '"', column_name) AS seq
        FROM information_schema.columns
        WHERE table_schema IN ('public', 'eshop')
          AND (column_default LIKE 'nextval%' OR is_identity = 'YES')
          AND pg_get_serial_sequence('"' || table_schema || '"."' || table_name || '"', column_name) IS NOT NULL
    LOOP
        -- Get Sequence Last Value safely
        EXECUTE 'SELECT last_value FROM ' || r.seq INTO v_seq_last_value;
        
        -- Get Max ID
        EXECUTE 'SELECT COALESCE(MAX(' || quote_ident(r.column_name) || '), 0) FROM "' || r.table_schema || '"."' || r.table_name || '"' INTO v_max_id;

        -- Calculate Safe Value: Higher of (MaxID, CurrentSeq) + 1
        -- We won't rewind the sequence, preventing collisions with in-flight transactions
        IF v_max_id >= v_seq_last_value THEN
            -- Only update if data is ahead of sequence (Import scenario)
            -- Or strictly sync them.
            -- To be SAFE, we use GREATEST.
            -- setval(seq, val, false) -> next nextval returns val.
            v_sql := 'SELECT setval(''' || r.seq || ''', ' || (GREATEST(v_max_id, v_seq_last_value) + 1) || ', false)';
            EXECUTE v_sql;
        END IF;
        
        -- Note: If v_seq_last_value > v_max_id, we do nothing (preserve potential in-flight IDs)
        -- Unless the user specifically WANTS to rewind (which is dangerous).
        -- The user asked to "reset ... to max current record", which implies fixing broken imports.
        -- But also "make this safe".
        -- The ONLY safe way is to NEVER rewind below last_value.
    END LOOP;
END;
$$;


-- Strict Permissions (Validated)
REVOKE ALL ON FUNCTION public.reset_all_sequences() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reset_all_sequences() FROM anon;
REVOKE ALL ON FUNCTION public.reset_all_sequences() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reset_all_sequences TO service_role;
