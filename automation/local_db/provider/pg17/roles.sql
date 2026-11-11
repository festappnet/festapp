--
-- PostgreSQL database cluster dump
--


SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF; END $$;
ALTER ROLE anon WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF; END $$;
ALTER ROLE authenticated WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator; END IF; END $$;
ALTER ROLE authenticator WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='dashboard_user') THEN CREATE ROLE dashboard_user; END IF; END $$;
ALTER ROLE dashboard_user WITH NOSUPERUSER INHERIT CREATEROLE CREATEDB NOLOGIN REPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='pgbouncer') THEN CREATE ROLE pgbouncer; END IF; END $$;
ALTER ROLE pgbouncer WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='postgres') THEN CREATE ROLE postgres; END IF; END $$;
ALTER ROLE postgres WITH NOSUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $$;
ALTER ROLE service_role WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION BYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_admin') THEN CREATE ROLE supabase_admin; END IF; END $$;
ALTER ROLE supabase_admin WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin; END IF; END $$;
ALTER ROLE supabase_auth_admin WITH NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_etl_admin') THEN CREATE ROLE supabase_etl_admin; END IF; END $$;
ALTER ROLE supabase_etl_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN REPLICATION BYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_functions_admin') THEN CREATE ROLE supabase_functions_admin; END IF; END $$;
ALTER ROLE supabase_functions_admin WITH NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_privileged_role') THEN CREATE ROLE supabase_privileged_role; END IF; END $$;
ALTER ROLE supabase_privileged_role WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user; END IF; END $$;
ALTER ROLE supabase_read_only_user WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION BYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_realtime_admin') THEN CREATE ROLE supabase_realtime_admin; END IF; END $$;
ALTER ROLE supabase_realtime_admin WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_replication_admin') THEN CREATE ROLE supabase_replication_admin; END IF; END $$;
ALTER ROLE supabase_replication_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN REPLICATION NOBYPASSRLS;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='supabase_storage_admin') THEN CREATE ROLE supabase_storage_admin; END IF; END $$;
ALTER ROLE supabase_storage_admin WITH NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;

--
-- User Configurations
--

--
-- User Config "anon"
--

ALTER ROLE anon SET statement_timeout TO '3s';

--
-- User Config "authenticated"
--

ALTER ROLE authenticated SET statement_timeout TO '8s';

--
-- User Config "authenticator"
--

ALTER ROLE authenticator SET session_preload_libraries TO 'supautils', 'safeupdate';
ALTER ROLE authenticator SET statement_timeout TO '8s';
ALTER ROLE authenticator SET lock_timeout TO '8s';

--
-- User Config "postgres"
--

ALTER ROLE postgres SET search_path TO E'\\$user', 'public', 'extensions';

--
-- User Config "supabase_admin"
--

ALTER ROLE supabase_admin SET search_path TO E'\\$user', 'public', 'auth', 'extensions';
ALTER ROLE supabase_admin SET log_statement TO 'none';

--
-- User Config "supabase_auth_admin"
--

ALTER ROLE supabase_auth_admin SET search_path TO 'auth';
ALTER ROLE supabase_auth_admin SET idle_in_transaction_session_timeout TO '60000';
ALTER ROLE supabase_auth_admin SET log_statement TO 'none';

--
-- User Config "supabase_functions_admin"
--

ALTER ROLE supabase_functions_admin SET search_path TO 'supabase_functions';

--
-- User Config "supabase_read_only_user"
--

ALTER ROLE supabase_read_only_user SET default_transaction_read_only TO 'on';

--
-- User Config "supabase_realtime_admin"
--

ALTER ROLE supabase_realtime_admin SET search_path TO 'public', 'extensions', 'realtime';

--
-- User Config "supabase_storage_admin"
--

ALTER ROLE supabase_storage_admin SET search_path TO 'storage';
ALTER ROLE supabase_storage_admin SET log_statement TO 'none';


--
-- Role memberships
--

GRANT anon TO authenticator WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT anon TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT anon TO supabase_realtime_admin WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT authenticated TO authenticator WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT authenticated TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT authenticated TO supabase_realtime_admin WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT authenticator TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT authenticator TO supabase_storage_admin WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT pg_create_subscription TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_monitor TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_monitor TO supabase_etl_admin WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_monitor TO supabase_read_only_user WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_read_all_data TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_read_all_data TO supabase_etl_admin WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_read_all_data TO supabase_read_only_user WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT pg_signal_backend TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT service_role TO authenticator WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT service_role TO postgres WITH ADMIN OPTION, INHERIT TRUE GRANTED BY supabase_admin;
GRANT service_role TO supabase_realtime_admin WITH INHERIT FALSE GRANTED BY supabase_admin;
GRANT supabase_functions_admin TO postgres WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT supabase_privileged_role TO postgres WITH INHERIT TRUE GRANTED BY supabase_admin;
GRANT supabase_privileged_role TO supabase_etl_admin WITH INHERIT TRUE GRANTED BY supabase_admin;


--
-- Role privileges on configuration parameters
--

GRANT SET ON PARAMETER log_min_messages TO supabase_realtime_admin;



--
-- PostgreSQL database cluster dump complete
--

