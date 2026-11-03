CREATE OR REPLACE FUNCTION generate_schema_policies_ddl(p_schema text)
RETURNS text
SET search_path = public, extensions AS $$
WITH policies AS (
  SELECT schemaname,
         tablename,
         policyname,
         permissive,
         cmd,
         roles,
         qual,
         with_check
  FROM pg_policies
  WHERE schemaname = p_schema
),
formatted_policies AS (
  SELECT
    (
      'DROP POLICY IF EXISTS ' || quote_ident(policyname) || ' ON ' ||
        quote_ident(schemaname) || '.' || quote_ident(tablename) || ';' || E'\n' ||
      'CREATE POLICY ' || quote_ident(policyname) || ' ON ' ||
        quote_ident(schemaname) || '.' || quote_ident(tablename) || E'\n' ||
      (CASE WHEN lower(permissive) = 'permissive'
            THEN 'AS PERMISSIVE '
            ELSE 'AS RESTRICTIVE ' END) ||
      'FOR ' || upper(cmd) || E'\n' ||
      (CASE
         WHEN roles IS NOT NULL AND array_length(roles,1) > 0
         THEN 'TO ' || (SELECT string_agg(quote_ident(r), ', ')
                      FROM unnest(roles) AS r) || E'\n'
         ELSE ''
       END) ||
      (CASE WHEN qual IS NOT NULL AND qual <> ''
            THEN 'USING (' || qual || ')' || E'\n'
            ELSE '' END) ||
      (CASE WHEN with_check IS NOT NULL AND with_check <> ''
            THEN 'WITH CHECK (' || with_check || ')' || E'\n'
            ELSE '' END)
    ) AS raw_policy_ddl
  FROM policies
)
SELECT string_agg(rtrim(raw_policy_ddl, E'\n') || ';', E'\n\n') AS ddl_all
FROM formatted_policies;
$$ LANGUAGE sql STABLE;

-- Security Hardening
REVOKE EXECUTE ON FUNCTION generate_schema_policies_ddl(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_schema_policies_ddl(text) TO service_role;
