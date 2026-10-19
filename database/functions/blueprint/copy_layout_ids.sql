-- Called only by the existing occasion-copy owner. Rewrite declared identity
-- fields and actual geometry references, never arbitrary string content.
CREATE OR REPLACE FUNCTION public.remap_blueprint_layout_ids_internal(p_value jsonb,p_ids jsonb,p_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_value)='object' THEN
  SELECT coalesce(jsonb_object_agg(item.key,public.remap_blueprint_layout_ids_internal(item.value,p_ids,item.key)),'{}') INTO result FROM jsonb_each(p_value) item;
  RETURN result;
 ELSIF jsonb_typeof(p_value)='array' THEN
  SELECT coalesce(jsonb_agg(public.remap_blueprint_layout_ids_internal(item.value,p_ids,p_key) ORDER BY item.position),'[]') INTO result FROM jsonb_array_elements(p_value) WITH ORDINALITY item(value,position);
  RETURN result;
 ELSIF jsonb_typeof(p_value)='string' AND p_key IN ('id','parentId','rootId','assemblyId','seatId','targetId','nodeIds') THEN
  RETURN coalesce(p_ids->(p_value#>>'{}'),p_value);
 END IF;
 RETURN p_value;
END $$;
REVOKE ALL ON FUNCTION public.remap_blueprint_layout_ids_internal(jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
