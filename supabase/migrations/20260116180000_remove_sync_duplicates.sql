-- Migration: Remove duplicates from external_sync_maps and add unique constraint

-- 1. Remove duplicate rows (keeping the one with the smallest ID)
--     We define a duplicate as a row having identical configuration:
--     (source_name, target_org_id, target_unit_id, remote_link_base, remote_org_id, remote_unit_id)
DELETE FROM public.external_sync_maps a
USING public.external_sync_maps b
WHERE a.id > b.id
  AND a.source_name = b.source_name
  AND a.target_org_id = b.target_org_id
  AND a.target_unit_id = b.target_unit_id
  AND a.remote_link_base = b.remote_link_base
  AND (a.remote_org_id IS NOT DISTINCT FROM b.remote_org_id)
  AND (a.remote_unit_id IS NOT DISTINCT FROM b.remote_unit_id);

-- 2. Add Unique Index to prevent future duplicates.
--     We use COALESCE to ensure that NULL values (meaning "All" or "None") are treated as distinct values for uniqueness checks.
--     (Standard UNIQUE index treats NULL != NULL, allowing multiple NULL rows).
CREATE UNIQUE INDEX IF NOT EXISTS external_sync_maps_unique_idx
ON public.external_sync_maps (
    source_name,
    target_org_id,
    target_unit_id,
    remote_link_base,
    COALESCE(remote_org_id, -1),
    COALESCE(remote_unit_id, -1)
);
