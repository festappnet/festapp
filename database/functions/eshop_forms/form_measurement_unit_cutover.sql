-- Migration-only transition. Stage normalized legacy data once; every preflight
-- runs before mutation. Ambiguity is never resolved by first-form-wins.
DO $$
DECLARE problem bigint;
BEGIN
 LOCK TABLE public.forms,public.units,public.occasions IN SHARE ROW EXCLUSIVE MODE;
 CREATE TEMP TABLE form_measurement_cutover ON COMMIT DROP AS
 SELECT f.id,f.occasion,o.unit,o.organization,u.organization unit_organization,m.metadata,
  m.metadata->'analytics' legacy,
  jsonb_strip_nulls(jsonb_build_object(
   'measurement_gtm_container',nullif(btrim(m.metadata#>>'{analytics,gtm_container}'),''),
   'measurement_scripts',nullif(m.metadata#>>'{analytics,scripts}',''))) config
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion LEFT JOIN public.units u ON u.id=o.unit
 CROSS JOIN LATERAL (SELECT public.normalize_form_metadata_internal(f.data) metadata) m
 WHERE m.metadata->'analytics' ?| ARRAY['gtm_container','scripts','enhanced_conversions'];
 SELECT id INTO problem FROM pg_temp.form_measurement_cutover WHERE unit IS NULL OR unit_organization IS DISTINCT FROM organization LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Legacy measurement form % has invalid Unit scope',problem; END IF;
 SELECT id INTO problem FROM pg_temp.form_measurement_cutover WHERE legacy->'enhanced_conversions'='true'::jsonb LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Legacy enhanced-conversion preparation on form % requires explicit reconciliation',problem; END IF;
 SELECT unit INTO problem FROM pg_temp.form_measurement_cutover WHERE config<>'{}'::jsonb GROUP BY unit HAVING count(DISTINCT config)>1 LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Conflicting legacy measurement destinations in Unit %',problem; END IF;
 SELECT c.unit INTO problem FROM pg_temp.form_measurement_cutover c JOIN public.units u ON u.id=c.unit
 CROSS JOIN LATERAL (SELECT jsonb_strip_nulls(jsonb_build_object(
  'measurement_gtm_container',nullif(btrim(u.data->>'measurement_gtm_container'),''),
  'measurement_scripts',nullif(u.data->>'measurement_scripts',''))) config) existing
 WHERE c.config<>'{}'::jsonb AND existing.config<>'{}'::jsonb AND c.config IS DISTINCT FROM existing.config LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Legacy measurement destination conflicts with Unit % configuration',problem; END IF;
 -- Preflight complete. Enablement is never backfilled to true. Invalidate stale
 -- Unit/form aggregate snapshots in the same transaction as the move.
 WITH changed AS (
  UPDATE public.units u SET data=coalesce(u.data,'{}')||c.config
  FROM (SELECT DISTINCT unit,config FROM pg_temp.form_measurement_cutover WHERE config<>'{}'::jsonb) c
  WHERE u.id=c.unit AND NOT coalesce(u.data,'{}') @> c.config RETURNING u.id
 ) INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'unit','unit',id,id::text,1 FROM changed
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'form','occasion',occasion,id::text,1 FROM pg_temp.form_measurement_cutover
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 UPDATE public.forms f SET data=jsonb_set(c.metadata,'{analytics}',jsonb_build_object('enabled',coalesce(c.legacy->'enabled'='true'::jsonb,false)))
 FROM pg_temp.form_measurement_cutover c WHERE f.id=c.id;
 DROP TABLE pg_temp.form_measurement_cutover;
END $$;
