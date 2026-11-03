CREATE OR REPLACE FUNCTION public.blueprint_layout_asset_refs_internal(p_layout jsonb)
RETURNS TABLE(asset_ref text,hash text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH RECURSIVE documents(doc) AS (SELECT p_layout UNION ALL SELECT preset->'document' FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'presets','[]')) preset)
 SELECT doc#>>'{background,assetRef}',doc#>>'{background,hash}' FROM documents WHERE doc#>>'{background,assetRef}' IS NOT NULL
 UNION SELECT node#>>'{graphic,assetRef}',node#>>'{graphic,hash}' FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node WHERE node->>'kind'='image'
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_asset_refs_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_canonical_asset_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_object_agg(a.asset_ref,jsonb_build_object('hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length)),'{}')
 FROM public.blueprint_image_assets a WHERE (a.occasion=p_occasion OR a.unit=p_unit) AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit)
  AND a.state='ready' AND EXISTS(SELECT 1 FROM public.blueprint_layout_asset_refs_internal(p_layout) r WHERE r.asset_ref=a.asset_ref AND r.hash=a.hash)
$$;
REVOKE ALL ON FUNCTION public.blueprint_canonical_asset_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_blueprint_bitmap_resources_internal(p_layout jsonb,p_occasion bigint)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.blueprint_layout_asset_refs_internal(p_layout) r WHERE NOT EXISTS(SELECT 1 FROM public.blueprint_image_assets a WHERE a.occasion=p_occasion AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) AND a.asset_ref=r.asset_ref AND a.hash=r.hash AND a.state='ready')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_IMAGE_RESOURCE_NOT_READY';END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_bitmap_resources_internal(jsonb,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';END IF;
 RETURN public.blueprint_canonical_text_resources_internal(p_layout,p_occasion,NULL,true)||jsonb_build_object('assets',public.blueprint_canonical_asset_resources_internal(p_layout,p_occasion,p_unit));
END $$;
REVOKE ALL ON FUNCTION public.blueprint_layout_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.copy_blueprint_text_resources_internal(p_source_occasion bigint,p_source_draft uuid,p_target bigint,p_layout jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE entry record;old jsonb;scope text:='occasion:'||p_target::text;
BEGIN
 IF (p_source_occasion IS NULL)=(p_source_draft IS NULL) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_COPY_SCOPE';END IF;
 FOR entry IN SELECT DISTINCT r.resource_id,r.resource_kind,r.payload FROM public.blueprint_text_resources r JOIN public.blueprint_layout_text_requests_internal(p_layout,true) q
  ON r.payload->'descriptor' @> q.descriptor AND r.payload->'descriptor'=q.descriptor
  WHERE r.scope_key=CASE WHEN p_source_occasion IS NOT NULL THEN 'occasion:'||p_source_occasion::text ELSE 'setup:'||p_source_draft::text END LOOP
  SELECT payload INTO old FROM public.blueprint_text_resources WHERE scope_key=scope AND resource_id=entry.resource_id;
  IF FOUND AND old IS DISTINCT FROM entry.payload THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_IMMUTABLE';END IF;
  INSERT INTO public.blueprint_text_resources(scope_key,occasion,resource_id,resource_kind,payload) VALUES(scope,p_target,entry.resource_id,entry.resource_kind,entry.payload) ON CONFLICT DO NOTHING;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.copy_blueprint_text_resources_internal(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Internal caller supplies a source occasion and/or the authorized setup unit.
-- Only exact referenced processed manifests are copied into the new aggregate.
CREATE OR REPLACE FUNCTION public.copy_blueprint_canonical_bitmap_resources_internal(p_source bigint,p_unit bigint,p_target bigint,p_layout jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE ref record; asset public.blueprint_image_assets; target_org bigint; target_unit bigint;
BEGIN
 SELECT organization,unit INTO target_org,target_unit FROM public.occasions WHERE id=p_target;
 IF target_org IS NULL OR (p_source IS NOT NULL AND (SELECT organization FROM public.occasions WHERE id=p_source) IS DISTINCT FROM target_org)
  OR (p_unit IS NOT NULL AND p_unit IS DISTINCT FROM target_unit) THEN RAISE insufficient_privilege USING MESSAGE='BLUEPRINT_INVALID_ASSET_COPY_SCOPE';END IF;
 FOR ref IN SELECT * FROM public.blueprint_layout_asset_refs_internal(p_layout) LOOP
  SELECT * INTO asset FROM public.blueprint_image_assets a WHERE a.organization=target_org AND a.asset_ref=ref.asset_ref AND a.hash=ref.hash AND a.state='ready'
   AND (a.occasion=p_source OR a.unit=p_unit OR a.occasion=p_target) ORDER BY a.occasion NULLS LAST LIMIT 1;
  IF NOT FOUND THEN RAISE check_violation USING MESSAGE='BLUEPRINT_IMAGE_RESOURCE_NOT_READY';END IF;
  INSERT INTO public.blueprint_image_assets(occasion,organization,asset_ref,hash,url,width,height,mime_type,byte_length,state)
  VALUES(p_target,target_org,asset.asset_ref,asset.hash,asset.url,asset.width,asset.height,asset.mime_type,asset.byte_length,asset.state)
  ON CONFLICT(occasion,asset_ref) WHERE occasion IS NOT NULL DO NOTHING;
 END LOOP;
 PERFORM public.check_blueprint_bitmap_resources_internal(p_layout,p_target);
END $$;
REVOKE ALL ON FUNCTION public.copy_blueprint_canonical_bitmap_resources_internal(bigint,bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Viewers receive geometry and prepared paint only. Original imported SVG and
-- private reusable presets stay in the permission-checked authoring projection.
CREATE OR REPLACE FUNCTION public.blueprint_public_document_internal(p_layout jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT jsonb_set(jsonb_set(p_layout,'{presets}','[]'),'{nodes}',
  coalesce((SELECT jsonb_agg(node-'originalSource' ORDER BY position)
    FROM jsonb_array_elements(p_layout->'nodes') WITH ORDINALITY records(node,position)),'[]'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_public_document_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
