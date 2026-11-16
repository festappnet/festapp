-- Install only under tenant pause, after the old worker has drained.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM eshop.ticket_wallet_objects WHERE lease_until>clock_timestamp()) THEN
  RAISE EXCEPTION 'wallet_legacy_leases_not_drained';
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE NOT paused) THEN
  RAISE EXCEPTION 'wallet_cutover_requires_pause';
 END IF;
END $$;
DROP INDEX IF EXISTS eshop.ticket_wallet_due;
ALTER TABLE eshop.ticket_wallet_objects DROP COLUMN IF EXISTS lease,DROP COLUMN IF EXISTS lease_until,
 DROP COLUMN IF EXISTS next_attempt,DROP COLUMN IF EXISTS last_synced,DROP COLUMN IF EXISTS failures,DROP COLUMN IF EXISTS last_error;

-- Historical bootstrap could install a dormant runtime-DB schedule. The actual
-- deployment scheduler is the single verified control-plane job, updated separately.
DO $$ DECLARE old_job bigint; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  FOR old_job IN SELECT jobid FROM cron.job WHERE jobname='festapp_google_ticket_wallet' LOOP
   PERFORM cron.unschedule(old_job);
  END LOOP;
 END IF;
END $$;
