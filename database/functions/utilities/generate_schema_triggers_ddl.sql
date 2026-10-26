CREATE OR REPLACE FUNCTION generate_schema_triggers_ddl(p_schema text)
RETURNS text
SET search_path = public, extensions AS $$
WITH aggregated_triggers AS (
  SELECT
    trigger_schema,
    trigger_name,
    event_object_schema,
    event_object_table,
    action_timing,
    action_orientation,
    string_agg(event_manipulation, ' or ') AS events,
    max(action_condition) AS action_condition,
    max(action_statement) AS action_statement
  FROM information_schema.triggers
  WHERE trigger_schema = p_schema
  GROUP BY trigger_schema, trigger_name, event_object_schema, event_object_table, action_timing, action_orientation
),
formatted_triggers AS (
  SELECT
    -- Drop statement
    'DROP TRIGGER IF EXISTS ' || quote_ident(trigger_name) || ' ON '
    || CASE
         WHEN event_object_schema = p_schema
           THEN quote_ident(event_object_table)
         ELSE quote_ident(event_object_schema) || '.' || quote_ident(event_object_table)
       END || ';' || E'\n'
    ||
    -- Create statement
    'CREATE TRIGGER ' || quote_ident(trigger_name) || E'\n'
    || upper(action_timing) || ' ' || lower(events) || ' ON '
    || CASE
         WHEN event_object_schema = p_schema
           THEN quote_ident(event_object_table)
         ELSE quote_ident(event_object_schema) || '.' || quote_ident(event_object_table)
       END
    || E'\nFOR EACH ' || lower(action_orientation) || E'\n'
    || CASE
         WHEN action_condition IS NOT NULL
           THEN 'WHEN (' || action_condition || ')' || E'\n'
         ELSE ''
       END
    || 'EXECUTE ' || action_statement || ';'
    AS trigger_ddl
  FROM aggregated_triggers
)
SELECT string_agg(trigger_ddl, E'\n\n') AS ddl_all
FROM formatted_triggers;
$$ LANGUAGE sql STABLE;

-- Security Hardening
REVOKE EXECUTE ON FUNCTION generate_schema_triggers_ddl(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_schema_triggers_ddl(text) TO service_role;