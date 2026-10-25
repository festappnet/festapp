-- The canonical import remapped places.id but left these nested place references
-- in their source namespace. Repair only the seven investigated jm2025 routes.
-- Exact before/after guards prevent double mapping or overwriting later edits.
-- Execute inside the migration transaction, including its ledger insertion.
DO $repair$
DECLARE
  candidate record;
  current_path jsonb;
  node record;
  items jsonb := '[]';
  changed integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.occasions WHERE id=1072521) THEN
    RETURN; -- Other installations have no affected occasion.
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.occasions
    WHERE id=1072521 AND organization=9 AND link='jm2025') THEN
    RAISE EXCEPTION 'Jubileum path repair: occasion identity mismatch';
  END IF;
  FOR candidate IN SELECT * FROM (VALUES
    (3, '[[189,190,191,192,189]]'::jsonb, '[[205,206,207,208,205]]'::jsonb),
    (4, '[[189,190,193,194,191,195,192,189]]'::jsonb, '[[205,206,209,210,207,211,208,205]]'::jsonb),
    (5, '[[209,189],[208,192],[254,189]]'::jsonb, '[[225,205],[224,208],[268,205]]'::jsonb),
    (6, '[[203,204,205,206,202,207,203]]'::jsonb, '[[219,220,221,222,218,223,219]]'::jsonb),
    (7, '[[196,267,268,269,270,329,273,312],[309,267],[307,315,316,317,311],[306,318,319,320,321,322,310],[308,323,324,325,326,322],[328,329]]'::jsonb, '[[212,281,282,283,284,336,285,319],[316,281],[314,322,323,324,318],[313,325,326,327,328,329,317],[315,330,331,332,333,329],[335,336]]'::jsonb),
    (8, '[[265,257,255,259,258,264,260,262,263,261,266,265],[258,256]]'::jsonb, '[[279,271,269,273,272,278,274,276,277,275,280,279],[272,270]]'::jsonb),
    (9, '[[314,311,313,312,310,314,310,312,313,311,314],[199,314,199,311,199,313,199,312,199,310,199]]'::jsonb, '[[321,318,320,319,317,321,317,319,320,318,321],[215,321,215,318,215,320,215,319,215,317,215]]'::jsonb)
  ) AS expected(id, original_path, repaired_path) ORDER BY id LOOP
    SELECT path_data INTO current_path FROM public.path_groups
      WHERE id=candidate.id AND occasion=1072521 FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Jubileum path repair: missing path %', candidate.id;
    END IF;
    IF current_path = candidate.repaired_path THEN CONTINUE; END IF;
    IF current_path IS DISTINCT FROM candidate.original_path THEN
      RAISE EXCEPTION 'Jubileum path repair: path % changed; refusing overwrite', candidate.id;
    END IF;

    -- Check every old/new pair against retained canonical import provenance and
    -- the target occasion. Never infer identity from a title or numeric offset.
    FOR node IN
      SELECT old_node.value #>> '{}' AS old_id,
        new_node.value #>> '{}' AS new_id
      FROM jsonb_array_elements(candidate.original_path) WITH ORDINALITY old_segment(value,i)
      JOIN jsonb_array_elements(candidate.repaired_path) WITH ORDINALITY new_segment(value,i) USING(i)
      CROSS JOIN LATERAL jsonb_array_elements(old_segment.value) WITH ORDINALITY old_node(value,j)
      JOIN LATERAL jsonb_array_elements(new_segment.value) WITH ORDINALITY new_node(value,j) USING(j)
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM festapp_merge.id_mappings m
        JOIN festapp_merge.import_runs r ON r.run_id=m.run_id
        JOIN public.places p ON p.id=m.target_id::bigint AND p.occasion=1072521
        WHERE m.run_id='b1e710d5-e3e5-4ae9-9376-c84c7c1afc8b'::uuid
          AND r.source_alias='a' AND r.status='validated'
          AND m.source_table='public.places'
          AND m.source_id=node.old_id AND m.target_id=node.new_id
      ) THEN
        RAISE EXCEPTION 'Jubileum path repair: unproven place mapping % -> %', node.old_id,node.new_id;
      END IF;
    END LOOP;

    UPDATE public.path_groups SET path_data=candidate.repaired_path
      WHERE id=candidate.id AND occasion=1072521;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('path','occasion',1072521,candidate.id::text,1)
    ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
      SET version=public.client_aggregate_versions.version+1, updated_at=now();
    items := items || jsonb_build_array(jsonb_build_object(
      'entityType','path','entityId',candidate.id,'operation','update',
      'changedFields',jsonb_build_array('path_data')));
    changed := changed+1;
  END LOOP;
  IF changed>0 THEN
    PERFORM public.record_client_sync_commit_v1(
      1072521,'repair.jubileum2025.path_place_references','map',items,
      ARRAY['map_catalog'],'[]'::jsonb,'[]'::jsonb,'system',
      'Restore seven route place references using canonical import provenance');
  END IF;
  RAISE NOTICE 'Jubileum path repair: % paths restored',changed;
END;
$repair$;
