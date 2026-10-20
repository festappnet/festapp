-- The occasion image source joined the registry after the original production
-- cutover. Close its ordinary table-writer path when a v1 occasion is already
-- enabled; clients use add_image_record/remove_image_records instead.
DO $close_occasion_media_legacy_dml$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE COALESCE((o.data->>'client_sync_v1')::boolean,false)
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.client_sync_component_sources s
      WHERE s.registry_version=(
          SELECT max(v.registry_version) FROM public.client_sync_component_sources v)
        AND s.component='occasion_config'
        AND s.source_relation='public.images'::regclass
        AND s.cutover_ready
        AND s.canonical_writers @> ARRAY['add_image_record','remove_image_records']
        AND cardinality(s.legacy_writers)=0
    ) THEN
      RAISE EXCEPTION 'occasion image source is not ready for legacy DML closure';
    END IF;

    REVOKE INSERT,UPDATE,DELETE ON TABLE public.images FROM anon,authenticated;

    IF EXISTS (
      SELECT 1 FROM information_schema.role_table_grants g
      WHERE g.grantee IN ('anon','authenticated')
        AND g.table_schema='public'
        AND g.table_name='images'
        AND g.privilege_type IN ('INSERT','UPDATE','DELETE')
    ) THEN
      RAISE EXCEPTION 'occasion image legacy DML grants remain';
    END IF;
  END IF;
END
$close_occasion_media_legacy_dml$;
