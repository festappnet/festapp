BEGIN;

-- save_occasion_client_sync_v1 deliberately owns an empty search_path. Its
-- renamed legacy implementation still calls trusted public helpers without
-- schema qualification, so it must not inherit the locked-down caller path.
ALTER FUNCTION public.update_occasion_internal_v1(jsonb)
  SET search_path = public, extensions;

COMMIT;
