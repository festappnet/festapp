-- Install on the verified canonical database only, inside one transaction.
-- Role password is provisioned separately and never enters repository SQL.
DO $$ BEGIN
  IF current_database() <> 'festapp_rehearsal_20260909220601' THEN
    RAISE EXCEPTION 'Unexpected database';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=1) THEN
    RAISE EXCEPTION 'Missing canonical Festapp organization';
  END IF;
  CREATE ROLE festapp_agent_diagnostics LOGIN NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
END $$;
ALTER ROLE festapp_agent_diagnostics SET default_transaction_read_only=on;
ALTER ROLE festapp_agent_diagnostics SET statement_timeout='3s';
ALTER ROLE festapp_agent_diagnostics SET idle_in_transaction_session_timeout='5s';
CREATE SCHEMA agent_operations AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA agent_operations FROM PUBLIC;
CREATE VIEW agent_operations.identity WITH (security_barrier=true) AS
  SELECT id AS organization FROM public.organizations WHERE id=1;
CREATE VIEW agent_operations.migrations WITH (security_barrier=true) AS
  SELECT version FROM supabase_migrations.schema_migrations
  ORDER BY version DESC LIMIT 50;
REVOKE ALL ON ALL TABLES IN SCHEMA agent_operations FROM PUBLIC;
GRANT USAGE ON SCHEMA agent_operations TO festapp_agent_diagnostics;
GRANT SELECT ON agent_operations.identity,agent_operations.migrations TO festapp_agent_diagnostics;
