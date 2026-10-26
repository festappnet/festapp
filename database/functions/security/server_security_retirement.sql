-- No active application, stored-function, dependency or cron caller found.
-- No CASCADE: an unexpected dependency aborts this contraction, keeping containment.
DROP FUNCTION IF EXISTS public.migrate_users_to_org(bigint);
DROP FUNCTION IF EXISTS public.update_spot(jsonb);
DROP FUNCTION IF EXISTS public.apply_allocations_claim_only(bigint);
DROP FUNCTION IF EXISTS public.send_email_mailersend(jsonb,jsonb);
