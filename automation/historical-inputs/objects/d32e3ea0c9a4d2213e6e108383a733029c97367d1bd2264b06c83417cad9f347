-- Remove helpers from earlier local iterations after all callers are replaced.
-- Deliberately no CASCADE: an overlooked dependency must fail the migration.
DROP FUNCTION IF EXISTS public.demo_entity_can_read(text,bigint);
DROP FUNCTION IF EXISTS public.can_read_demo_bank_account(bigint);
