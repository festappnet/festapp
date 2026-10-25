-- Read-only audit for the 2026-08-01 CSV-import incident on occasion 643.
-- The production schema has no occasion_users.updated_at column and no
-- field-level audit trigger. The cohort is therefore identified by the exact
-- damaged row signature plus the tightly clustered user_info.updated_at window.

WITH affected AS (
    SELECT
        ou."user",
        ui.email_readonly,
        ui.updated_at AS profile_updated_at,
        ou.created_at AS occasion_membership_created_at,
        standard_group.title AS standard_group
    FROM public.occasion_users ou
    JOIN public.user_info ui ON ui.id = ou."user"
    LEFT JOIN LATERAL (
        SELECT ugi.title
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ug."user" = ou."user"
          AND ugi.occasion = ou.occasion
          AND ugi.type IS NULL
        ORDER BY ugi.id
        LIMIT 1
    ) standard_group ON true
    WHERE ou.occasion = 643
      AND ou.services IS NULL
      AND ou.role IS NULL
      AND ou.data ? 'sex'
      AND ou.data->'sex' = 'null'::jsonb
      AND ui.updated_at >= timestamptz '2026-08-01 10:34:50.394762+00'
      AND ui.updated_at <= timestamptz '2026-08-01 10:36:54.308740+00'
)
SELECT
    count(*) AS affected_users,
    min(profile_updated_at) AS first_change,
    max(profile_updated_at) AS last_change,
    count(*) FILTER (WHERE standard_group IS NOT NULL) AS with_standard_group,
    count(*) FILTER (WHERE standard_group IS NULL) AS without_standard_group
FROM affected;

-- For a review/export list, replace the aggregate SELECT above with the line
-- below while keeping the same WITH clause. Keep its output outside source
-- control because it contains participant e-mail addresses.
-- SELECT * FROM affected ORDER BY profile_updated_at, email_readonly;
