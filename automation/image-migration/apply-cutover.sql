-- Input is one verified private bundle in pg_temp.asset_cutover_input(payload).
-- This is an operator transaction, not an application RPC or a schema migration.
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='120s';
SET LOCAL search_path=public,extensions;
SET LOCAL TimeZone='UTC';
SELECT pg_advisory_xact_lock(hashtextextended('festapp-storage-r2-retirement',0));
DO $cutover$
DECLARE b jsonb; field jsonb; relation oid; relation_name text; pk text[]; supplied text[];
 changed bigint; scope record; components text[]; impacts jsonb; manifest text;
BEGIN
 IF session_user<>'postgres' OR current_database()<>'festapp_rehearsal_20260909220601'
 OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=3 AND title='vstupenky.online') THEN
  RAISE EXCEPTION 'Canonical operator target mismatch';
 END IF;
 SELECT payload INTO STRICT b FROM pg_temp.asset_cutover_input;
 manifest:=b->>'manifest_sha256';
 IF (b->>'version')::integer IS DISTINCT FROM 1 OR manifest IS NULL OR manifest !~ '^[0-9a-f]{64}$'
 OR b->'production_mutations' IS DISTINCT FROM 'false'::jsonb
 OR b->'requires_atomic_client_sync_publication' IS DISTINCT FROM 'true'::jsonb
 OR jsonb_typeof(b->'registry') IS DISTINCT FROM 'array'
 OR jsonb_typeof(b->'edits') IS DISTINCT FROM 'array' THEN
  RAISE EXCEPTION 'Unverified cutover input';
 END IF;
 PERFORM singleton FROM public.canonical_asset_cutover
 WHERE singleton AND NOT active AND inventory_sha256 IS NULL FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM public.canonical_assets) THEN
  RAISE EXCEPTION 'Registry already prepared or active; read back instead of replay';
 END IF;
 IF COALESCE((b->>'discarded_roma_test_map')::boolean,false) THEN
  PERFORM id FROM public.occasions WHERE id=63 AND organization=1 AND unit=9
   AND link='romatrip' AND is_hidden FOR UPDATE;
  IF NOT FOUND OR (SELECT count(*) FROM public.occasion_users WHERE occasion=63)<>1
   OR EXISTS(SELECT 1 FROM eshop.orders WHERE occasion=63) THEN
   RAISE EXCEPTION 'Approved test map disposal scope changed';
  END IF;
 END IF;
 -- Freeze the old object catalog for this short transaction. A changed source
 -- or a newly uploaded object aborts the whole operation, never just one row.
 LOCK TABLE storage.objects IN SHARE MODE;
 IF (SELECT count(*) FROM storage.objects)<>jsonb_array_length(b->'registry') OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(b->'registry') r
  WHERE NOT EXISTS(SELECT 1 FROM storage.objects o
   WHERE o.bucket_id=r->>'source_bucket' AND o.name=r->>'source_key'
    AND to_jsonb(o)=r->'source_storage_record')) THEN
  RAISE EXCEPTION 'Storage catalog changed since verified copy';
 END IF;
 FOR relation_name IN SELECT DISTINCT format('%I.%I',e->>'schema',e->>'table')
  FROM jsonb_array_elements(b->'edits') e ORDER BY 1 LOOP
  IF split_part(relation_name,'.',1) NOT IN ('public','eshop') THEN
   RAISE EXCEPTION 'Unexpected reference schema';
  END IF;
  EXECUTE 'LOCK TABLE '||relation_name||' IN SHARE ROW EXCLUSIVE MODE';
 END LOOP;
 INSERT INTO public.canonical_assets(bucket,object_key,sha256,bytes,content_type,
  visibility,owner_id,source_bucket,source_key,source_storage_record,verified_at)
 SELECT bucket,object_key,sha256,bytes,content_type,visibility,owner_id,
  source_bucket,source_key,source_storage_record,verified_at
 FROM jsonb_to_recordset(b->'registry') AS r(bucket text,object_key text,sha256 text,bytes bigint,
  content_type text,visibility text,owner_id text,source_bucket text,source_key text,
  source_storage_record jsonb,verified_at timestamptz);
 FOR field IN SELECT value FROM jsonb_array_elements(b->'edits')
  ORDER BY value->>'schema',value->>'table',(value->'key')::text,value->>'field' LOOP
  relation:=to_regclass(format('%I.%I',field->>'schema',field->>'table'));
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=relation AND relkind IN ('r','p'))
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=relation
    AND attname=field->>'field' AND attnum>0 AND NOT attisdropped AND attgenerated='') THEN
   RAISE EXCEPTION 'Reference relation or writable field changed';
  END IF;
  SELECT array_agg(a.attname::text ORDER BY a.attname) INTO pk FROM pg_index i
   CROSS JOIN LATERAL unnest(i.indkey) k(attnum)
   JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum
   WHERE i.indrelid=relation AND i.indisprimary;
  SELECT array_agg(k ORDER BY k) INTO supplied FROM jsonb_object_keys(field->'key') k;
  IF pk IS NULL OR pk IS DISTINCT FROM supplied THEN
   RAISE EXCEPTION 'Exact durable primary key required';
  END IF;
  -- Identifiers are catalog-checked and quoted; every value is bound with USING.
  -- Native arrays, JSON, JSONB, text and domains retain their actual column type.
  EXECUTE format('UPDATE %I.%I AS t SET %I=(jsonb_populate_record(NULL::%I.%I,jsonb_build_object($4,$1))).%I
    WHERE to_jsonb(t) @> $3 AND to_jsonb(t.%I) IS NOT DISTINCT FROM $2',
    field->>'schema',field->>'table',field->>'field',field->>'schema',field->>'table',field->>'field',field->>'field')
   USING field->'replacement',field->'original',field->'key',field->>'field';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'Concurrent reference edit; entire cutover rolled back'; END IF;
 END LOOP;
 -- Shared content can feed public and private projections. Invalidate existing
 -- scopes through the canonical commit owner in the SAME transaction as edits.
 -- The publisher retains its normal claims, revisions and immutable artifacts.
 IF EXISTS(SELECT 1 FROM public.client_sync_scopes WHERE scope_type<>'occasion') THEN
  RAISE EXCEPTION 'Unreviewed non-occasion publication scope';
 END IF;
 FOR scope IN SELECT DISTINCT o.id FROM public.occasions o
  WHERE EXISTS(SELECT 1 FROM public.client_sync_scopes s WHERE s.scope_id=o.id AND s.scope_type='occasion')
   OR EXISTS(SELECT 1 FROM public.client_sync_private_scopes s WHERE s.occasion=o.id)
  ORDER BY o.id LOOP
  SELECT COALESCE(array_agg(component ORDER BY component),'{}') INTO components
   FROM public.client_sync_scopes WHERE scope_type='occasion' AND scope_id=scope.id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component',s.component,'userId',s.user_id)
   ORDER BY s.component,s.user_id),'[]') INTO impacts FROM public.client_sync_private_scopes s
   WHERE s.occasion=scope.id AND EXISTS(SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=scope.id AND ou."user"=s.user_id);
  PERFORM public.record_client_sync_commit_v1(scope.id,'storage.r2.retirement','catalog','[]',
   components,impacts,'[]','system','verified-manifest:'||manifest);
 END LOOP;
 UPDATE public.canonical_asset_cutover SET inventory_sha256=manifest WHERE singleton;
END $cutover$;
