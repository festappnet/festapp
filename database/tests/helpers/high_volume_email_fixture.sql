-- Test-only workload profile, rolled back by run_db_tests.js. State-machine
-- scenarios deliberately enqueue more than a real recipient burst in one SQL
-- statement. Production defaults and the abuse boundary suites stay unchanged.
UPDATE public.abuse_policy_rules SET base_limit=1000,hard_cap=1000
 WHERE rule_key IN ('email.ordinary.recipient.burst','email.ordinary.recipient.day');
