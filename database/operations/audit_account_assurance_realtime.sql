-- Read-only inventory for the MFA activation and recovery evidence.
-- Broadcast and Presence authorization is cached in Realtime, outside PostgreSQL.
WITH messages AS (
  SELECT oid, relrowsecurity, relforcerowsecurity
  FROM pg_class
  WHERE oid = to_regclass('realtime.messages')
), client_roles(role_name) AS (
  VALUES ('anon'::text), ('authenticated'::text)
), message_access AS (
  SELECT client_roles.role_name,
         has_table_privilege(client_roles.role_name, messages.oid, 'SELECT') AS can_select,
         has_table_privilege(client_roles.role_name, messages.oid, 'INSERT') AS can_insert,
         ARRAY(
           SELECT policy.polname
           FROM pg_policy policy
           WHERE policy.polrelid = messages.oid AND policy.polpermissive
             AND policy.polcmd IN ('r', 'a', '*')
             AND EXISTS (
               SELECT FROM unnest(policy.polroles) AS target(role_oid)
               WHERE CASE WHEN target.role_oid = 0 THEN true
                     ELSE pg_has_role(client_roles.role_name, target.role_oid, 'MEMBER') END
             )
           ORDER BY policy.polname
         ) AS permissive_policies
  FROM messages CROSS JOIN client_roles
)
SELECT jsonb_build_object(
  'publicationRelations', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('publication', pubname, 'schema', schemaname, 'relation', tablename)
                     ORDER BY pubname, schemaname, tablename)
    FROM pg_publication_tables
  ), '[]'::jsonb),
  'messagesRlsEnabled', (SELECT relrowsecurity FROM messages),
  'messagesRlsForced', (SELECT relforcerowsecurity FROM messages),
  'messageClientAccess', COALESCE((
    SELECT jsonb_agg(to_jsonb(message_access) ORDER BY role_name) FROM message_access
  ), '[]'::jsonb),
  'changeSubscriptionTablePresent', to_regclass('realtime.subscription') IS NOT NULL
);
