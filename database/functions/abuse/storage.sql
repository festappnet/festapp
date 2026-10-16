-- Canonical image writes belong to the existing R2 control Worker. A released
-- client's Storage copy/upload must not become an unmetered alternate writer.
-- Restrictive policies compose with existing read/delete permissions and do
-- not affect service-owned ticket fonts or other unrelated buckets.
DROP POLICY IF EXISTS image_storage_write_cutover_insert ON storage.objects;
CREATE POLICY image_storage_write_cutover_insert ON storage.objects AS RESTRICTIVE
 FOR INSERT TO anon,authenticated
 WITH CHECK (bucket_id NOT IN ('public-files','images-temp','editor-files'));
DROP POLICY IF EXISTS image_storage_write_cutover_update ON storage.objects;
CREATE POLICY image_storage_write_cutover_update ON storage.objects AS RESTRICTIVE
 FOR UPDATE TO anon,authenticated
 USING (bucket_id NOT IN ('public-files','images-temp','editor-files'))
 WITH CHECK (bucket_id NOT IN ('public-files','images-temp','editor-files'));

-- A historical name is only an exact lookup key, never ownership evidence.
-- Every corresponding canonical image link must pass the existing complete-
-- batch authorization; adding a second owned row cannot steal another owner.
CREATE INDEX IF NOT EXISTS images_link_abuse ON public.images(link);
CREATE OR REPLACE FUNCTION public.can_delete_legacy_image_v1(p_name text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE links text[];
BEGIN
 IF auth.uid() IS NULL OR p_name IS NULL THEN RETURN false; END IF;
 SELECT array_agg(DISTINCT link) INTO links FROM public.images
 WHERE link='https://api.festapp.net/storage/v1/object/public/public-files/'||p_name;
 IF links IS NULL THEN RETURN false; END IF;
 PERFORM 1 FROM public.authorize_image_deletion(links);
 RETURN true;
EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.can_delete_legacy_image_v1(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_delete_legacy_image_v1(text) TO authenticated;
DROP POLICY IF EXISTS "Public Images Policy" ON storage.objects;
DROP POLICY IF EXISTS image_storage_legacy_select ON storage.objects;
CREATE POLICY image_storage_legacy_select ON storage.objects FOR SELECT TO authenticated
 USING (bucket_id='public-files' AND public.can_delete_legacy_image_v1(name));
DROP POLICY IF EXISTS image_storage_legacy_delete ON storage.objects;
CREATE POLICY image_storage_legacy_delete ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='public-files' AND public.can_delete_legacy_image_v1(name));
DROP POLICY IF EXISTS image_storage_listing_owner ON storage.objects;
CREATE POLICY image_storage_listing_owner ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated
 USING (bucket_id<>'public-files' OR public.can_delete_legacy_image_v1(name));
DROP POLICY IF EXISTS image_storage_no_anonymous_listing ON storage.objects;
CREATE POLICY image_storage_no_anonymous_listing ON storage.objects AS RESTRICTIVE FOR SELECT TO anon
 USING (bucket_id<>'public-files');
DROP POLICY IF EXISTS image_storage_delete_owner ON storage.objects;
CREATE POLICY image_storage_delete_owner ON storage.objects AS RESTRICTIVE
 FOR DELETE TO authenticated
 USING (bucket_id<>'public-files' OR public.can_delete_legacy_image_v1(name));

CREATE INDEX IF NOT EXISTS images_occasion_abuse ON public.images(occasion) WHERE occasion IS NOT NULL;
CREATE INDEX IF NOT EXISTS images_unit_abuse ON public.images(unit) WHERE unit IS NOT NULL;
CREATE OR REPLACE FUNCTION public.admit_image_record_v1(p_link text,p_occasion bigint,p_unit bigint) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint; policy jsonb; scopes jsonb; r jsonb; unit_count bigint; org_count bigint;
BEGIN
 IF auth.uid() IS NULL OR (p_occasion IS NULL)=(p_unit IS NULL) OR public.check_upload_permission(p_occasion,p_unit) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='exactly one authorized image owner required'; END IF;
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
REVOKE ALL ON FUNCTION public.admit_image_record_v1(text,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE INSERT,UPDATE ON public.images FROM PUBLIC,anon,authenticated;
