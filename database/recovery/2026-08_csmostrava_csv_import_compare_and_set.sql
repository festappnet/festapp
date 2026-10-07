-- Conservative recovery template for the 2026-08-01 CSV-import incident.
--
-- This file is deliberately NOT a migration and must not be run blindly.
-- Restore/download backup 762371118 (2026-08-01 04:26:45 UTC), export the
-- occasion_users rows for occasion 643, and load them into the temporary
-- backup table below. Run the preview first. The script ends in ROLLBACK by
-- default; change it to COMMIT only after the preview has been reviewed.
--
-- Safety invariant: a backup value is written only if the production value is
-- still exactly the damaged value observed while the recovery plan is built.
-- A non-null services object, including custom accommodation, is never
-- replaced. The final WHERE clauses are compare-and-set guards against a
-- concurrent or later manual edit.

BEGIN;

CREATE TEMP TABLE csv_import_backup_occasion_users (
    "user" uuid PRIMARY KEY,
    data jsonb,
    services jsonb,
    role bigint,
    is_editor_view boolean,
    user_info_data jsonb
) ON COMMIT DROP;

-- Load the export from the restored backup here, for example from psql:
-- \copy csv_import_backup_occasion_users FROM 'occasion_643_before_incident.csv' CSV HEADER

-- Restore only keys whose current value is still the null/missing value left
-- by the incident. This helper is temporary and disappears on commit/rollback.
CREATE FUNCTION pg_temp.restore_damaged_csv_keys(
    p_current jsonb,
    p_backup jsonb,
    p_keys text[]
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_result jsonb := COALESCE(p_current, '{}'::jsonb);
    v_key text;
BEGIN
    FOREACH v_key IN ARRAY p_keys
    LOOP
        IF (NOT v_result ? v_key OR v_result->v_key = 'null'::jsonb)
           AND p_backup ? v_key
           AND p_backup->v_key <> 'null'::jsonb THEN
            v_result := jsonb_set(
                v_result, ARRAY[v_key], p_backup->v_key, true
            );
        END IF;
    END LOOP;
    RETURN v_result;
END;
$$;

CREATE TEMP TABLE csv_import_recovery_plan ON COMMIT DROP AS
SELECT
    current_ou."user",
    ui.email_readonly,
    current_ou.services AS observed_services,
    backup_ou.services AS backup_services,
    current_ou.data AS observed_occasion_data,
    backup_ou.data AS backup_occasion_data,
    ui.data AS observed_user_info_data,
    backup_ou.user_info_data AS backup_user_info_data,
    current_ou.role AS observed_role,
    backup_ou.role AS backup_role,
    current_ou.is_editor_view AS observed_is_editor_view,
    backup_ou.is_editor_view AS backup_is_editor_view,
    current_ou.services IS NULL
        AND backup_ou.services IS NOT NULL AS restore_services,
    pg_temp.restore_damaged_csv_keys(
        current_ou.data,
        backup_ou.data,
        ARRAY[
            'sex', 'diet', 'note', 'phone', 'text1', 'text2', 'text3',
            'birthDate', 'is_volunteer'
        ]
    ) AS restored_occasion_data,
    pg_temp.restore_damaged_csv_keys(
        ui.data,
        backup_ou.user_info_data,
        ARRAY[
            'sex', 'diet', 'note', 'phone', 'text1', 'text2', 'text3',
            'birthDate'
        ]
    ) AS restored_user_info_data,
    current_ou.role IS NULL
        AND backup_ou.role IS NOT NULL AS restore_role
FROM public.occasion_users current_ou
JOIN public.user_info ui ON ui.id = current_ou."user"
JOIN csv_import_backup_occasion_users backup_ou
  ON backup_ou."user" = current_ou."user"
WHERE current_ou.occasion = 643
  -- Exact incident fingerprint captured during the audit. A later profile edit
  -- intentionally excludes the user from automatic recovery.
  AND ui.updated_at >= timestamptz '2026-08-01 10:34:50.394762+00'
  AND ui.updated_at <= timestamptz '2026-08-01 10:36:54.308740+00'
  AND current_ou.role IS NULL
  AND current_ou.data->'sex' = 'null'::jsonb;

-- Preview: must show 768 rows before any post-incident edits. A lower number is
-- expected when users have since been changed and is safer than overwriting.
SELECT
    count(*) AS candidates,
    count(*) FILTER (WHERE restore_services) AS services_to_restore,
    count(*) FILTER (
        WHERE restored_occasion_data IS DISTINCT FROM observed_occasion_data
    ) AS occasion_data_to_restore,
    count(*) FILTER (
        WHERE restored_user_info_data IS DISTINCT FROM observed_user_info_data
    ) AS user_info_data_to_restore,
    count(*) FILTER (WHERE restore_role) AS roles_to_restore,
    count(*) FILTER (
        WHERE observed_is_editor_view IS DISTINCT FROM backup_is_editor_view
    ) AS editor_view_requires_manual_review
FROM csv_import_recovery_plan;

-- Review every skipped/custom/conflicting value before changing ROLLBACK to
-- COMMIT. is_editor_view is never auto-restored because false is not an
-- unambiguous damage marker and the table has no field-level audit history.
SELECT *
FROM csv_import_recovery_plan
WHERE NOT restore_services
   OR observed_is_editor_view IS DISTINCT FROM backup_is_editor_view
ORDER BY email_readonly;

UPDATE public.occasion_users current_ou
SET services = CASE
        WHEN plan.restore_services THEN plan.backup_services
        ELSE current_ou.services
    END,
    data = plan.restored_occasion_data,
    role = CASE
        WHEN plan.restore_role THEN plan.backup_role
        ELSE current_ou.role
    END
FROM csv_import_recovery_plan plan
WHERE current_ou.occasion = 643
  AND current_ou."user" = plan."user"
  AND (plan.restore_services
       OR plan.restored_occasion_data IS DISTINCT FROM plan.observed_occasion_data
       OR plan.restore_role)
  AND (NOT plan.restore_services
       OR current_ou.services IS NOT DISTINCT FROM plan.observed_services)
  AND current_ou.data IS NOT DISTINCT FROM plan.observed_occasion_data
  AND (NOT plan.restore_role
       OR current_ou.role IS NOT DISTINCT FROM plan.observed_role);

UPDATE public.user_info current_ui
SET data = plan.restored_user_info_data
FROM csv_import_recovery_plan plan
WHERE current_ui.id = plan."user"
  AND plan.restored_user_info_data IS DISTINCT FROM plan.observed_user_info_data
  AND current_ui.data IS NOT DISTINCT FROM plan.observed_user_info_data;

-- Final machine-readable verification for both dry-run and committed runs.
SELECT
    count(*) AS candidates,
    count(*) FILTER (WHERE plan.restore_services) AS planned_services,
    count(*) FILTER (
        WHERE plan.restored_occasion_data
              IS DISTINCT FROM plan.observed_occasion_data
    ) AS planned_occasion_data,
    count(*) FILTER (
        WHERE plan.restored_user_info_data
              IS DISTINCT FROM plan.observed_user_info_data
    ) AS planned_user_info_data,
    count(*) FILTER (WHERE plan.restore_role) AS planned_roles,
    count(*) FILTER (
        WHERE plan.observed_is_editor_view
              IS DISTINCT FROM plan.backup_is_editor_view
    ) AS editor_view_conflicts,
    count(*) FILTER (
        WHERE ou.services IS NULL
          AND ou.role IS NULL
          AND ou.data->'sex' = 'null'::jsonb
    ) AS remaining_original_damage_signature
FROM csv_import_recovery_plan plan
JOIN public.occasion_users ou
  ON ou.occasion = 643 AND ou."user" = plan."user";

ROLLBACK;
