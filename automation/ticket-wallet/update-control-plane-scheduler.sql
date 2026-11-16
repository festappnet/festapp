-- PREPARED ONLY. Run in the verified control-plane postgres DB after cutover probes.
-- psql -v runtime_database=... -v scheduler_owner=... -f this_file
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE wallet_scheduler_target(database_name text,owner_name text) ON COMMIT DROP;
INSERT INTO wallet_scheduler_target VALUES(:'runtime_database',:'scheduler_owner');
DO $$
DECLARE j record; target record;
BEGIN
 SELECT * INTO STRICT target FROM wallet_scheduler_target;
 SELECT * INTO STRICT j FROM cron.job WHERE jobname='festapp_google_ticket_wallet';
 IF j.database IS DISTINCT FROM target.database_name OR j.username IS DISTINCT FROM target.owner_name
 OR j.command NOT LIKE '%public.wake_ticket_wallet_worker()%'
 OR (SELECT count(*) FROM cron.job WHERE command LIKE '%public.wake_ticket_wallet_worker()%')<>1 THEN
  RAISE EXCEPTION 'wallet_scheduler_identity_or_single_owner_mismatch';
 END IF;
 -- Preserve trusted command, database, owner and active state. No second job.
 PERFORM cron.alter_job(j.jobid,schedule:='10 seconds');
END $$;
COMMIT;
SELECT jobid,jobname,schedule,database,username,active FROM cron.job WHERE jobname='festapp_google_ticket_wallet';
