-- Verified blueprint images through the existing upload/processing/quota/gallery owners.

-- Source: database/functions/abuse/media.sql
-- The actual IO adapter supplies the measured file size before transform/R2 put.
-- A direct call grants no storage capability and cannot refund committed IO work.
CREATE OR REPLACE FUNCTION public.admit_image_upload_budget_internal(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; costs jsonb;
BEGIN
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='image bytes required'; END IF;
 IF p_occasion_id IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion_id;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit_id; END IF;
 policy:=public.abuse_effective_rules_v1('image.upload',un,org);
 costs:=jsonb_build_object('image.upload.actor.bytes',p_bytes,'image.upload.unit.bytes',p_bytes,'image.upload.organization.bytes',p_bytes);
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org),costs);
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_upload_v1(p_bytes bigint,p_occasion_id bigint DEFAULT NULL,p_unit_id bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion_id IS NULL)=(p_unit_id IS NULL)
  OR public.check_upload_permission(p_occasion_id,p_unit_id) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='image editor required'; END IF;
 RETURN public.admit_image_upload_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_upload_v1(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint,p_profile text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_profile IS DISTINCT FROM 'blueprint-background' OR (p_occasion_id IS NULL)=(p_unit_id IS NULL) OR auth.uid() IS NULL
  OR NOT (CASE WHEN p_unit_id IS NULL THEN (coalesce(public.get_is_editor_on_occasion(p_occasion_id),false) OR coalesce(public.get_is_manager_on_occasion(p_occasion_id),false)) ELSE (coalesce(public.get_is_editor_on_unit(p_unit_id),false) OR coalesce(public.get_is_manager_on_unit(p_unit_id),false)) END) THEN RAISE insufficient_privilege USING MESSAGE='blueprint image editor required'; END IF;
 RETURN public.admit_image_upload_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;

GRANT EXECUTE ON FUNCTION public.admit_image_upload_v1(bigint,bigint,bigint,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admit_image_upload_budget_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;








-- Called with actual transformed output bytes by the existing R2 IO adapter.
-- A direct RPC cannot write to R2 or refund any committed allocation.
CREATE OR REPLACE FUNCTION public.admit_image_storage_budget_internal(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='actual storage bytes required'; END IF;
 IF p_occasion_id IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion_id;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit_id; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('image.storage',un,org),
  jsonb_build_object('unit',un,'organization',org,'global','all'),
  jsonb_build_object('image.storage.unit.bytes',p_bytes,'image.storage.organization.bytes',p_bytes,'image.storage.global.bytes',p_bytes));
 RETURN true;
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_storage_v1(p_bytes bigint,p_occasion_id bigint DEFAULT NULL,p_unit_id bigint DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion_id IS NULL)=(p_unit_id IS NULL)
  OR public.check_upload_permission(p_occasion_id,p_unit_id) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='image editor required'; END IF;
 RETURN public.admit_image_storage_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_storage_v1(p_bytes bigint,p_occasion_id bigint,p_unit_id bigint,p_profile text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_profile IS DISTINCT FROM 'blueprint-background' OR (p_occasion_id IS NULL)=(p_unit_id IS NULL) OR auth.uid() IS NULL
  OR NOT (CASE WHEN p_unit_id IS NULL THEN (coalesce(public.get_is_editor_on_occasion(p_occasion_id),false) OR coalesce(public.get_is_manager_on_occasion(p_occasion_id),false)) ELSE (coalesce(public.get_is_editor_on_unit(p_unit_id),false) OR coalesce(public.get_is_manager_on_unit(p_unit_id),false)) END) THEN RAISE insufficient_privilege USING MESSAGE='blueprint image editor required'; END IF;
 RETURN public.admit_image_storage_budget_internal(p_bytes,p_occasion_id,p_unit_id);
END $$;

GRANT EXECUTE ON FUNCTION public.admit_image_storage_v1(bigint,bigint,bigint,text) TO authenticated;
REVOKE ALL ON FUNCTION public.admit_image_storage_budget_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;





-- Source: database/functions/abuse/image_records.sql
-- Canonical R2 image record admission; legacy Storage policy history stays in its installed migration.
CREATE INDEX IF NOT EXISTS images_occasion_abuse ON public.images(occasion) WHERE occasion IS NOT NULL;
CREATE INDEX IF NOT EXISTS images_unit_abuse ON public.images(unit) WHERE unit IS NOT NULL;
CREATE OR REPLACE FUNCTION public.admit_image_record_budget_internal(p_link text,p_occasion bigint,p_unit bigint) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; scopes jsonb; r jsonb; unit_count bigint; org_count bigint;
BEGIN
 IF p_link IS NULL OR p_link !~ '^https://(a\.)?img\.festapp\.net/images/[A-Za-z0-9_./-]+$' THEN
  RAISE invalid_parameter_value USING MESSAGE='canonical public image URL required'; END IF;
 IF p_occasion IS NOT NULL THEN SELECT unit,organization INTO un,org FROM public.occasions WHERE id=p_occasion;
 ELSE SELECT id,organization INTO un,org FROM public.units WHERE id=p_unit; END IF;
 policy:=public.abuse_effective_rules_v1('image.records',un,org);
 scopes:=jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' IN ('rolling','occupancy') THEN
   PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
  END IF;
 END LOOP;
 SELECT count(*) FILTER(WHERE coalesce(i.unit,o.unit)=un),count(*) INTO unit_count,org_count
 FROM public.images i LEFT JOIN public.occasions o ON o.id=i.occasion LEFT JOIN public.units u ON u.id=i.unit
 WHERE coalesce(o.organization,u.organization)=org;
 PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('image.records.link.bytes',octet_length(p_link),
  'image.records.stored.unit',unit_count+1,'image.records.stored.organization',org_count+1));
END $$;
CREATE OR REPLACE FUNCTION public.admit_image_record_v1(p_link text,p_occasion bigint,p_unit bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR (p_occasion IS NULL)=(p_unit IS NULL) OR public.check_upload_permission(p_occasion,p_unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='exactly one authorized image owner required'; END IF;
 PERFORM public.admit_image_record_budget_internal(p_link,p_occasion,p_unit);
END $$;
REVOKE ALL ON FUNCTION public.admit_image_record_budget_internal(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE INSERT,UPDATE ON public.images FROM PUBLIC,anon,authenticated;


-- Source: database/functions/others/add_image_record.sql
-- The existing gallery insertion/admission/sync owner, shared by verified
-- blueprint processing and the original permission-checked public wrapper.
CREATE OR REPLACE FUNCTION public.add_image_record_internal(p_link text,p_occasion_id bigint,p_unit_id bigint)
RETURNS bigint LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_image_id bigint;
BEGIN
    -- Insert Record
    PERFORM public.admit_image_record_budget_internal(p_link,p_occasion_id,p_unit_id);
    INSERT INTO public.images (link, occasion, unit)
    VALUES (p_link, p_occasion_id, p_unit_id)
    RETURNING id INTO v_image_id;

    IF p_occasion_id IS NOT NULL THEN
      PERFORM public.record_client_sync_commit_v1(
        p_occasion_id,'image.add','content',jsonb_build_array(jsonb_build_object(
          'entityType','occasion_image','entityId',v_image_id::text,
          'operation','insert','safeLabel',left(p_link,240),
          'changedFields',jsonb_build_array('link'))),
        ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'user',NULL);
    END IF;
 RETURN v_image_id;
END $$;
REVOKE ALL ON FUNCTION public.add_image_record_internal(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.add_image_record(p_link text, p_occasion_id bigint, p_unit_id bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE v_image_id bigint;
BEGIN
    -- Permission Check
    IF p_unit_id IS NOT NULL THEN
        -- Unit Editor
        IF (SELECT public.get_is_editor_on_unit(p_unit_id)) IS NOT TRUE THEN
            RAISE EXCEPTION 'Permission denied: User is not an editor of this unit.';
        END IF;
    ELSIF p_occasion_id IS NOT NULL THEN
        -- Occasion Editor OR Occasion Order Editor
        IF (public.get_is_editor_on_occasion(p_occasion_id)) IS NOT TRUE 
           AND (public.get_is_editor_order_on_occasion(p_occasion_id)) IS NOT TRUE THEN
             RAISE EXCEPTION 'Permission denied: User is not an editor/order-editor of this occasion.';
        END IF;
    ELSE
        RAISE EXCEPTION 'Entity ID (unit or occasion) must be provided.';
    END IF;

    PERFORM public.add_image_record_internal(p_link,p_occasion_id,p_unit_id);

END;
$$;


-- Source: database/functions/blueprint/image_assets.sql
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


-- Source: database/functions/others/authorize_image_deletion.sql
CREATE OR REPLACE FUNCTION public.authorize_image_deletion(p_links text[])
RETURNS TABLE(link text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_requested_count integer;
  v_found_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  v_requested_count := cardinality(p_links);
  IF v_requested_count IS NULL OR v_requested_count < 1 OR v_requested_count > 50
     OR array_position(p_links, NULL) IS NOT NULL
     OR v_requested_count <> (SELECT count(DISTINCT requested) FROM unnest(p_links) AS requested) THEN
    RAISE EXCEPTION 'Image link batch must contain 1-50 unique non-null links.'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(DISTINCT image.link) INTO v_found_count
  FROM public.images AS image
  WHERE image.link = ANY(p_links);

  IF v_found_count <> v_requested_count THEN
    RAISE EXCEPTION 'Every image link must exist.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.images AS image
    WHERE image.link = ANY(p_links)
      AND NOT (
        (image.unit IS NOT NULL AND public.get_is_editor_on_unit(image.unit))
        OR
        (image.occasion IS NOT NULL AND (
          public.get_is_editor_on_occasion(image.occasion)
          OR public.get_is_editor_order_on_occasion(image.occasion)
        ))
      )
  ) THEN
    RAISE EXCEPTION 'Permission denied for image deletion.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS(SELECT 1 FROM public.blueprint_image_assets a WHERE a.url=ANY(p_links)) THEN
    RAISE insufficient_privilege USING MESSAGE='BLUEPRINT_IMAGE_IMMUTABLE'; END IF;

  RETURN QUERY
  SELECT DISTINCT image.link
  FROM public.images AS image
  WHERE image.link = ANY(p_links)
  ORDER BY image.link;
END;
$$;






-- Source: database/functions/blueprint/resources.sql
ALTER TABLE public.ticket_font_assets ADD COLUMN IF NOT EXISTS layout_outline jsonb;



CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('protocol',1,'fonts',coalesce((SELECT jsonb_object_agg(a.id,a.layout_outline)
 FROM public.ticket_font_assets a WHERE a.layout_outline IS NOT NULL AND a.id IN (
  SELECT p_layout#>>'{defaultTextStyle,fontId}' UNION SELECT n->>'fontId' FROM jsonb_array_elements(coalesce(p_layout->'nodes','[]')) n)),'{}'),
 'assets',coalesce((SELECT jsonb_object_agg(a.asset_ref,jsonb_build_object('hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length))
 FROM public.blueprint_image_assets a WHERE (a.occasion=p_occasion OR a.unit=p_unit) AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit)
 AND a.state='ready' AND a.asset_ref=p_layout#>>'{background,assetRef}' AND a.hash=p_layout#>>'{background,hash}'),'{}'))
$$;



-- Source: database/functions/blueprint/validation.sql



-- Storage boundary validation. Numeric limits and authoring keys mirror the
-- public layout protocol; commercial identities never belong in the document.
CREATE OR REPLACE FUNCTION public.validate_blueprint_layout_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n jsonb; value jsonb; field text; index_nodes jsonb; current_node jsonb; seen text[]; depth int; a jsonb; ids text[]; referenced text; font jsonb; ch text; shape text;
 geometry_keys text[]:=ARRAY['shape','cornerRadius','appearanceOverrides','seatStyle','seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding','objectStyle','fill','stroke','strokeWidth','strokeStyle','dash','opacity','points','holes','pathPattern','zigzagTeeth','zigzagAmplitude','arrowHeadLength','text','fontId','labelOrientation','fontStyle','size','color','align','lineHeight','bold','italic','symbol','role','obstacle','manual','manualRotation','slot','assembly','rows','seatsPerRow','blocks','aisle','spacing','rowSpacing','arc','left','right','rear','decks','upperRows','upperRear','deck','compartments','seats','capacity','furniture','guestSide'];
BEGIN
 IF jsonb_typeof(p_doc) IS DISTINCT FROM 'object' OR p_doc->>'schemaVersion' IS DISTINCT FROM '1' OR p_doc->>'symbolSetVersion' IS DISTINCT FROM '1'
  OR jsonb_typeof(p_doc->'nodes') IS DISTINCT FROM 'array' OR jsonb_typeof(p_doc->'canvas') IS DISTINCT FROM 'object' THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc) key WHERE key<>ALL(ARRAY['appearance','schemaVersion','symbolSetVersion','canvas','defaultTextStyle','nodes','sections','selectionUnits','attachments','generators','background','presets'])) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_UNKNOWN_LAYOUT_FIELD'; END IF;
 IF jsonb_array_length(p_doc->'nodes')>25000 OR (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes') x WHERE x->>'kind'='seat')>20000 THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_LIMIT'; END IF;
 IF EXISTS(WITH RECURSIVE entries(value,key,depth) AS (
   SELECT p_doc,''::text,0 UNION ALL SELECT child.value,child.key,entries.depth+1 FROM entries CROSS JOIN LATERAL (
    SELECT object.value,object.key FROM jsonb_each(CASE WHEN jsonb_typeof(entries.value)='object' THEN entries.value ELSE '{}'::jsonb END) object
    UNION ALL SELECT element.value,''::text FROM jsonb_array_elements(CASE WHEN jsonb_typeof(entries.value)='array' THEN entries.value ELSE '[]'::jsonb END) element
   ) child WHERE entries.depth<=64)
   SELECT 1 FROM entries WHERE entries.depth>64 OR lower(regexp_replace(key,'[_-]','','g')) IN
    ('spot','spotid','product','productid','price','unitprice','currency','orderid','ticket','ticketid','secret','secretid','token','accesstoken','refreshtoken','customer','customerid','email','payment','paymentid','reservation','reservationid','hold','holdid','selected','pending','status','camera','viewport') LIMIT 1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_NON_PORTABLE_LAYOUT'; END IF;
 FOREACH field IN ARRAY ARRAY['sections','selectionUnits','attachments','generators','presets'] LOOP
  IF p_doc ? field AND jsonb_typeof(p_doc->field) IS DISTINCT FROM 'array' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT_COLLECTION'; END IF;
 END LOOP;
 FOREACH field IN ARRAY ARRAY['x','y','width','height'] LOOP
  value:=p_doc->'canvas'->field;
  IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR abs(value::numeric)>1000000000
   OR (field IN ('width','height') AND (value::numeric<64 OR value::numeric>1000000)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANVAS'; END IF;
 END LOOP;
 IF coalesce(p_doc#>>'{canvas,fill}','') !~ '^#[0-9a-fA-F]{8}$'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc->'canvas') key WHERE key<>ALL(ARRAY['x','y','width','height','fill','floorStyle']))
  OR (p_doc#>>'{canvas,floorStyle}' IS NOT NULL AND p_doc#>>'{canvas,floorStyle}' NOT IN ('plain','wood','tile','carpet')) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANVAS'; END IF;
 IF jsonb_typeof(p_doc->'defaultTextStyle') IS DISTINCT FROM 'object' OR coalesce(p_doc#>>'{defaultTextStyle,color}','') !~ '^#[0-9a-fA-F]{8}$'
  OR jsonb_typeof(p_doc#>'{defaultTextStyle,size}') IS DISTINCT FROM 'number' OR (p_doc#>>'{defaultTextStyle,size}')::numeric NOT BETWEEN 1 AND 4096
  OR nullif(p_doc#>>'{defaultTextStyle,fontId}','') IS NULL
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc->'defaultTextStyle') key WHERE key<>ALL(ARRAY['fontId','size','color','align','lineHeight','bold','italic','fontStyle'])) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF;
 IF p_doc#>>'{defaultTextStyle,align}' IS NOT NULL AND p_doc#>>'{defaultTextStyle,align}' NOT IN ('left','center','right')
  OR p_doc#>>'{defaultTextStyle,fontStyle}' IS NOT NULL AND p_doc#>>'{defaultTextStyle,fontStyle}' NOT IN ('normal','italic')
  OR p_doc#>'{defaultTextStyle,lineHeight}' IS NOT NULL AND (jsonb_typeof(p_doc#>'{defaultTextStyle,lineHeight}')<>'number' OR (p_doc#>>'{defaultTextStyle,lineHeight}')::numeric NOT BETWEEN 0.8 AND 3) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF;
 FOREACH field IN ARRAY ARRAY['bold','italic'] LOOP IF p_doc->'defaultTextStyle' ? field AND jsonb_typeof(p_doc->'defaultTextStyle'->field)<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT_STYLE'; END IF; END LOOP;
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}') INTO index_nodes FROM jsonb_array_elements(p_doc->'nodes') x;
 IF (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes'))<>(SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_doc->'nodes') x) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_NODE'; END IF;
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  IF jsonb_typeof(n) IS DISTINCT FROM 'object' OR coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   OR coalesce(n->>'kind','') NOT IN ('group','table','seat','furniture','capacityArea','shape','text')
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key<>ALL(geometry_keys||ARRAY['id','kind','parentId','transform','width','height','z','locked','label'])) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  IF jsonb_typeof(n->'transform') IS DISTINCT FROM 'object'
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n->'transform') key WHERE key NOT IN ('x','y','rotation')) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GEOMETRY'; END IF;
  FOREACH field IN ARRAY ARRAY['width','height','x','y','rotation'] LOOP
   value:=CASE WHEN field IN ('width','height') THEN n->field ELSE n->'transform'->field END;
   IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR abs(value::numeric)>1000000000 OR (field IN ('width','height') AND value::numeric<=0) THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GEOMETRY',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  END LOOP;
  IF n ? 'z' AND (jsonb_typeof(n->'z')<>'number' OR (n->>'z')::numeric<>trunc((n->>'z')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_Z'; END IF;
  FOREACH field IN ARRAY ARRAY['locked','bold','italic','manual','manualRotation','obstacle'] LOOP
   IF n ? field AND jsonb_typeof(n->field)<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN'; END IF;
  END LOOP;
  FOREACH field IN ARRAY ARRAY['fill','stroke','color'] LOOP
   IF n ? field AND coalesce(n->>field,'') !~ '^#[0-9a-fA-F]{8}$' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_COLOR'; END IF;
  END LOOP;
  FOREACH field IN ARRAY ARRAY['cornerRadius','strokeWidth','seatWidth','seatHeight','seatGap','seatSpacing','seatEdgePadding','opacity','size','lineHeight','zigzagAmplitude','arrowHeadLength','spacing','rowSpacing'] LOOP
   IF n ? field THEN
    value:=n->field;
    IF jsonb_typeof(value)<>'number' OR value::numeric<0 OR value::numeric>1000000000
     OR (field='opacity' AND value::numeric>1) OR (field='size' AND value::numeric NOT BETWEEN 1 AND 4096)
     OR (field='lineHeight' AND value::numeric NOT BETWEEN 0.8 AND 3)
     OR (field='arrowHeadLength' AND value::numeric<=0)
     OR (field IN ('seatWidth','seatHeight') AND value::numeric NOT BETWEEN 1 AND 1000000) THEN
     RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_STYLE'; END IF;
   END IF;
  END LOOP;
  IF n->>'objectStyle' IS NOT NULL AND n->>'objectStyle' NOT IN ('round','simple','minimal','wood','lounge','transit','hall','banquet')
   OR n->>'seatStyle' IS NOT NULL AND n->>'seatStyle' NOT IN ('roundUpholstered','round','plain','wood','upholstered','transit','banquet')
   OR n->>'fontStyle' IS NOT NULL AND n->>'fontStyle' NOT IN ('normal','italic')
   OR n->>'align' IS NOT NULL AND n->>'align' NOT IN ('left','center','right') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_STYLE'; END IF;
  IF n ? 'dash' AND (jsonb_typeof(n->'dash')<>'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements(n->'dash') dash WHERE jsonb_typeof(dash)<>'number' OR dash::numeric<=0)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DASH'; END IF;
  IF n ? 'capacity' AND (jsonb_typeof(n->'capacity')<>'number' OR (n->>'capacity')::numeric<0 OR (n->>'capacity')::numeric<>trunc((n->>'capacity')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
  shape:=n->>'shape';
  IF shape IS NOT NULL AND shape NOT IN ('rect','rectangle','roundedRect','ellipse','oval','circle','round','polygon','polyline','line','arrow') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SHAPE'; END IF;
  IF n->>'labelOrientation' IS NOT NULL AND n->>'labelOrientation' NOT IN ('screen','object') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LABEL_ORIENTATION'; END IF;
  IF n->>'symbol' IS NOT NULL AND n->>'symbol' NOT IN ('chair','bench','sofa','wheelchair','driver') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SYMBOL'; END IF;
  IF n->>'strokeStyle' IS NOT NULL AND n->>'strokeStyle' NOT IN ('solid','dashed','dotted') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STROKE'; END IF;
  IF n->>'text' IS NOT NULL AND (jsonb_typeof(n->'text')<>'string' OR length(n->>'text')>4096) OR n->>'kind'='text' AND n->>'text' IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_TEXT'; END IF;
  IF n ? 'label' AND jsonb_typeof(n->'label')<>'string' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LABEL'; END IF;
  IF n ? 'points' THEN PERFORM public.validate_blueprint_polygon_internal(n->'points',shape='polygon');
  ELSIF shape='polygon' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MISSING_VERTICES'; END IF;
  IF n ? 'holes' THEN
   IF shape<>'polygon' OR jsonb_typeof(n->'holes')<>'array' OR jsonb_array_length(n->'holes')>128 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_HOLES'; END IF;
   FOR value IN SELECT * FROM jsonb_array_elements(n->'holes') LOOP PERFORM public.validate_blueprint_polygon_internal(value,true); END LOOP;
  END IF;
  current_node:=n; seen:=ARRAY[n->>'id'];depth:=1;
  WHILE current_node->>'parentId' IS NOT NULL LOOP
   referenced:=current_node->>'parentId';
   IF referenced=ANY(seen) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PARENT_CYCLE'; END IF;
   current_node:=index_nodes->referenced;
   IF current_node IS NULL OR current_node->>'kind' NOT IN ('group','table','furniture') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PARENT'; END IF;
   seen:=array_append(seen,referenced);depth:=depth+1;
   IF depth>16 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DEPTH_LIMIT'; END IF;
  END LOOP;
 END LOOP;
 -- All authoring IDs use a common UUID namespace, including sections/units.
 SELECT array_agg(x->>'id') INTO ids FROM jsonb_array_elements(p_doc->'nodes') x;
 FOR n IN SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) item UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'selectionUnits','[]')) item
  UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'generators','[]')) item UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) item LOOP
  IF coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' OR n->>'id'=ANY(ids) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_OR_INVALID_ID'; END IF;
  ids:=array_append(ids,n->>'id');
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) LOOP
  IF coalesce(index_nodes->(a->>'seatId')->>'kind','')<>'seat' OR coalesce(index_nodes->(a->>'targetId')->>'kind','')<>'table'
   OR index_nodes->(a->>'seatId')->>'parentId' IS DISTINCT FROM a->>'targetId'
   OR coalesce(a->>'kind','') NOT IN ('edge','perimeter') OR jsonb_typeof(a->'t') IS DISTINCT FROM 'number' OR (a->>'t')::numeric NOT BETWEEN 0 AND 1
   OR jsonb_typeof(a->'gap') IS DISTINCT FROM 'number' OR (a->>'gap')::numeric<0 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ATTACHMENT'; END IF;
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) LOOP
  IF coalesce(index_nodes->(a->>'rootId')->>'kind','')<>'group' OR coalesce(a->>'title','')='' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SECTION'; END IF;
  IF a->'outline' IS NOT NULL AND a->'outline'<>'null'::jsonb THEN PERFORM public.validate_blueprint_polygon_internal(a->'outline',true); END IF;
 END LOOP;
 IF EXISTS(SELECT attachment->>'seatId' FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) attachment GROUP BY attachment->>'seatId' HAVING count(*)>1)
  OR EXISTS(SELECT section->>'rootId' FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) section GROUP BY section->>'rootId' HAVING count(*)>1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_AUTHORING_REFERENCE'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'generators','[]')) LOOP
  referenced:=coalesce(a->>'rootId',a->>'assemblyId');
  IF coalesce(a->>'kind','') NOT IN ('rows','row','arc','bus','compartments','table') OR coalesce(index_nodes->referenced->>'kind','')<>(CASE WHEN a->>'kind'='table' THEN 'table' ELSE 'group' END)
   OR (a ? 'version' AND a->>'version'<>'1') OR (a ? 'rootId' AND a ? 'assemblyId' AND a->>'rootId'<>a->>'assemblyId') THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GENERATOR'; END IF;
  IF a ? 'nodeIds' AND (jsonb_typeof(a->'nodeIds')<>'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(a->'nodeIds') member WHERE NOT index_nodes ? member)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GENERATOR_MEMBER'; END IF;
 END LOOP;
 IF jsonb_array_length(coalesce(p_doc->'presets','[]'))>100 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PRESET_LIMIT'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF coalesce(a->>'title','')='' OR jsonb_typeof(a->'document') IS DISTINCT FROM 'object' OR jsonb_array_length(coalesce(a#>'{document,nodes}','[]'))>2000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET'; END IF;
  PERFORM public.validate_blueprint_layout_internal(a->'document');
 END LOOP;
 -- Ready font outlines must cover actual label/text characters after reopening.
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  referenced:=coalesce(n->>'fontId',p_doc#>>'{defaultTextStyle,fontId}');
  SELECT layout_outline INTO font FROM public.ticket_font_assets WHERE id=referenced;
  IF font IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_RESOURCE_NOT_READY'; END IF;
  FOR ch IN SELECT regexp_split_to_table(coalesce(n->>'text',n->>'label',''),'') LOOP
   IF ch NOT IN ('',E'\n',E'\r') AND NOT (font->'glyphs' ? ch) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_GLYPH_NOT_READY',DETAIL=jsonb_build_object('nodeId',n->>'id')::text; END IF;
  END LOOP;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=p_doc#>>'{defaultTextStyle,fontId}' AND layout_outline IS NOT NULL) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_RESOURCE_NOT_READY'; END IF;
END $$;



-- Source: database/functions/blueprint/save.sql
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean;
 pool public.inventory_pools; capacity_int bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint;
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF (coalesce(public.get_is_editor_on_occasion((p_blueprint->>'occasion')::bigint),false) OR coalesce(public.get_is_manager_on_occasion((p_blueprint->>'occasion')::bigint),false)) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF (coalesce(public.get_is_editor_on_occasion(b.occasion),false) OR coalesce(public.get_is_manager_on_occasion(b.occasion),false)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 PERFORM public.check_occasion_writable(b.occasion);
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}'),count(*) FILTER(WHERE x->>'kind'='seat') INTO node_index,seat_count FROM jsonb_array_elements(doc->'nodes') x;
 -- Membership is projected from the document, never trusted from an overlay.
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u WHERE
   (u->>'id')::uuid IS NULL OR jsonb_array_length(u->'nodeIds')=0 OR coalesce(u->>'kind','atomic')<>'atomic')
  OR EXISTS(SELECT member FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member GROUP BY member HAVING count(*)>1)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member
   WHERE coalesce(node_index->member->>'kind','')<>'seat') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SELECTION_UNITS'; END IF;
 SELECT coalesce(jsonb_object_agg(member,u->>'id'),'{}') INTO unit_index
 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member;
 -- Keep the existing financial resource lock ordering, before spot row locks.
 PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=b.id ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
   DELETE FROM eshop.spots WHERE id=s.id;
   CONTINUE;
  END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'seat' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SEAT_CHANGE',DETAIL=c::text; END IF;
  IF NOT c ? 'productId' OR NOT c ? 'blocked' OR NOT c ? 'groupNodeId' OR NOT c ? 'selectionUnitId' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SEAT_CHANGE',DETAIL=c::text; END IF;
  product_id:=(c->>'productId')::bigint; group_id:=(c->>'groupNodeId')::uuid; unit_id:=(c->>'selectionUnitId')::uuid; blocked_value:=(c->>'blocked')::boolean;
  IF blocked_value IS NULL OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_PRODUCT',DETAIL=c::text; END IF;
  IF group_id IS NOT NULL AND coalesce(node_index->group_id::text->>'kind','') NOT IN ('group','table','furniture') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP',DETAIL=c::text; END IF;
  IF unit_id IS DISTINCT FROM (unit_index->>node::text)::uuid THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_UNIT_MEMBERSHIP_MISMATCH',DETAIL=c::text; END IF;
  spot_id:=(c->>'spotId')::bigint;
  IF binding.node_id IS NOT NULL AND spot_id IS DISTINCT FROM binding.spot THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_IDENTITY_CHANGED',DETAIL=c::text; END IF;
  IF spot_id IS NOT NULL THEN
   SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=b.id AND occasion=b.occasion;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_SCOPE_MISMATCH',DETAIL=c::text; END IF;
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))
    AND (s.product IS DISTINCT FROM product_id OR s.title IS DISTINCT FROM c->>'title'
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id;
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND coalesce(node_index->sb.node_id::text->>'kind','')<>'seat')
  OR (SELECT count(*) FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id)<>seat_count
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.selection_unit IS DISTINCT FROM
   (unit_index->>sb.node_id::text)::uuid) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_SET_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.group_node IS NOT NULL AND coalesce(node_index->sb.group_node::text->>'kind','') NOT IN ('group','table','furniture')) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'groupProductChanges','[]')) LOOP
  IF NOT c ? 'productId' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_GROUP_CHANGE',DETAIL=c::text; END IF;
  node:=(c->>'groupNodeId')::uuid; product_id:=(c->>'productId')::bigint;
  IF coalesce(node_index->node::text->>'kind','') NOT IN ('table','group','furniture')
   OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP_PRODUCT',DETAIL=c::text; END IF;
  DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
  IF product_id IS NOT NULL THEN INSERT INTO eshop.blueprint_group_products VALUES(b.id,node,product_id); END IF;
 END LOOP;
 DELETE FROM eshop.blueprint_group_products gp WHERE blueprint=b.id AND NOT node_index ? gp.group_node::text;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'areaBindingChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid; product_id:=(c->>'productId')::bigint;
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN CONTINUE; END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'capacityArea'
   OR NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=product_id AND pic.inventory_context=(c->>'inventoryContextId')::bigint AND p.occasion=b.occasion AND ip.occasion=b.occasion) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_AREA_BINDING',DETAIL=c::text; END IF;
  IF c ? 'capacity' THEN
   capacity_int:=(c->>'capacity')::bigint;
   IF capacity_int IS NULL OR capacity_int<0 OR capacity_int>1000000 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
   SELECT ip.* INTO pool FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id WHERE ic.id=(c->>'inventoryContextId')::bigint;
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',to_jsonb(pool)||jsonb_build_object('sellable_capacity',capacity_int)));
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 RETURN result;
END $$;



-- Source: database/functions/eshop/get_blueprint.sql
CREATE OR REPLACE FUNCTION get_blueprint(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT b.objects FROM eshop.blueprints b WHERE b.id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    SELECT coalesce(valid_spots,'[]'::jsonb)||coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- Fetch product data for all spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price, 'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    WHERE p.occasion=(SELECT occasion FROM public.forms WHERE key=form_key)
      AND p.id IN (SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
        UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_public_binding_projection_internal(blueprint_id,my_secret);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,(SELECT id FROM public.forms WHERE key=form_key)));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;


-- Source: database/functions/eshop/get_blueprint_for_edit.sql
CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion link does not exist');
    END IF;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Fetch the first blueprint_id for the occasion
    SELECT id
    INTO blueprint_id
    FROM eshop.blueprints
    WHERE occasion = occasion_id
    ORDER BY id
    LIMIT 1;

    -- Check if a blueprint exists for the occasion
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No blueprint found for this occasion');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT objects FROM eshop.blueprints WHERE id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    SELECT coalesce(valid_spots,'[]'::jsonb)||coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
          WHEN t.state = 'used' THEN 'used'
          WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
          WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
          ELSE 'available'
        END
      )
    )
    INTO spotsData
    FROM eshop.spots s
    LEFT JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    LEFT JOIN eshop.tickets t ON opt.ticket = t.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = occasion_id;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description,
        'product_type', p.product_type,
        'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'order_symbol', o.order_symbol,
        'order_sequence', o.order_sequence,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note')
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_binding_projection_internal(blueprint_id);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,NULL));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

-- Source: database/functions/others/duplicate_occasion.sql
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint, p_locale text)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
  v_demo boolean;
  v_layout_ids jsonb; v_copied_layout jsonb;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  v_demo := public.is_demo_occasion(oc);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.can_copy_occasion_source(oc)
     OR public.is_demo_unit(v_target_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, CASE WHEN v_demo THEN true ELSE is_hidden END,
         CASE WHEN v_demo THEN false ELSE is_open END, CASE WHEN v_demo THEN false ELSE is_promoted END, start_time, end_time,
         '' AS link,
         public.copy_occasion_title_internal(title,p_locale), v_organization, services, v_target_unit, features, NULL, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',new_occ,NULL,true) WHERE id=new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprint_layout_ids (blueprint bigint,old_id uuid,new_id uuid,PRIMARY KEY(blueprint,old_id)) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_pools (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_contexts (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resources (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resource_slots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_scanner_fields (old_id bigint,new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc AND NOT v_demo
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, configuration, objects, groups, background_svg, layout
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    PERFORM public.copy_blueprint_image_resources_internal(oc,new_occ,rec.layout);
    v_layout_ids:='{}';v_copied_layout:=rec.layout;
    IF rec.layout IS NOT NULL THEN
      -- Collect every declared record UUID, including nested preset documents.
      WITH RECURSIVE records(value) AS (
        SELECT rec.layout UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
          SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}'::jsonb END) item
          UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]'::jsonb END) item
        ) child
      )
      INSERT INTO tmp_blueprint_layout_ids(blueprint,old_id,new_id)
      SELECT rec.id,(value->>'id')::uuid,extensions.gen_random_uuid() FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id'
      ON CONFLICT(blueprint,old_id) DO NOTHING;
      SELECT coalesce(jsonb_object_agg(old_id::text,new_id),'{}') INTO v_layout_ids FROM tmp_blueprint_layout_ids WHERE blueprint=rec.id;
      v_copied_layout:=public.remap_blueprint_layout_ids_internal(rec.layout,v_layout_ids);
      PERFORM public.validate_blueprint_layout_internal(v_copied_layout);
      PERFORM public.check_blueprint_image_resource_internal(v_copied_layout,new_occ);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg,layout,layout_revision)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg,v_copied_layout,0)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order", maximum
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order", rec.maximum)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- Inventory configuration is copied, never its allocations or reservations.
  FOR rec IN SELECT * FROM public.inventory_pools WHERE occasion=oc LOOP
    INSERT INTO public.inventory_pools(title,description,type,data,sellable_capacity,occasion)
    VALUES(rec.title,rec.description,rec.type,rec.data,rec.sellable_capacity,new_occ)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_pools VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT c.* FROM public.inventory_contexts c
    JOIN tmp_inventory_pools m ON m.old_id=c.inventory_pool LOOP
    INSERT INTO public.inventory_contexts(inventory_pool,block_date,title,"order",data)
    VALUES((SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      rec.block_date,rec.title,rec."order",rec.data) RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_contexts VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resources r
    JOIN tmp_inventory_pools m ON m.old_id=r.inventory_pool LOOP
    INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
    VALUES(rec.title,rec.description,rec.capacity,rec.booking_rules,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place),new_occ,v_target_unit,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resources VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resource_slots r JOIN tmp_resources m ON m.old_id=r.resource LOOP
    INSERT INTO public.resource_slots(resource,title,data)
    VALUES((SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),rec.title,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resource_slots VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity)
    SELECT p.new_id,c.new_id,x.quantity FROM eshop.product_inventory_contexts x
    JOIN tmp_products p ON p.old_id=x.product
    JOIN tmp_inventory_contexts c ON c.old_id=x.inventory_context;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot))
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- Copied geometry and commercial state share the same new UUID mapping.
  -- Holds/orders are deliberately absent and numeric spots/products remap too.
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked
  FROM eshop.blueprint_seat_bindings sb JOIN tmp_blueprints bp ON bp.old_id=sb.blueprint JOIN tmp_spots sp ON sp.old_id=sb.spot
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=sb.blueprint AND node_map.old_id=sb.node_id
  LEFT JOIN tmp_blueprint_layout_ids unit_map ON unit_map.blueprint=sb.blueprint AND unit_map.old_id=sb.selection_unit
  LEFT JOIN tmp_blueprint_layout_ids group_map ON group_map.blueprint=sb.blueprint AND group_map.old_id=sb.group_node;
  INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product)
  SELECT bp.new_id,node_map.new_id,p.new_id FROM eshop.blueprint_group_products gp
  JOIN tmp_blueprints bp ON bp.old_id=gp.blueprint JOIN tmp_products p ON p.old_id=gp.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=gp.blueprint AND node_map.old_id=gp.group_node;
  INSERT INTO eshop.blueprint_area_bindings(blueprint,node_id,inventory_context,product)
  SELECT bp.new_id,node_map.new_id,c.new_id,p.new_id FROM eshop.blueprint_area_bindings ab JOIN tmp_blueprints bp ON bp.old_id=ab.blueprint
  JOIN tmp_inventory_contexts c ON c.old_id=ab.inventory_context JOIN tmp_products p ON p.old_id=ab.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=ab.blueprint AND node_map.old_id=ab.node_id;

  -- 6. Update blueprints “objects” JSON column if it contains spot objects.
  --    For each blueprint, if its "objects" JSON array contains an object with "type" = 'spot',
  --    replace its "id" with the corresponding new spot id.
  ------------------------------------------------------------------
  FOR rec IN
    SELECT tb.old_id AS old_bp, tb.new_id AS new_bp, b.objects
    FROM tmp_blueprints tb
    JOIN eshop.blueprints b ON b.id = tb.new_id
  LOOP
    IF rec.objects IS NOT NULL THEN
      UPDATE eshop.blueprints
      SET objects = (
        SELECT jsonb_agg(
          CASE
            WHEN obj->>'type' = 'spot' THEN
              obj || jsonb_build_object(
                'id',
                COALESCE(
                  (SELECT ts.new_id FROM tmp_spots ts WHERE ts.old_id = (obj->>'id')::bigint),
                  (obj->>'id')::int
                )
              )
            ELSE obj
          END
        )
        FROM jsonb_array_elements(rec.objects) AS obj
      )
      WHERE id = rec.new_bp;
    END IF;
  END LOOP;


  ------------------------------------------------------------------
  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_demo THEN NULL WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_demo THEN false WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            NULL,
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',v_new_id,NULL,true) WHERE id=v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  FOR rec IN SELECT * FROM public.form_fields WHERE form IN (SELECT old_id FROM tmp_forms) LOOP
    INSERT INTO public.form_fields(created_at,title,description,data,type,is_required,form,is_hidden,"order",product_type,is_ticket_field)
    VALUES(now(),rec.title,rec.description,rec.data,rec.type,rec.is_required,
      (SELECT new_id FROM tmp_forms WHERE old_id=rec.form),rec.is_hidden,rec."order",
      (SELECT new_id FROM tmp_product_types WHERE old_id=rec.product_type),rec.is_ticket_field) RETURNING id INTO v_new_id;
    INSERT INTO tmp_scanner_fields VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO public.scanner_settings(occasion_id,config)
  SELECT new_occ,jsonb_set(jsonb_set(config,'{products}',jsonb_build_object('mode',config#>>'{products,mode}',
    'ids',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,ids}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb),
    'order',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,order}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb))),
    '{fields}',coalesce((SELECT jsonb_agg(CASE WHEN f->>'source'='builtin' THEN f ELSE
      f||jsonb_build_object('form_id',fm.new_id,'field_id',ff.new_id,'key',(CASE WHEN f->>'source'='ticket_field' THEN 'ticket' ELSE 'order' END)||':'||fm.new_id||':'||ff.new_id) END ORDER BY n)
      FROM jsonb_array_elements(config->'fields') WITH ORDINALITY x(f,n)
      LEFT JOIN tmp_forms fm ON fm.old_id=(f->>'form_id')::bigint LEFT JOIN tmp_scanner_fields ff ON ff.old_id=(f->>'field_id')::bigint
      WHERE f->>'source'='builtin' OR (fm.new_id IS NOT NULL AND ff.new_id IS NOT NULL)),'[]'::jsonb))
  FROM public.scanner_settings WHERE occasion_id=oc;


  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,tmp_blueprint_layout_ids,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;


-- Existing internal callers retain same-unit semantics.








-- All readers now supply their authenticated form/editor/draft scope.
DROP FUNCTION IF EXISTS public.blueprint_layout_resources_internal(jsonb);
NOTIFY pgrst, 'reload schema';
