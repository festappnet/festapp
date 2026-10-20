-- Minimal authoring projection. No orders, buyers, QR or hold secrets.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_for_authoring_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF NOT public.can_edit_ticket_layout(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
 SELECT jsonb_build_object('occasion',o.id,'aggregate_version',coalesce(v.version,0),
  'schemaVersion',3,'appearance',coalesce((SELECT jsonb_build_object('layout',f->'layout',
    'background',f->'background','ticket_type',f->'ticket_type') FROM jsonb_array_elements(o.features) f WHERE f->>'code'='ticket'),'{}'),
  'images',coalesce((SELECT jsonb_agg(i.link ORDER BY i.id) FROM public.images i WHERE i.occasion=o.id OR i.unit=o.unit),'[]'))
 INTO result FROM public.occasions o LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text
 WHERE o.id=p_occasion;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_for_authoring_v1(bigint) TO authenticated;
