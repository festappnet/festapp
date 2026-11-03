CREATE OR REPLACE FUNCTION generate_schema_ddl(p_schema text)
RETURNS text
SET search_path = public, extensions AS $$
WITH table_info AS (
  SELECT
    t.table_schema,
    t.table_name,
    CASE
      WHEN COALESCE(pg.tablespace, '') = '' THEN ' TABLESPACE pg_default'
      ELSE ' TABLESPACE ' || pg.tablespace
    END AS tablespace_clause
  FROM information_schema.tables t
  LEFT JOIN pg_catalog.pg_tables pg
    ON t.table_schema = pg.schemaname
   AND t.table_name = pg.tablename
  WHERE t.table_schema = p_schema
    AND t.table_type = 'BASE TABLE'
),
table_columns AS (
  SELECT
    c.table_schema,
    c.table_name,
    string_agg(
      '  ' || quote_ident(c.column_name) || ' ' ||
      (
        CASE
          -- Identity columns: type + identity clause
          WHEN c.is_identity = 'YES' THEN
            c.data_type ||
            CASE
              WHEN c.data_type IN ('character varying','character')
                   AND c.character_maximum_length IS NOT NULL
              THEN '(' || c.character_maximum_length || ')'
              WHEN c.data_type = 'numeric' AND c.numeric_precision IS NOT NULL
              THEN '(' || c.numeric_precision || ', ' || c.numeric_scale || ')'
              ELSE ''
            END ||
            ' generated ' || lower(c.identity_generation) || ' as identity'
          -- Serial columns (if not identity)
          WHEN c.data_type = 'integer' AND c.column_default LIKE 'nextval(%' THEN
            'serial'
          -- Numeric columns with precision/scale
          WHEN c.data_type = 'numeric' AND c.numeric_precision IS NOT NULL THEN
            'numeric(' || c.numeric_precision || ', ' || c.numeric_scale || ')'
          ELSE
            c.data_type ||
              CASE
                WHEN c.data_type IN ('character varying','character')
                     AND c.character_maximum_length IS NOT NULL
                THEN '(' || c.character_maximum_length || ')'
                ELSE ''
              END
        END
      ) ||
      ' ' || (CASE WHEN c.is_nullable = 'NO' THEN 'not null' ELSE 'null' END) ||
      CASE
         WHEN c.is_identity <> 'YES'
              AND NOT (c.data_type = 'integer' AND c.column_default LIKE 'nextval(%')
              AND c.column_default IS NOT NULL
         THEN ' default ' || c.column_default
         ELSE ''
      END,
      E',\n'
      ORDER BY c.ordinal_position
    ) AS columns_definition
  FROM information_schema.columns c
  WHERE c.table_schema = p_schema
  GROUP BY c.table_schema, c.table_name
),
constraints_pk AS (
  SELECT
    tc.table_schema,
    tc.table_name,
    '  constraint ' || quote_ident(tc.constraint_name) || ' primary key (' ||
      string_agg(quote_ident(kcu.column_name), ', ' ORDER BY kcu.ordinal_position) || ')' AS constraint_def
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
  WHERE tc.constraint_type = 'PRIMARY KEY'
    AND tc.table_schema = p_schema
  GROUP BY tc.table_schema, tc.table_name, tc.constraint_name
),
constraints_fk AS (
  SELECT
    tc.table_schema,
    tc.table_name,
    '  constraint ' || quote_ident(tc.constraint_name) || ' foreign KEY (' ||
      string_agg(quote_ident(kcu.column_name), ', ' ORDER BY kcu.ordinal_position) || ') references ' ||
      (
        -- Invert the condition: if the referenced schema is different, qualify the name.
        CASE
          WHEN reftable_ns.nspname <> p_schema
          THEN quote_ident(reftable_ns.nspname) || '.' || quote_ident(reftable.relname)
          ELSE quote_ident(reftable.relname)
        END
      ) || ' (' ||
      (
        SELECT string_agg(quote_ident(att.attname), ', ' ORDER BY u.ordinality)
        FROM unnest(pgc.confkey) WITH ORDINALITY AS u(attnum, ordinality)
        JOIN pg_attribute att
          ON att.attrelid = pgc.confrelid AND att.attnum = u.attnum
      )
      || ')' ||
      CASE
         WHEN pgc.confdeltype = 'c' THEN ' on delete cascade'
         WHEN pgc.confdeltype = 'n' THEN ' on delete set null'
         WHEN pgc.confdeltype = 'd' THEN ' on delete set default'
         WHEN pgc.confdeltype = 'r' THEN ' on delete restrict'
         ELSE ''
      END AS constraint_def
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
  JOIN pg_constraint pgc
    ON pgc.conname = tc.constraint_name
       AND pgc.conrelid = (
            SELECT oid FROM pg_class
            WHERE relname = tc.table_name
              AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = tc.table_schema)
       )
  JOIN pg_class reftable ON reftable.oid = pgc.confrelid
  JOIN pg_namespace reftable_ns ON reftable_ns.oid = reftable.relnamespace
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = p_schema
  GROUP BY tc.table_schema, tc.table_name, tc.constraint_name,
           reftable_ns.nspname, reftable.relname, pgc.confdeltype, pgc.confkey, pgc.confrelid
),
all_constraints AS (
  SELECT
    table_schema,
    table_name,
    string_agg(constraint_def, E',\n') AS constraints_def
  FROM (
    SELECT * FROM constraints_pk
    UNION ALL
    SELECT * FROM constraints_fk
  ) sub
  GROUP BY table_schema, table_name
),
create_statements AS (
  SELECT
    'create table if not exists ' || quote_ident(t.table_schema) || '.' || quote_ident(t.table_name) || E' (\n' ||
    COALESCE(tc.columns_definition, '') ||
    CASE
      WHEN ac.constraints_def IS NOT NULL THEN E',\n' || ac.constraints_def
      ELSE ''
    END ||
    E'\n) ' ||
    COALESCE(t.tablespace_clause, '') ||
    ';' AS create_table_statement
  FROM table_info t
  LEFT JOIN table_columns tc
    ON t.table_schema = tc.table_schema AND t.table_name = tc.table_name
  LEFT JOIN all_constraints ac
    ON t.table_schema = ac.table_schema AND t.table_name = ac.table_name
)
SELECT string_agg(create_table_statement, E'\n\n') AS ddl_all
FROM create_statements;
$$ LANGUAGE sql STABLE;

-- Security Hardening
REVOKE EXECUTE ON FUNCTION generate_schema_ddl(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_schema_ddl(text) TO service_role;