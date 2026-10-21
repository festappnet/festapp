-- Hosted pgAudit records privileged and API writes outside application tables
-- in Supabase Postgres Logs. Parameters remain redacted to avoid turning the
-- audit channel into a second store for user content or credentials.
CREATE EXTENSION IF NOT EXISTS pgaudit WITH SCHEMA extensions;

ALTER ROLE postgres SET pgaudit.log TO 'write, role, ddl';

ALTER ROLE authenticator SET pgaudit.log TO 'write';
