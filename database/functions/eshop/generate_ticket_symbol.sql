CREATE OR REPLACE FUNCTION generate_ticket_symbol(organization_id BIGINT, occasion_id BIGINT)
RETURNS TEXT
SET search_path = public, extensions AS $$
DECLARE
    visible_id TEXT;
    org_suffix TEXT;
    occasion_suffix TEXT;
    numeric_part TEXT := '123456789';
    alphabetic_part TEXT := 'ACEFGHIJKLMNPQRUVWXY';
    attempt_count INT := 0;
BEGIN
    -- Extract last two digits of organization_id and occasion_id
    org_suffix := LPAD((organization_id % 100)::TEXT, 2, '0');  -- Ensure 2 digits
    occasion_suffix := LPAD((occasion_id % 100)::TEXT, 2, '0'); -- Ensure 2 digits

    -- Replace '0' with 'X' in the suffixes
    org_suffix := REPLACE(org_suffix, '0', 'X');
    occasion_suffix := REPLACE(occasion_suffix, '0', 'X');

    LOOP
        -- Generate alternating numeric and alphabetic parts
        visible_id := org_suffix || occasion_suffix ||
                      SUBSTRING(numeric_part FROM FLOOR(RANDOM() * 9 + 1)::INT FOR 1) ||
                      SUBSTRING(alphabetic_part FROM FLOOR(RANDOM() * 20 + 1)::INT FOR 1) ||
                      SUBSTRING(numeric_part FROM FLOOR(RANDOM() * 9 + 1)::INT FOR 1) ||
                      SUBSTRING(alphabetic_part FROM FLOOR(RANDOM() * 20 + 1)::INT FOR 1) ||
                      SUBSTRING(numeric_part FROM FLOOR(RANDOM() * 9 + 1)::INT FOR 1) ||
                      SUBSTRING(alphabetic_part FROM FLOOR(RANDOM() * 20 + 1)::INT FOR 1);

        -- Ensure uniqueness in the database (within the occasion)
        IF NOT EXISTS (
            SELECT 1
            FROM eshop.tickets
            WHERE ticket_symbol = visible_id AND occasion = occasion_id
        ) THEN
            RETURN visible_id; -- Return the unique visible ID
        END IF;

        -- Increment attempt count and fail after a fixed number of attempts
        attempt_count := attempt_count + 1;
        IF attempt_count > 10 THEN
            RAISE EXCEPTION 'Failed to generate unique visible ID after 10 attempts';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
