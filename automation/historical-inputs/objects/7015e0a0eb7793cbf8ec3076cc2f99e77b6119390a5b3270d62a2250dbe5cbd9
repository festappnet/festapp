CREATE OR REPLACE FUNCTION generate_schema_rls_enable_ddl(p_schema text)
RETURNS text
SET search_path = public, extensions AS $$
WITH tables AS (
  SELECT n.nspname AS schemaname,
         c.relname AS tablename
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = p_schema
    AND c.relkind IN ('r', 'p')  -- regular and partitioned tables
)
SELECT string_agg(
         'ALTER TABLE ' || quote_ident(schemaname) || '.' || quote_ident(tablename) ||
         ' ENABLE ROW LEVEL SECURITY;', E'\n'
       ) AS ddl_all
FROM tables;
$$ LANGUAGE sql STABLE;

-- Security Hardening
REVOKE EXECUTE ON FUNCTION generate_schema_rls_enable_ddl(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_schema_rls_enable_ddl(text) TO service_role;
