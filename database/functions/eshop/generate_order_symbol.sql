-- Private candidate generator. The global constraint owns uniqueness.
CREATE OR REPLACE FUNCTION public.generate_order_symbol()
RETURNS text LANGUAGE plpgsql VOLATILE
SET search_path = public, extensions AS $$
DECLARE
    alphabets text[] := ARRAY['123456789', 'ACEFGHIJKLMNPQRUVWXY'];
    bytes bytea := extensions.gen_random_bytes(64);
    pos integer := 0;
    b integer;
    alphabet text;
    symbol text := '';
BEGIN
    FOR pair IN 1..5 LOOP
        FOREACH alphabet IN ARRAY alphabets LOOP
            LOOP
                IF pos = length(bytes) THEN
                    bytes := extensions.gen_random_bytes(64);
                    pos := 0;
                END IF;
                b := get_byte(bytes, pos);
                pos := pos + 1;
                EXIT WHEN b < 256 - (256 % length(alphabet));
            END LOOP;
            symbol := symbol || substr(alphabet, (b % length(alphabet)) + 1, 1);
        END LOOP;
    END LOOP;
    RETURN symbol;
END;
$$;
ALTER FUNCTION public.generate_order_symbol() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.generate_order_symbol() FROM PUBLIC, anon, authenticated, service_role;
