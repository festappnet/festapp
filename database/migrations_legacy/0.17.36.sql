DO $$
BEGIN
    -- Check if the column 'is_hidden' does NOT exist in 'public.organization_users'
    -- This prevents errors if the migration is run more than once
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'organization_users'
        AND column_name = 'is_hidden'
    ) THEN
        -- Add the 'is_hidden' column
        -- We use DEFAULT false so existing records show up as visible
        ALTER TABLE public.organization_users
        ADD COLUMN is_hidden BOOLEAN NOT NULL DEFAULT false;

        RAISE NOTICE 'Column is_hidden added to public.organization_users';
    ELSE
        RAISE NOTICE 'Column is_hidden already exists in public.organization_users, skipping.';
    END IF;

END;
$$;