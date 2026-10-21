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
-- Schema-1 dependency boundary. Match effectiveNodeProperties: a kind
-- declaration wins over an unmasked node value; explicit overrides win last.
-- Presets have their own document defaults and namespace.
CREATE OR REPLACE FUNCTION public.blueprint_layout_font_dependencies_internal(p_layout jsonb)
RETURNS TABLE(font_id text,node_id text,rendered_text text)
LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH RECURSIVE documents(doc) AS (
  SELECT p_layout UNION ALL
  SELECT preset->'document' FROM documents
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'presets','[]')) preset
 ), declarations AS (
  SELECT doc#>>'{defaultTextStyle,fontId}' AS font_id FROM documents
  UNION SELECT style->>'fontId' FROM documents
   CROSS JOIN LATERAL jsonb_each(coalesce(doc->'appearance','{}')) styles(kind,style)
  UNION SELECT node->>'fontId' FROM documents
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node
 )
 SELECT font_id,NULL::text,NULL::text FROM declarations WHERE font_id IS NOT NULL
 UNION ALL
 SELECT coalesce(CASE WHEN coalesce(node->'appearanceOverrides','[]') ? 'fontId' THEN node->>'fontId' END,
   doc->'appearance'->(node->>'kind')->>'fontId',node->>'fontId',doc#>>'{defaultTextStyle,fontId}'),
  node->>'id',CASE WHEN node->>'kind'='seat' OR (node->>'kind'='furniture' AND node->>'furniture'='couch')
   OR (node->>'kind'='table' AND node->>'furniture'='bar') THEN ''
   WHEN node->>'kind'='text' THEN coalesce(node->>'text','') ELSE coalesce(node->>'label','') END
 FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node
 UNION ALL
 -- The scene's numeric badge uses the document face, independently of kind
 -- appearance. Prepare symbols once; availability changes must not fetch fonts.
 SELECT doc#>>'{defaultTextStyle,fontId}',node->>'id','×0123456789'
 FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'nodes','[]')) node
 WHERE node->>'kind'='capacityArea' OR (node->>'kind'='furniture' AND node->>'furniture' IS DISTINCT FROM 'couch' AND
  coalesce((SELECT jsonb_array_length(unit->'nodeIds')
   FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) WITH ORDINALITY units(unit,ordinal)
   WHERE jsonb_array_length(unit->'nodeIds')>0 AND NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements_text(unit->'nodeIds') member
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(doc->'nodes') child
     WHERE child->>'id'=member AND child->>'parentId'=node->>'id'))
   ORDER BY ordinal LIMIT 1),0)>1)
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_font_dependencies_internal(jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_legacy_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('protocol',1,'fonts',coalesce((SELECT jsonb_object_agg(a.id,a.layout_outline)
 FROM public.ticket_font_assets a WHERE a.layout_outline IS NOT NULL AND a.id IN (
  SELECT font_id FROM public.blueprint_layout_font_dependencies_internal(p_layout))),'{}'),
 'assets',coalesce((SELECT jsonb_object_agg(a.asset_ref,jsonb_build_object('hash',a.hash,'url',a.url,'width',a.width,'height',a.height,'mimeType',a.mime_type,'byteLength',a.byte_length))
 FROM public.blueprint_image_assets a WHERE (a.occasion=p_occasion OR a.unit=p_unit) AND a.organization=(SELECT organization FROM public.occasions WHERE id=p_occasion UNION ALL SELECT organization FROM public.units WHERE id=p_unit)
 AND a.state='ready' AND a.asset_ref=p_layout#>>'{background,assetRef}' AND a.hash=p_layout#>>'{background,hash}'),'{}'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_layout_resources_legacy_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated;

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
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_layout->>'schemaVersion'='2' THEN
  public.blueprint_canonical_text_resources_internal(p_layout,p_occasion,NULL,true)||jsonb_build_object('assets',public.blueprint_canonical_asset_resources_internal(p_layout,p_occasion,p_unit))
 ELSE public.blueprint_layout_resources_legacy_internal(p_layout,p_occasion,p_unit) END
$$;
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

CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean; assignment_mode text;
 pool public.inventory_pools; capacity_int bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint; text_ids text[]:='{}';
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
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=b.occasion AND ou."user"=auth.uid() AND (ou.is_editor OR ou.is_manager)) THEN RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 ELSE
 IF (coalesce(public.get_is_editor_on_occasion(b.occasion),false) OR coalesce(public.get_is_manager_on_occasion(b.occasion),false)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF b.layout IS NOT NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 ELSE PERFORM public.check_occasion_writable(b.occasion); END IF;
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
 IF doc->>'schemaVersion'='2' THEN
  PERFORM public.check_blueprint_text_resources_internal(doc,b.occasion);
  text_ids:=public.blueprint_text_resource_ids_internal(doc,b.occasion);
  IF jsonb_typeof(p_blueprint->'textResourceIds') IS DISTINCT FROM 'array'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_blueprint->'textResourceIds') id WHERE jsonb_typeof(id)<>'string')
    OR (SELECT coalesce(array_agg(id ORDER BY id),'{}'::text[]) FROM jsonb_array_elements_text(p_blueprint->'textResourceIds') id) IS DISTINCT FROM text_ids
    THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_REFS_MISMATCH'; END IF;
 END IF;
 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 PERFORM public.check_blueprint_bitmap_resources_internal(doc,b.occasion);
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
  assignment_mode:=coalesce(c->>'productAssignmentMode','override');
  IF assignment_mode NOT IN ('inherit','override') OR (doc->>'schemaVersion'='2' AND NOT c ? 'productAssignmentMode') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
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
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id
    AND (product IS DISTINCT FROM product_id OR title IS DISTINCT FROM c->>'title');
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value,assignment_mode)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked,product_assignment_mode=excluded.product_assignment_mode;
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
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots bound_spot ON bound_spot.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL OR bound_spot.product IS DISTINCT FROM gp.product)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
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
 UPDATE eshop.blueprints SET layout=doc,layout_text_resource_ids=text_ids,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_impl_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Runtime entry always enforces occasion writability, including demo read-only.
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_blueprint_layout_impl_internal(p_blueprint,false);
$$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
    form_bundle JSONB;
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

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'layout', jsonb_set(b.layout,'{presets}','[]'), 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(jsonb_set(b.layout,'{presets}','[]'),b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

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

    -- Reuse the form's public catalog projection, including current wave-applied
    -- price, visible offers, product maximum and inventory availability.
    form_bundle:=public.get_form_bundle_internal((SELECT id FROM public.forms WHERE key=form_key),true)::jsonb;
    SELECT coalesce(jsonb_agg(product||jsonb_build_object('isAvailable',
        coalesce((product->>'is_dynamically_available')::boolean,true) AND
        (coalesce((product->>'maximum')::bigint,0)<=0 OR
         coalesce((product->>'ordered_count')::bigint,0)<(product->>'maximum')::bigint))),'[]')
    INTO productsData
    FROM (SELECT DISTINCT ON (offered_product.value->>'id') offered_product.value AS product
      FROM jsonb_array_elements(coalesce(nullif(form_bundle#>'{data,fields}','null'::jsonb),'[]'::jsonb)) field
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(field#>'{product_type_data,products}','null'::jsonb),'[]'::jsonb)) AS offered_product(value)
      WHERE (field->>'type'='ticket' OR ((field->>'is_ticket_field')::boolean AND field->>'type'='product_type'))
        AND (offered_product.value->>'id')::bigint IN (
          SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::bigint)
          UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id)
      ORDER BY offered_product.value->>'id') offered;

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
  v_layout_ids jsonb; v_copied_layout jsonb; v_resource_copy jsonb;
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

  IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=oc AND layout IS NULL) THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';
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
    SELECT id, data, title, organization, layout
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
      IF v_copied_layout->>'schemaVersion'='2' THEN
       PERFORM public.copy_blueprint_text_resources_internal(oc,NULL,new_occ,v_copied_layout);
       PERFORM public.check_blueprint_text_resources_internal(v_copied_layout,new_occ);
      END IF;
      PERFORM public.check_blueprint_image_resource_internal(v_copied_layout,new_occ);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, occasion, updated_at,layout,layout_revision,layout_text_resource_ids)
    VALUES (now(), rec.data, rec.title, v_organization, new_occ, now(),v_copied_layout,0,coalesce(rec.layout_text_resource_ids,'{}'))
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
    v_resource_copy:=public.copy_inventory_resource_configuration_internal(rec.id,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place));
    INSERT INTO tmp_resources VALUES(rec.id,(v_resource_copy->>'resourceId')::bigint);
    INSERT INTO tmp_resource_slots(old_id,new_id)
      SELECT key::bigint,value::text::bigint FROM jsonb_each(v_resource_copy->'slotMap');
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

    v_new_id:=public.copy_empty_inventory_spot_internal(rec.id,new_occ,COALESCE(new_product_id, rec.product),COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot));

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- Copied geometry and commercial state share the same new UUID mapping.
  -- Holds/orders are deliberately absent and numeric spots/products remap too.
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked,sb.product_assignment_mode
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
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint,p_target_unit bigint)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_internal_v1(oc,p_target_unit,'en');
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Temporary staged rollout: only organization 3 is released first.
-- Retire both private legacy readers after the remaining tenants are migrated.
-- The canonical layout readers remain authoritative for every converted row.

CREATE OR REPLACE FUNCTION public.get_blueprint_legacy_rollout_internal(
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
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg
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
        'price', p.price
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.spots s ON s.product = p.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

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

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;

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
    form_bundle JSONB;
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

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL AND organization<>3) THEN
      RETURN public.get_blueprint_legacy_rollout_internal(my_secret,form_key,blueprint_id);
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'layout', jsonb_set(b.layout,'{presets}','[]'), 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(jsonb_set(b.layout,'{presets}','[]'),b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

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

    -- Reuse the form's public catalog projection, including current wave-applied
    -- price, visible offers, product maximum and inventory availability.
    form_bundle:=public.get_form_bundle_internal((SELECT id FROM public.forms WHERE key=form_key),true)::jsonb;
    SELECT coalesce(jsonb_agg(product||jsonb_build_object('isAvailable',
        coalesce((product->>'is_dynamically_available')::boolean,true) AND
        (coalesce((product->>'maximum')::bigint,0)<=0 OR
         coalesce((product->>'ordered_count')::bigint,0)<(product->>'maximum')::bigint))),'[]')
    INTO productsData
    FROM (SELECT DISTINCT ON (offered_product.value->>'id') offered_product.value AS product
      FROM jsonb_array_elements(coalesce(nullif(form_bundle#>'{data,fields}','null'::jsonb),'[]'::jsonb)) field
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(field#>'{product_type_data,products}','null'::jsonb),'[]'::jsonb)) AS offered_product(value)
      WHERE (field->>'type'='ticket' OR ((field->>'is_ticket_field')::boolean AND field->>'type'='product_type'))
        AND (offered_product.value->>'id')::bigint IN (
          SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::bigint)
          UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id)
      ORDER BY offered_product.value->>'id') offered;

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

CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit_legacy_rollout_internal(
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
        'background_svg', b.background_svg
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

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_blueprint_for_edit_legacy_rollout_internal(text) FROM PUBLIC,anon,authenticated,service_role;

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

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL AND organization<>3) THEN
      RETURN public.get_blueprint_for_edit_legacy_rollout_internal(occasion_link);
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

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
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note', 'note_hidden', coalesce(o.note_hidden,o.data->>'note_hidden'))
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