ALTER TABLE public.ticket_font_assets ADD COLUMN IF NOT EXISTS layout_outline jsonb;
CREATE OR REPLACE FUNCTION public.register_blueprint_layout_font(p_font_id text,p_outline jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE asset public.ticket_font_assets; merged jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE insufficient_privilege USING MESSAGE='font service required'; END IF;
 SELECT * INTO asset FROM public.ticket_font_assets WHERE id=p_font_id FOR UPDATE;
 IF NOT FOUND OR p_outline->>'id' IS DISTINCT FROM p_font_id OR p_outline->>'hash' IS DISTINCT FROM asset.metadata->>'sha256'
  OR p_outline->>'family' IS DISTINCT FROM asset.metadata->>'family' OR jsonb_typeof(p_outline->'glyphs') IS DISTINCT FROM 'object'
  OR coalesce((p_outline->>'unitsPerEm')::numeric,0)<=0 OR p_outline->>'ascent' IS NULL OR p_outline->>'descent' IS NULL
  OR octet_length(p_outline::text)>8388608 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_outline) k WHERE k NOT IN ('id','hash','family','unitsPerEm','ascent','descent','glyphs')) THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_INVALID_FONT_OUTLINE'; END IF;
 IF asset.layout_outline IS NOT NULL AND asset.layout_outline-'glyphs' IS DISTINCT FROM p_outline-'glyphs' THEN
  RAISE invalid_parameter_value USING MESSAGE='BLUEPRINT_FONT_METRICS_CHANGED'; END IF;
 merged:=jsonb_set(p_outline,'{glyphs}',coalesce(asset.layout_outline->'glyphs','{}')||(p_outline->'glyphs'));
 UPDATE public.ticket_font_assets SET layout_outline=merged WHERE id=p_font_id;
 RETURN merged;
END $$;
REVOKE ALL ON FUNCTION public.register_blueprint_layout_font(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_blueprint_layout_font(text,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('protocol',1,'fonts',coalesce((SELECT jsonb_object_agg(a.id,a.layout_outline)
 FROM public.ticket_font_assets a WHERE a.layout_outline IS NOT NULL AND a.id IN (
  SELECT p_layout#>>'{defaultTextStyle,fontId}' UNION SELECT n->>'fontId' FROM jsonb_array_elements(coalesce(p_layout->'nodes','[]')) n)),'{}'),
 'assets',coalesce((SELECT jsonb_object_agg(a.asset_ref,jsonb_build_object('hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length))
 FROM public.blueprint_image_assets a WHERE (a.occasion=p_occasion OR a.unit=p_unit) AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit)
 AND a.state='ready' AND a.asset_ref=p_layout#>>'{background,assetRef}' AND a.hash=p_layout#>>'{background,hash}'),'{}'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated;
