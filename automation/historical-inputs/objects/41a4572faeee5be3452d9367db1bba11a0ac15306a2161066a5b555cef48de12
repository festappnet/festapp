-- Seed data for local Supabase development
-- Creates a test organization with admin user t@t.com
-- Idempotent: safe to run on supabase db reset

DO $$
DECLARE
    v_org_id bigint;
BEGIN
    SELECT id INTO v_org_id FROM organizations WHERE title = 'Test Organization' LIMIT 1;

    IF v_org_id IS NULL THEN
        -- Create test org + admin user via existing seed function
        -- seed_org_with_admin creates: organization, unit, admin user with full rights
        PERFORM seed_org_with_admin('t@t.com', 'test');

        -- Update the organization title to our expected name
        UPDATE organizations
        SET title = 'Test Organization'
        WHERE title = 'Seed Organization';

        RAISE NOTICE 'Created test organization and user t@t.com';
    ELSE
        RAISE NOTICE 'Test organization already exists, skipping seed';
    END IF;
END $$;
