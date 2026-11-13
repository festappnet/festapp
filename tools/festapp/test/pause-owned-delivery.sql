-- Before the committed API fixture, close delivery in this runner-owned unit DB.
-- Earlier delivery/provider rehearsals intentionally exercise an unpaused queue.
-- Never weaken the Node guard or run this against an unmarked/active database.
BEGIN;
SELECT set_config('festapp.expected_fixture_project', :'owned_project', true);
DO $guard$
BEGIN
 IF current_setting('festapp.expected_fixture_project') !~ '^festapp-[a-z0-9-]+$'
    OR NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment
      WHERE project=current_setting('festapp.expected_fixture_project'))
    OR current_setting('cron.launch_active_jobs')<>'off' THEN
  RAISE EXCEPTION 'owned inactive disposable database required';
 END IF;
END
$guard$;
UPDATE public.email_capacity SET paused=true,worker_url=NULL;
COMMIT;
