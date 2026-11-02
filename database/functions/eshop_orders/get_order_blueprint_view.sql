-- Re-evaluate the core and placement under this statement's MVCC snapshot.
CREATE OR REPLACE FUNCTION public.get_order_blueprint_view(p_order bigint,p_occasion bigint,p_blueprint bigint,p_expected_placement_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE core jsonb; b eshop.blueprints;
BEGIN
 core:=public.get_order_admin_detail(p_order,p_occasion);
 IF core->>'code'<>'200' THEN RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 IF p_expected_placement_fingerprint IS DISTINCT FROM core#>>'{data,placementFingerprint}' THEN
  RETURN jsonb_build_object('code',409,'reason','PLACEMENT_CHANGED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(core#>'{data,plans}') p WHERE p->>'id'=p_blueprint::text) THEN
  RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 SELECT * INTO b FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion;
 IF b.id IS NULL OR b.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RETURN jsonb_build_object('code',422,'reason','CURRENT_PLAN_UNAVAILABLE'); END IF;
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
  'id',b.id,'occasion',b.occasion,'title',b.title,'layout_revision',b.layout_revision,'layout',b.layout,
  'placementFingerprint',core#>>'{data,placementFingerprint}',
  'places',(SELECT coalesce(jsonb_agg(p),'[]') FROM jsonb_array_elements(core#>'{data,places}') p WHERE p->>'blueprintId'=b.id::text),
  'resources',public.blueprint_layout_resources_internal(b.layout,b.occasion)
 ));
END $$;
REVOKE ALL ON FUNCTION public.get_order_blueprint_view(bigint,bigint,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_blueprint_view(bigint,bigint,bigint,text) TO authenticated;
