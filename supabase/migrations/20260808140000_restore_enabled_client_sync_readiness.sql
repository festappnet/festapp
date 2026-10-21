-- Adding a fully migrated source after the production cutover must not make an
-- already-enabled occasion fall back to legacy writers whose DML grants have
-- been revoked. Fresh installations remain gated until the normal cutover.
DO $restore_enabled_client_sync_readiness$
DECLARE v_registry_version integer;
BEGIN
  SELECT max(registry_version) INTO STRICT v_registry_version
  FROM public.client_sync_component_sources;

  IF EXISTS (
    SELECT 1 FROM public.occasions o
    WHERE COALESCE((o.data->>'client_sync_v1')::boolean,false)
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.client_sync_component_sources s
      WHERE s.registry_version=v_registry_version
        AND s.component='occasion_config'
        AND s.source_relation='public.images'::regclass
        AND s.disposition='migrate'
        AND s.canonical_writers @> ARRAY['add_image_record','remove_image_records']
        AND cardinality(s.legacy_writers)=0
    ) THEN
      RAISE EXCEPTION 'occasion image writer is not ready for client sync cutover';
    END IF;

    UPDATE public.client_sync_component_sources s
    SET cutover_ready=true
    WHERE s.registry_version=v_registry_version
      AND s.component='occasion_config'
      AND s.source_relation='public.images'::regclass;

    IF EXISTS (
      SELECT 1 FROM public.client_sync_component_sources s
      WHERE s.registry_version=v_registry_version AND NOT s.cutover_ready
    ) THEN
      RAISE EXCEPTION 'enabled client sync still has unready registry sources';
    END IF;
  END IF;
END
$restore_enabled_client_sync_readiness$;
