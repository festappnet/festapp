-- Verified processing receipts, separate from portable geometry. There is no
-- client-authoritative URL/hash upload path and no image bytes in receipts.
CREATE TABLE IF NOT EXISTS public.blueprint_image_assets (
 occasion bigint REFERENCES public.occasions(id) ON DELETE CASCADE,
 unit bigint REFERENCES public.units(id) ON DELETE CASCADE,
 organization bigint NOT NULL REFERENCES public.organizations(id),
 asset_ref text NOT NULL CHECK(asset_ref ~ '^image:[0-9a-f]{64}$'),
 hash text NOT NULL CHECK(hash ~ '^[0-9a-f]{64}$'),
 url text NOT NULL, width integer NOT NULL CHECK(width BETWEEN 1 AND 3000),
 height integer NOT NULL CHECK(height BETWEEN 1 AND 3000),
 mime_type text NOT NULL CHECK(mime_type IN ('image/png','image/jpeg','image/webp')),
 byte_length integer NOT NULL CHECK(byte_length BETWEEN 1 AND 819200),
 state text NOT NULL DEFAULT 'ready' CHECK(state='ready'),
 image bigint REFERENCES public.images(id) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK((occasion IS NULL)<>(unit IS NULL)),CHECK(asset_ref='image:'||hash)
);
CREATE UNIQUE INDEX IF NOT EXISTS blueprint_image_assets_occasion_key ON public.blueprint_image_assets(occasion,asset_ref) WHERE occasion IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS blueprint_image_assets_unit_key ON public.blueprint_image_assets(unit,asset_ref) WHERE unit IS NOT NULL;
ALTER TABLE public.blueprint_image_assets OWNER TO postgres;
ALTER TABLE public.blueprint_image_assets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.blueprint_image_assets FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_blueprint_image_upload_access(p_occasion bigint,p_project text,p_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND (p_occasion IS NULL)<>(p_unit IS NULL) AND p_project IN ('default','a','slunovrat')
 AND CASE WHEN p_occasion IS NOT NULL THEN (public.get_is_editor_on_occasion(p_occasion) IS TRUE OR public.get_is_manager_on_occasion(p_occasion) IS TRUE)
 ELSE (public.get_is_editor_on_unit(p_unit) IS TRUE OR public.get_is_manager_on_unit(p_unit) IS TRUE) END
 AND EXISTS(SELECT 1 FROM (SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit) o
 WHERE coalesce((SELECT project FROM public.image_project_imports WHERE organization=o.organization),'default')=p_project)
$$;
REVOKE ALL ON FUNCTION public.get_blueprint_image_upload_access(bigint,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_blueprint_image_upload_access(bigint,text,bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.register_blueprint_image_asset(p_occasion bigint,p_project text,p_asset jsonb,p_issued_at bigint,p_proof text,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE secret_value text; message text; expected text; org bigint; image_id bigint; existing public.blueprint_image_assets; ext text; expected_url text;
BEGIN
 IF public.get_blueprint_image_upload_access(p_occasion,p_project,p_unit) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint image editor required'; END IF;
 IF p_occasion IS NOT NULL THEN PERFORM public.check_occasion_writable(p_occasion); END IF;
 IF jsonb_typeof(p_asset) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(p_asset))<>8
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_asset) key WHERE key NOT IN ('assetRef','hash','url','width','height','mimeType','byteLength','state')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_IMAGE_MANIFEST'; END IF;
 IF p_asset ? 'reserved' OR p_asset->>'state' IS DISTINCT FROM 'ready' OR coalesce(p_asset->>'hash','') !~ '^[a-f0-9]{64}$'
  OR p_asset->>'assetRef' IS DISTINCT FROM 'image:'||(p_asset->>'hash')
  OR jsonb_typeof(p_asset->'width') IS DISTINCT FROM 'number' OR jsonb_typeof(p_asset->'height') IS DISTINCT FROM 'number' OR jsonb_typeof(p_asset->'byteLength') IS DISTINCT FROM 'number'
  OR (p_asset->>'width')::numeric<>trunc((p_asset->>'width')::numeric) OR (p_asset->>'height')::numeric<>trunc((p_asset->>'height')::numeric)
  OR (p_asset->>'byteLength')::numeric<>trunc((p_asset->>'byteLength')::numeric)
  OR (p_asset->>'width')::numeric NOT BETWEEN 1 AND 3000 OR (p_asset->>'height')::numeric NOT BETWEEN 1 AND 3000
  OR (p_asset->>'byteLength')::numeric NOT BETWEEN 1 AND 819200 OR p_asset->>'mimeType' NOT IN ('image/png','image/jpeg','image/webp') THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_IMAGE_MANIFEST'; END IF;
 ext:=CASE p_asset->>'mimeType' WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/webp' THEN 'webp' END;
 expected_url:='https://'||CASE WHEN p_project='a' THEN 'a.img.festapp.net' ELSE 'img.festapp.net' END||'/images/'||CASE WHEN p_unit IS NULL THEN p_occasion::text ELSE 'unit-'||p_unit::text END||'/blueprint/'||(p_asset->>'hash')||'.'||ext;
 IF p_asset->>'url' IS DISTINCT FROM expected_url OR p_issued_at IS NULL OR p_issued_at<extract(epoch FROM statement_timestamp())-600 OR p_issued_at>extract(epoch FROM statement_timestamp())+30
  OR coalesce(p_proof,'') !~ '^[a-f0-9]{64}$' THEN RAISE insufficient_privilege USING MESSAGE='BLUEPRINT_IMAGE_ATTESTATION_REJECTED'; END IF;
 SELECT decrypted_secret INTO secret_value FROM vault.decrypted_secrets WHERE name='blueprint_image_processing_v1';
 IF secret_value IS NULL OR length(secret_value)<32 THEN RAISE configuration_limit_exceeded USING MESSAGE='BLUEPRINT_IMAGE_PROCESSOR_NOT_CONFIGURED'; END IF;
 message:=concat_ws(E'\n','blueprint-image-v1',CASE WHEN p_unit IS NULL THEN 'occasion:'||p_occasion::text ELSE 'unit:'||p_unit::text END,p_project,p_asset->>'assetRef',p_asset->>'hash',p_asset->>'url',p_asset->>'width',p_asset->>'height',p_asset->>'mimeType',p_asset->>'byteLength',p_issued_at::text);
 expected:=encode(extensions.hmac(convert_to(message,'UTF8'),convert_to(secret_value,'UTF8'),'sha256'),'hex');
 IF extensions.digest(convert_to(p_proof,'UTF8'),'sha256')<>extensions.digest(convert_to(expected,'UTF8'),'sha256') THEN RAISE insufficient_privilege USING MESSAGE='BLUEPRINT_IMAGE_ATTESTATION_REJECTED'; END IF;
 IF p_unit IS NULL THEN
  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
  SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
 ELSE
  PERFORM pg_advisory_xact_lock(hashtextextended('blueprint-image-unit:'||p_unit,0));
  SELECT organization INTO org FROM public.units WHERE id=p_unit;
 END IF;
 SELECT * INTO existing FROM public.blueprint_image_assets WHERE (occasion=p_occasion OR unit=p_unit) AND asset_ref=p_asset->>'assetRef';
 IF FOUND THEN
  IF existing.organization<>org OR existing.hash<>p_asset->>'hash' OR existing.url<>p_asset->>'url' OR existing.width<>(p_asset->>'width')::integer OR existing.height<>(p_asset->>'height')::integer OR existing.mime_type<>p_asset->>'mimeType' OR existing.byte_length<>(p_asset->>'byteLength')::integer THEN RAISE check_violation USING MESSAGE='BLUEPRINT_IMAGE_IMMUTABLE'; END IF;
  RETURN p_asset;
 END IF;
 image_id:=public.add_image_record_internal(p_asset->>'url',p_occasion,p_unit);
 INSERT INTO public.blueprint_image_assets(occasion,unit,organization,asset_ref,hash,url,width,height,mime_type,byte_length,image)
 VALUES(p_occasion,p_unit,org,p_asset->>'assetRef',p_asset->>'hash',p_asset->>'url',(p_asset->>'width')::integer,(p_asset->>'height')::integer,p_asset->>'mimeType',(p_asset->>'byteLength')::integer,image_id);
 RETURN p_asset;
END $$;
REVOKE ALL ON FUNCTION public.register_blueprint_image_asset(bigint,text,jsonb,bigint,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.register_blueprint_image_asset(bigint,text,jsonb,bigint,text,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_blueprint_image_resource_internal(p_layout jsonb,p_occasion bigint)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE b jsonb:=p_layout->'background'; a public.blueprint_image_assets; field text; value jsonb;
BEGIN
 IF b IS NULL OR b='null'::jsonb THEN RETURN; END IF;
 IF jsonb_typeof(b)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(b) key WHERE key NOT IN ('assetRef','hash','x','y','rotation','width','height','scale','opacity','crop')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND'; END IF;
 SELECT * INTO a FROM public.blueprint_image_assets WHERE occasion=p_occasion AND asset_ref=b->>'assetRef' AND organization=(SELECT organization FROM public.occasions WHERE id=p_occasion) AND state='ready';
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='BLUEPRINT_ASSET_RESOURCE_NOT_READY'; END IF;
 IF b->>'hash' IS DISTINCT FROM a.hash OR (b->>'width')::numeric IS DISTINCT FROM a.width::numeric OR (b->>'height')::numeric IS DISTINCT FROM a.height::numeric THEN RAISE check_violation USING MESSAGE='BLUEPRINT_ASSET_MANIFEST_MISMATCH'; END IF;
 FOREACH field IN ARRAY ARRAY['x','y','rotation','width','height','scale'] LOOP
  value:=b->field;
  IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR abs(value::numeric)>1000000000 OR field IN ('width','height','scale') AND value::numeric<=0 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND'; END IF;
 END LOOP;
 IF b ? 'opacity' AND (jsonb_typeof(b->'opacity')<>'number' OR (b->>'opacity')::numeric NOT BETWEEN 0 AND 1) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND'; END IF;
 IF jsonb_typeof(b->'crop') IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(b->'crop') key WHERE key NOT IN ('x','y','width','height')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND_CROP'; END IF;
 FOREACH field IN ARRAY ARRAY['x','y','width','height'] LOOP
  value:=b->'crop'->field;
  IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR value::numeric NOT BETWEEN 0 AND 1 OR field IN ('width','height') AND value::numeric<=0 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND_CROP'; END IF;
 END LOOP;
 IF (b#>>'{crop,x}')::numeric+(b#>>'{crop,width}')::numeric>1 OR (b#>>'{crop,y}')::numeric+(b#>>'{crop,height}')::numeric>1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BACKGROUND_CROP'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_image_resource_internal(jsonb,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Only existing authorized setup/copy owners may associate immutable verified
-- source bytes with another occasion. Client code cannot mint readiness.
CREATE OR REPLACE FUNCTION public.copy_blueprint_image_resources_internal(p_source_occasion bigint,p_target_occasion bigint,p_layout jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_layout->>'schemaVersion'='2' THEN
  PERFORM public.copy_blueprint_canonical_bitmap_resources_internal(p_source_occasion,NULL,p_target_occasion,p_layout);RETURN;
 END IF;
 IF p_source_occasion=p_target_occasion THEN
  PERFORM public.check_blueprint_image_resource_internal(p_layout,p_source_occasion);RETURN;
 END IF;
 PERFORM public.check_blueprint_image_resource_internal(p_layout,p_source_occasion);
 IF (SELECT organization FROM public.occasions WHERE id=p_source_occasion) IS DISTINCT FROM (SELECT organization FROM public.occasions WHERE id=p_target_occasion) THEN RAISE insufficient_privilege USING MESSAGE='same organization image copy required';END IF;
 INSERT INTO public.blueprint_image_assets(occasion,organization,asset_ref,hash,url,width,height,mime_type,byte_length,state)
 SELECT p_target_occasion,o.organization,a.asset_ref,a.hash,a.url,a.width,a.height,a.mime_type,a.byte_length,a.state
 FROM public.blueprint_image_assets a JOIN public.occasions o ON o.id=p_target_occasion
 WHERE a.occasion=p_source_occasion AND a.asset_ref=p_layout#>>'{background,assetRef}'
 ON CONFLICT(occasion,asset_ref) WHERE occasion IS NOT NULL DO NOTHING;
 PERFORM public.check_blueprint_image_resource_internal(p_layout,p_target_occasion);
END $$;
REVOKE ALL ON FUNCTION public.copy_blueprint_image_resources_internal(bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.copy_blueprint_unit_image_resources_internal(p_source_unit bigint,p_target_occasion bigint,p_layout jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE a public.blueprint_image_assets;
BEGIN
 IF p_layout->>'schemaVersion'='2' THEN
  PERFORM public.copy_blueprint_canonical_bitmap_resources_internal(NULL,p_source_unit,p_target_occasion,p_layout);RETURN;
 END IF;
 IF p_layout->'background' IS NULL OR p_layout->'background'='null'::jsonb THEN RETURN;END IF;
 SELECT * INTO a FROM public.blueprint_image_assets WHERE unit=p_source_unit AND asset_ref=p_layout#>>'{background,assetRef}' AND state='ready';
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.occasions o WHERE o.id=p_target_occasion AND o.unit=p_source_unit AND o.organization=a.organization) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_ASSET_RESOURCE_NOT_READY';END IF;
 INSERT INTO public.blueprint_image_assets(occasion,organization,asset_ref,hash,url,width,height,mime_type,byte_length,state)
 VALUES(p_target_occasion,a.organization,a.asset_ref,a.hash,a.url,a.width,a.height,a.mime_type,a.byte_length,a.state)
 ON CONFLICT(occasion,asset_ref) WHERE occasion IS NOT NULL DO NOTHING;
 PERFORM public.check_blueprint_image_resource_internal(p_layout,p_target_occasion);
END $$;
REVOKE ALL ON FUNCTION public.copy_blueprint_unit_image_resources_internal(bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION public.get_blueprint_image_upload_access(bigint,text,bigint) OWNER TO postgres;
ALTER FUNCTION public.register_blueprint_image_asset(bigint,text,jsonb,bigint,text,bigint) OWNER TO postgres;
