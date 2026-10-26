DO $$
BEGIN
    -- Alter the 'name' column to allow NULL values
    ALTER TABLE public.user_info
    ALTER COLUMN name DROP NOT NULL;

END;
$$;