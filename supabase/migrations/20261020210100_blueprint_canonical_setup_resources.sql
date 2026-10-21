-- Forward correction: canonical validation, assignment intent, declared families,
-- scoped setup text and bitmap objects. Previous applied migrations stay immutable.

-- Canonical source: database/functions/blueprint/canonical_text_dependencies.sql

-- Field definitions and shaping policy come from the core-generated metadata.

REVOKE ALL ON FUNCTION public.blueprint_resolved_label_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_layout_text_requests_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Explicit declarations, including unused kind styles, are catalog metadata.
-- They do not acquire arbitrary text resources or cross a preset projection.
CREATE OR REPLACE FUNCTION public.blueprint_declared_font_families_internal(p_layout jsonb,p_presets boolean DEFAULT false)
RETURNS TABLE(font_family_id text) LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 WITH RECURSIVE documents(doc) AS (
  SELECT p_layout UNION ALL
  SELECT preset->'document' FROM documents CROSS JOIN LATERAL jsonb_array_elements(coalesce(doc->'presets','[]')) preset WHERE p_presets
 ), styles(style) AS (
  SELECT doc->'styles' FROM documents
  UNION ALL SELECT kind_style.value FROM documents CROSS JOIN LATERAL jsonb_each(coalesce(doc#>'{styles,kinds}','{}')) kind_style
  UNION ALL SELECT node->'style' FROM documents CROSS JOIN LATERAL jsonb_array_elements(doc->'nodes') node
  UNION ALL SELECT child_style.value FROM documents CROSS JOIN LATERAL jsonb_array_elements(doc->'nodes') node
   CROSS JOIN LATERAL jsonb_each(coalesce(node->'childStyles','{}')) child_style
 ) SELECT DISTINCT style#>>'{label,fontFamilyId}' FROM styles WHERE style#>>'{label,fontFamilyId}' IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.blueprint_declared_font_families_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE INDEX IF NOT EXISTS blueprint_text_resources_descriptor_idx ON public.blueprint_text_resources USING gin((payload->'descriptor') jsonb_path_ops);
CREATE OR REPLACE FUNCTION public.blueprint_canonical_text_resources_internal(p_layout jsonb,p_occasion bigint,p_setup_draft uuid DEFAULT NULL,p_presets boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH requests AS (SELECT * FROM public.blueprint_layout_text_requests_internal(p_layout,p_presets)),
 prepared AS (SELECT DISTINCT r.resource_id,r.resource_kind,r.payload FROM public.blueprint_text_resources r JOIN requests q
  ON r.scope_key=CASE WHEN p_occasion IS NOT NULL THEN 'occasion:'||p_occasion::text ELSE 'setup:'||p_setup_draft::text END
   AND r.payload->'descriptor' @> q.descriptor AND r.payload->'descriptor'=q.descriptor)
 SELECT jsonb_build_object('protocol',2,
  'fontFamilies',coalesce((SELECT jsonb_object_agg(f.id,f.manifest) FROM public.ticket_font_families f WHERE f.id IN (SELECT font_family_id FROM requests UNION SELECT font_family_id FROM public.blueprint_declared_font_families_internal(p_layout,p_presets))),'{}'),
  'textLayouts',coalesce((SELECT jsonb_object_agg(resource_id,payload) FROM prepared WHERE resource_kind='text'),'{}'),
  'numberSymbols',coalesce((SELECT jsonb_object_agg(payload->>'fontFaceId',payload) FROM prepared WHERE resource_kind='number'),'{}'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_canonical_text_resources_internal(jsonb,bigint,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.check_blueprint_text_resources_internal(jsonb,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_text_resource_ids_internal(jsonb,bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Canonical source: database/functions/blueprint/canonical_validation.sql

-- Canonical declaration validation consumes the generated core metadata.

REVOKE ALL ON FUNCTION public.blueprint_validate_leaves_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_style_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_grid_contains_internal(jsonb,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_canonical_surface_projection_internal(p_node jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE surface jsonb:=p_node->'surface';ring jsonb;a jsonb;b jsonb;projected jsonb:='[]';rings jsonb;points jsonb;module numeric;area numeric; min_x numeric:=1e9;min_y numeric:=1e9;max_x numeric:=0;max_y numeric:=0;vertices int:=0;i int;j int;k int;other jsonb;c jsonb;d jsonb;
BEGIN
 IF jsonb_typeof(surface) IS DISTINCT FROM 'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SURFACE';END IF;
 IF surface->>'type' IN ('rect','circle') THEN
  IF surface-'type'<>'{}' OR (surface->>'type'='circle' AND (abs((p_node->>'width')::numeric-(p_node->>'height')::numeric)>1.0/1024 OR p_node->>'furniture'='bar')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SURFACE';END IF;
  RETURN (p_node-'surface')||jsonb_build_object('shape',surface->'type');
 END IF;
 IF surface->>'type' IS DISTINCT FROM 'grid' OR EXISTS(SELECT 1 FROM jsonb_object_keys(surface) key WHERE key NOT IN ('type','moduleSize','outer','holes')) OR jsonb_typeof(surface->'moduleSize') IS DISTINCT FROM 'number' OR jsonb_typeof(surface->'outer') IS DISTINCT FROM 'array' OR jsonb_typeof(surface->'holes') IS DISTINCT FROM 'array' OR jsonb_array_length(surface->'holes')>128 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID';END IF;
 module:=(surface->>'moduleSize')::numeric;
 IF module<=0 OR module>1000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID';END IF;
 rings:=jsonb_build_array(surface->'outer')||(surface->'holes');
 FOR k IN 0..jsonb_array_length(rings)-1 LOOP
  ring:=rings->k;area:=0;points:='[]';
  IF jsonb_typeof(ring)<>'array' OR jsonb_array_length(ring)<4 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_RING';END IF;
  PERFORM public.validate_blueprint_polygon_internal(ring,true);
  vertices:=vertices+jsonb_array_length(ring);
  FOR i IN 0..jsonb_array_length(ring)-1 LOOP
   a:=ring->i;b:=ring->((i+1)%jsonb_array_length(ring));
   IF (a->>0)::numeric<>trunc((a->>0)::numeric) OR (a->>1)::numeric<>trunc((a->>1)::numeric) OR abs((a->>0)::numeric)>16384 OR abs((a->>1)::numeric)>16384 OR ((a->0=b->0)=(a->1=b->1)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_NON_ORTHOGONAL_GRID';END IF;
   area:=area+(a->>0)::numeric*(b->>1)::numeric-(b->>0)::numeric*(a->>1)::numeric;
   IF k=0 THEN min_x:=least(min_x,(a->>0)::numeric);min_y:=least(min_y,(a->>1)::numeric);max_x:=greatest(max_x,(a->>0)::numeric);max_y:=greatest(max_y,(a->>1)::numeric);END IF;
   points:=points||jsonb_build_array(jsonb_build_array((a->>0)::numeric*module-(p_node->>'width')::numeric/2,(a->>1)::numeric*module-(p_node->>'height')::numeric/2));
  END LOOP;
  IF (k=0 AND area<=0) OR (k>0 AND area>=0) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_GRID_WINDING';END IF;
  IF k>0 AND NOT public.blueprint_grid_contains_internal(rings->0,(ring#>>'{0,0}')::numeric,(ring#>>'{0,1}')::numeric) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_GRID_HOLE_OUTSIDE';END IF;
  FOR j IN 0..k-1 LOOP
   other:=rings->j;
   IF j>0 AND (public.blueprint_grid_contains_internal(other,(ring#>>'{0,0}')::numeric,(ring#>>'{0,1}')::numeric) OR public.blueprint_grid_contains_internal(ring,(other#>>'{0,0}')::numeric,(other#>>'{0,1}')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_GRID_HOLES_OVERLAP';END IF;
   FOR i IN 0..jsonb_array_length(ring)-1 LOOP
    a:=ring->i;b:=ring->((i+1)%jsonb_array_length(ring));
    FOR c,d IN SELECT value,other->((ordinality::int)%jsonb_array_length(other)) FROM jsonb_array_elements(other) WITH ORDINALITY LOOP
     IF greatest(least((a->>0)::numeric,(b->>0)::numeric),least((c->>0)::numeric,(d->>0)::numeric))<=least(greatest((a->>0)::numeric,(b->>0)::numeric),greatest((c->>0)::numeric,(d->>0)::numeric)) AND greatest(least((a->>1)::numeric,(b->>1)::numeric),least((c->>1)::numeric,(d->>1)::numeric))<=least(greatest((a->>1)::numeric,(b->>1)::numeric),greatest((c->>1)::numeric,(d->>1)::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_GRID_RINGS_TOUCH';END IF;
    END LOOP;
   END LOOP;
  END LOOP;
  projected:=projected||jsonb_build_array(points);
 END LOOP;
 IF vertices>512 OR min_x<>0 OR min_y<>0 OR max_x*max_y>16384 OR abs((p_node->>'width')::numeric-max_x*module)>1.0/1024 OR abs((p_node->>'height')::numeric-max_y*module)>1.0/1024 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_GRID_DIMENSIONS';END IF;
 RETURN (p_node-'surface')||jsonb_build_object('shape','polygon','points',projected->0,'holes',projected-0);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_canonical_surface_projection_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_path_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_gradient_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_vector_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_canonical_geometry_projection_internal(p_doc jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE meta jsonb:=public.blueprint_contract_metadata_internal(); entry record; n jsonb; next_node jsonb; nodes jsonb:='[]'; a jsonb; placement jsonb; attachments jsonb:='[]'; presets jsonb:='[]'; field text;value jsonb;graphic jsonb;crop jsonb;
BEGIN
 IF jsonb_typeof(p_doc) IS DISTINCT FROM 'object' OR p_doc->>'schemaVersion' IS DISTINCT FROM '2' OR p_doc->>'symbolSetVersion' IS DISTINCT FROM '1' OR jsonb_typeof(p_doc->'nodes') IS DISTINCT FROM 'array' OR jsonb_typeof(p_doc->'styles') IS DISTINCT FROM 'object' OR jsonb_typeof(p_doc->'textPolicy') IS DISTINCT FROM 'object' OR jsonb_typeof(p_doc->'seatingDefaults') IS DISTINCT FROM 'object' OR octet_length(p_doc::text)>8388608 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc) key WHERE key NOT IN ('schemaVersion','symbolSetVersion','canvas','styles','seatingDefaults','textPolicy','nodes','attachments','selectionUnits','sections','presets','background')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANONICAL_LAYOUT';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc->'styles') key WHERE key NOT IN ('label','kinds')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STYLE_SCOPE';END IF;
 IF p_doc->'styles' ? 'label' THEN PERFORM public.blueprint_validate_leaves_internal(p_doc#>'{styles,label}',meta->'label');END IF;
 IF p_doc->'styles' ? 'kinds' THEN
  IF jsonb_typeof(p_doc#>'{styles,kinds}')<>'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STYLE_SCOPE';END IF;
  FOR entry IN SELECT * FROM jsonb_each(p_doc#>'{styles,kinds}') LOOP
   IF NOT(meta->'styleKinds' ? entry.key) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STYLE_KIND';END IF;
   PERFORM public.blueprint_validate_style_internal(entry.value,entry.key);
  END LOOP;
 END IF;
 PERFORM public.blueprint_validate_leaves_internal(p_doc->'seatingDefaults',meta->'seating');
 PERFORM public.blueprint_validate_leaves_internal(p_doc->'textPolicy',jsonb_build_object('language',meta#>'{label,language}','direction',meta#>'{label,direction}'));
 IF NOT(p_doc->'textPolicy' ?& ARRAY['language','direction']) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MISSING_TEXT_POLICY';END IF;
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  IF jsonb_typeof(n)<>'object' OR (n->>'kind'<>'group' AND NOT(meta->'styleKinds' ? (n->>'kind'))) OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key NOT IN ('id','kind','parentId','transform','width','height','z','locked','label','style','childStyles','seating','surface','assembly','graphic') AND NOT(meta->'nodeGeometryKeys' ? key)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANONICAL_NODE';END IF;
  PERFORM public.blueprint_validate_style_internal(coalesce(n->'style','{}'),n->>'kind');
  IF n->>'kind'='table' THEN
   IF n ? 'shape' OR n ? 'points' OR n ? 'holes' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LEGACY_SURFACE_FORBIDDEN';END IF;
   PERFORM public.blueprint_validate_leaves_internal(coalesce(n->'seating','{}'),meta->'seating');
   IF n ? 'childStyles' THEN
    IF jsonb_typeof(n->'childStyles')<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(n->'childStyles') k WHERE k<>'seat') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CHILD_STYLE';END IF;
    IF n->'childStyles' ? 'seat' THEN PERFORM public.blueprint_validate_style_internal(n#>'{childStyles,seat}','seat');END IF;
   END IF;
   next_node:=public.blueprint_canonical_surface_projection_internal(n);
  ELSE
   IF n ? 'surface' OR n ? 'seating' OR n ? 'childStyles' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TABLE_RECORD_ON_OTHER_KIND';END IF;
   next_node:=n;
  END IF;
  IF n ? 'assembly' THEN
   IF jsonb_typeof(n->'assembly')<>'object' OR coalesce(n#>>'{assembly,kind}','') NOT IN ('rows','bus','compartments','couch') OR EXISTS(SELECT 1 FROM jsonb_object_keys(n->'assembly') k WHERE k<>'kind' AND NOT(meta->'assemblyFields' ? k)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ASSEMBLY';END IF;
   FOR entry IN SELECT * FROM jsonb_each(n->'assembly'-'kind') LOOP
    value:=entry.value;
    IF jsonb_typeof(value)<>'number' OR value::numeric NOT BETWEEN 0 AND 1000000 OR (entry.key NOT IN ('spacing','rowSpacing','arc') AND value::numeric<>trunc(value::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ASSEMBLY_PARAMETER';END IF;
   END LOOP;
  END IF;
  IF n->>'kind'='vector' THEN
   PERFORM public.blueprint_validate_vector_internal(n->'graphic');next_node:=jsonb_set(next_node,'{kind}','"shape"');
  ELSIF n->>'kind'='image' THEN
   graphic:=n->'graphic';crop:=graphic->'crop';
   IF jsonb_typeof(graphic) IS DISTINCT FROM 'object' OR graphic->>'type' IS DISTINCT FROM 'bitmap' OR nullif(graphic->>'assetRef','') IS NULL OR coalesce(graphic->>'hash','') !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_object_keys(graphic) k WHERE k NOT IN ('type','assetRef','hash','crop')) OR jsonb_typeof(crop) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(crop) k WHERE k NOT IN ('x','y','width','height')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP';END IF;
   FOREACH field IN ARRAY ARRAY['x','y','width','height'] LOOP IF jsonb_typeof(crop->field) IS DISTINCT FROM 'number' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP_CROP';END IF;END LOOP;
   IF (crop->>'x')::numeric<0 OR (crop->>'y')::numeric<0 OR (crop->>'width')::numeric<=0 OR (crop->>'height')::numeric<=0 OR (crop->>'x')::numeric+(crop->>'width')::numeric>1 OR (crop->>'y')::numeric+(crop->>'height')::numeric>1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP_CROP';END IF;
   next_node:=jsonb_set(next_node,'{kind}','"shape"');
  ELSIF n ? 'graphic' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_UNEXPECTED_GRAPHIC';END IF;
  next_node:=next_node-ARRAY['style','seating','childStyles','assembly','graphic'];
  nodes:=nodes||jsonb_build_array(next_node);
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) LOOP
  placement:=a->'placement';
  IF jsonb_typeof(a)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN ('id','seatId','targetId','placement','rotationMode')) OR coalesce(a->>'rotationMode','') NOT IN ('auto','manual') OR jsonb_typeof(placement) IS DISTINCT FROM 'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
  IF placement->>'mode' IN ('automatic','free') THEN
   IF placement-'mode'<>'{}' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
  ELSIF placement->>'mode'='sidePinned' THEN
   IF placement ? 'cell' THEN
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(placement) k WHERE k NOT IN ('mode','cell','face')) OR jsonb_typeof(placement->'cell')<>'array' OR jsonb_array_length(placement->'cell')<>2 OR coalesce(placement->>'face','') NOT IN ('top','right','bottom','left') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_PIN';END IF;
    FOR value IN SELECT * FROM jsonb_array_elements(placement->'cell') LOOP IF jsonb_typeof(value)<>'number' OR value::numeric<>trunc(value::numeric) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_PIN';END IF;END LOOP;
   ELSE
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(placement) k WHERE k NOT IN ('mode','side','t')) OR coalesce(placement->>'side','') NOT IN ('top','right','bottom','left','perimeter') OR jsonb_typeof(placement->'t') IS DISTINCT FROM 'number' OR (placement->>'t')::numeric NOT BETWEEN 0 AND 1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SIDE_PIN';END IF;
   END IF;
  ELSE RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
  attachments:=attachments||jsonb_build_array((a-ARRAY['placement','rotationMode'])||jsonb_build_object('kind','perimeter','t',0.5,'gap',0));
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN ('id','title','description','document','version')) OR (a->'document' ? 'presets' AND jsonb_array_length(a#>'{document,presets}')>0) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET';END IF;
  presets:=presets||jsonb_build_array(jsonb_set(a,'{document}',public.blueprint_canonical_geometry_projection_internal(a->'document')));
 END LOOP;
 RETURN (p_doc-ARRAY['styles','seatingDefaults','textPolicy'])||jsonb_build_object('schemaVersion',1,'nodes',nodes,'attachments',attachments,'presets',presets,
  'defaultTextStyle',jsonb_build_object('fontId','geometry-validation-only','size',24,'color','#222222FF'));
END $$;
REVOKE ALL ON FUNCTION public.blueprint_canonical_geometry_projection_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Canonical source: database/functions/blueprint/canonical_resource_projection.sql


REVOKE ALL ON FUNCTION public.blueprint_layout_asset_refs_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_canonical_asset_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.check_blueprint_bitmap_resources_internal(jsonb,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_layout_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


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

-- Canonical source: database/functions/blueprint/save.sql

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
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id OR binding.product_assignment_mode IS DISTINCT FROM assignment_mode) THEN
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
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots bound_spot ON bound_spot.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
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

REVOKE ALL ON FUNCTION public.save_blueprint_layout_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Canonical source: database/functions/others/duplicate_occasion.sql

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
    VALUES (now(), rec.data, rec.title, v_organization, new_occ, now(),v_copied_layout,0,CASE WHEN v_copied_layout->>'schemaVersion'='2' THEN public.blueprint_text_resource_ids_internal(v_copied_layout,new_occ) ELSE '{}'::text[] END)
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

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Canonical source: database/functions/occasion_setup/blueprint_layout.sql

-- Unit-scoped preparation uses the existing ticket preview admission policy.

REVOKE ALL ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_blueprint_resources(p_draft uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; doc jsonb; source_id bigint; resource_occasion bigint; resource_unit bigint; resources jsonb; source_resources jsonb;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 source_id:=(d.data->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 doc:=coalesce(d.data#>'{blueprintLayoutDraft,layout}',jsonb_build_object('nodes','[]'::jsonb,'defaultTextStyle',jsonb_build_object('fontId',
  'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44')));
 IF doc->>'schemaVersion'='2' THEN
  resources:=public.blueprint_canonical_text_resources_internal(doc,NULL,p_draft,true);
  source_resources:=CASE WHEN source_id IS NULL THEN '{}'::jsonb ELSE public.blueprint_canonical_text_resources_internal(doc,source_id,NULL,true) END;
  resources:=resources||jsonb_build_object(
   'fontFamilies',coalesce(source_resources->'fontFamilies','{}')||(resources->'fontFamilies'),
   'textLayouts',coalesce(source_resources->'textLayouts','{}')||(resources->'textLayouts'),
   'numberSymbols',coalesce(source_resources->'numberSymbols','{}')||(resources->'numberSymbols'),
   'assets',public.blueprint_canonical_asset_resources_internal(doc,source_id,NULL)||public.blueprint_canonical_asset_resources_internal(doc,NULL,d.unit));
  RETURN public.bound_document_data_v1(jsonb_build_object('resources',resources));
 END IF;
 IF source_id IS NULL OR EXISTS(SELECT 1 FROM public.blueprint_image_assets WHERE unit=d.unit AND asset_ref=doc#>>'{background,assetRef}' AND state='ready') THEN
  resource_unit:=d.unit;
 ELSE resource_occasion:=source_id; END IF;
 RETURN public.bound_document_data_v1(jsonb_build_object('resources',public.blueprint_layout_resources_internal(doc,resource_occasion,resource_unit)));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_blueprint_resources(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_blueprint_resources(uuid) TO authenticated;

-- Copy shared inventory configuration through its existing command owners.
-- Only empty target inventory is created; source holds/bookings never enter it.

REVOKE ALL ON FUNCTION public.copy_setup_area_inventory_internal(jsonb,jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.materialize_setup_area_inventory_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.materialize_setup_blueprint_layout_internal(p_draft jsonb,p_product_map jsonb,p_source bigint,p_target bigint,p_unit bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE doc jsonb:=p_draft->'layout'; ids jsonb:='{}'; seat jsonb; grp jsonb; area jsonb; product_id bigint; context_id bigint;
 seats jsonb:='[]'; groups jsonb:='[]'; areas jsonb:='[]'; result jsonb; context_map jsonb;
BEGIN
 PERFORM public.check_is_editor_on_occasion(p_target);
 IF p_source IS NOT NULL AND NOT public.can_copy_occasion_source(p_source) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF jsonb_typeof(doc)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_draft) k WHERE k NOT IN('layout','seatBindings','groupProducts','areaBindings')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_INVALID_DRAFT'; END IF;
 IF p_source IS NOT NULL THEN
  WITH RECURSIVE records(value) AS (SELECT doc UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
   SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}' END) item
   UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]' END) item) child)
  SELECT coalesce(jsonb_object_agg(value->>'id',extensions.gen_random_uuid()),'{}') INTO ids FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id';
  doc:=public.remap_blueprint_layout_ids_internal(doc,ids);
 END IF;
 IF doc->>'schemaVersion'='2' THEN
  IF p_source IS NOT NULL THEN PERFORM public.copy_blueprint_text_resources_internal(p_source,NULL,p_target,doc); END IF;
  PERFORM public.check_blueprint_text_resources_internal(doc,p_target);
  PERFORM public.copy_blueprint_canonical_bitmap_resources_internal(p_source,p_unit,p_target,doc);
 END IF;
 -- A new draft may use an authenticated unit-owned processed background.
 IF doc->>'schemaVersion' IS DISTINCT FROM '2' AND doc#>>'{background,assetRef}' LIKE 'image:%' THEN
  IF EXISTS(SELECT 1 FROM public.blueprint_image_assets WHERE unit=p_unit AND asset_ref=doc#>>'{background,assetRef}' AND state='ready') THEN
   PERFORM public.copy_blueprint_unit_image_resources_internal(p_unit,p_target,doc);
  ELSIF p_source IS NOT NULL THEN
   PERFORM public.copy_blueprint_image_resources_internal(p_source,p_target,doc);
  ELSE RAISE check_violation USING MESSAGE='BLUEPRINT_IMAGE_RESOURCE_NOT_READY'; END IF;
 END IF;
 FOR seat IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'seatBindings','[]')) LOOP
  IF seat ? 'spotId' OR EXISTS(SELECT 1 FROM jsonb_object_keys(seat) k WHERE k NOT IN('nodeId','productId','title','groupNodeId','selectionUnitId','blocked','productAssignmentMode')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_BINDING_IDENTITY'; END IF;
  product_id:=(p_product_map->>(seat->>'productId'))::bigint;
  IF seat->>'productId' IS NOT NULL AND product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  seats:=seats||jsonb_build_array(seat||jsonb_build_object('nodeId',coalesce(ids->> (seat->>'nodeId'),seat->>'nodeId'),
   'productAssignmentMode',coalesce(seat->>'productAssignmentMode','override'),'groupNodeId',coalesce(ids->>(seat->>'groupNodeId'),seat->>'groupNodeId'),'selectionUnitId',coalesce(ids->>(seat->>'selectionUnitId'),seat->>'selectionUnitId'),
   'spotId',NULL,'productId',product_id,'operation','upsert'));
 END LOOP;
 FOR grp IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'groupProducts','[]')) LOOP
  product_id:=(p_product_map->>(grp->>'productId'))::bigint;
  IF grp->>'productId' IS NOT NULL AND product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  groups:=groups||jsonb_build_array(jsonb_build_object('groupNodeId',coalesce(ids->>(grp->>'groupNodeId'),grp->>'groupNodeId'),'productId',product_id));
 END LOOP;
 context_map:=public.copy_setup_area_inventory_internal(coalesce(p_draft->'areaBindings','[]'),p_product_map,p_source,p_target);
 FOR area IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'areaBindings','[]')) LOOP
  product_id:=(p_product_map->>(area->>'productId'))::bigint;
  IF product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  IF area->>'inventoryContextId' IS NOT NULL THEN context_id:=(context_map->>(area->>'inventoryContextId'))::bigint;
  ELSE context_id:=public.materialize_setup_area_inventory_internal(area,product_id,p_target); END IF;
  areas:=areas||jsonb_build_array(jsonb_build_object('nodeId',coalesce(ids->>(area->>'nodeId'),area->>'nodeId'),'productId',product_id,'inventoryContextId',context_id,'operation','upsert'));
 END LOOP;
 result:=public.save_blueprint_layout_internal_v1(jsonb_build_object('occasion',p_target,'expected_layout_revision',0,'title','Blueprint','layout',doc,'seatChanges',seats,'groupProductChanges',groups,'areaBindingChanges',areas)||CASE WHEN doc->>'schemaVersion'='2' THEN jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(doc,p_target))) ELSE '{}'::jsonb END);
 RETURN (result->>'blueprint_id')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.materialize_setup_blueprint_layout_internal(jsonb,jsonb,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Canonical source: database/functions/occasion_setup/finalize.sql

-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 blueprint_id bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := d.data;
 communication_new:=payload ? 'communicationTone';
 IF communication_new THEN
  IF coalesce(payload->>'communicationTone','') NOT IN ('inherit','formal','informal')
    OR coalesce(payload->>'replyToMode','') NOT IN ('inherit','custom')
    OR coalesce(payload->>'remindersMode','') NOT IN ('inherit','enabled','disabled') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid communication options'; END IF;
  IF payload->>'replyToMode'='custom' THEN
   reply_email:=btrim(payload->>'replyToEmail');
   IF reply_email IS NULL OR length(reply_email)>254 OR reply_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid reply email'; END IF;
  END IF;
  SELECT coalesce(u.data,'{}'::jsonb) INTO unit_defaults FROM public.units u WHERE u.id=d.unit;
 END IF;
 source_id := (payload->>'sourceId')::bigint;
 intro_image:=nullif(payload->>'introImage','');
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 -- Draft uploads use the existing unit-scoped image writer. Never trust an
 -- arbitrary URL supplied by a client, or adopt another unit's image.
 IF intro_image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=intro_image AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft image access denied'; END IF;
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- New setup clients explicitly confirm receiving instructions. Old drafts
 -- without this field retain the existing canonical automatic routing contract.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND payload ? 'bankAccountConfirmed' THEN
  IF (payload->>'bankAccountConfirmed')::boolean IS DISTINCT FROM true OR nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account confirmation required'; END IF;
  selected_bank:=(payload->>'bankAccountId')::bigint;
  PERFORM 1 FROM eshop.bank_accounts ba JOIN eshop.unit_bank_accounts u ON u.bank_account=ba.id
   WHERE u.unit=d.unit AND ba.id=selected_bank AND ba.type<>'CASH' FOR SHARE OF ba,u;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Bank account access denied'; END IF;
  -- Take a fresh statement snapshot after acquiring locks: a concurrent account
  -- update may have committed while the locking statement was waiting.
  SELECT ba.supported_currencies,public.occasion_setup_bank_fingerprint_internal(ba.id)
   INTO bank_currencies,bank_fingerprint FROM eshop.bank_accounts ba WHERE ba.id=selected_bank;
  IF bank_currencies IS NULL OR NOT required_currencies <@ bank_currencies THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account currency mismatch'; END IF;
  IF bank_fingerprint IS DISTINCT FROM payload->>'bankAccountFingerprint' THEN
   RAISE serialization_failure USING MESSAGE='Bank account details changed; confirm again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) AND payload->>'blueprintMode' IN ('Nový','Převzít')
   AND jsonb_array_length(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]'))+
       jsonb_array_length(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]'))=0 THEN
  RAISE invalid_parameter_value USING MESSAGE='Selected blueprint has no places'; END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  features := features || jsonb_build_array(jsonb_build_object('code','form','is_enabled',true) ||
    CASE WHEN communication_new THEN jsonb_build_object(
      'reminder_is_enabled',coalesce((unit_defaults->>'is_reminder_enabled')::boolean,true),
      'reminder_interval_seconds',coalesce((unit_defaults->>'reminder_interval_seconds')::bigint,86400)) ELSE '{}'::jsonb END);
 END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
 policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],d.unit,d.organization);
 IF source_id IS NOT NULL AND (coalesce((payload->>'copyProgram')::boolean,false) OR coalesce((payload->>'copyInformation')::boolean,false) OR coalesce((payload->>'copyEmails')::boolean,false)) THEN
  PERFORM public.admit_occasion_copy_v1(source_id,d.unit,d.organization,policies->'occasion.copy'); END IF;
 PERFORM public.admit_occasion_creation_v1(auth.uid(),d.unit,d.organization,NULL,policies->'occasion.creation');
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF communication_new THEN
   -- Semantic choices override legacy source metadata. Inherited values stay
   -- absent so reply/tone remain live unit defaults; reminder defaults above
   -- are a creation snapshot and never requeue existing events.
   form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
     -'communication_tone'-'is_reminder_enabled'-'reminder_interval_seconds';
   IF payload->>'communicationTone'<>'inherit' THEN
    form_meta:=form_meta||jsonb_build_object('communication_tone',payload->>'communicationTone'); END IF;
   IF required_currencies IS NOT NULL THEN
    IF payload->>'remindersMode'<>'inherit' THEN
     form_meta:=form_meta||jsonb_build_object('is_reminder_enabled',payload->>'remindersMode'='enabled'); END IF;
    IF nullif(btrim(payload->>'reminderLeadDays'),'') IS NOT NULL THEN
     reminder_days:=replace(payload->>'reminderLeadDays',',','.')::numeric;
     IF reminder_days<0 OR reminder_days::text IN ('NaN','Infinity','-Infinity') THEN
      RAISE invalid_parameter_value USING MESSAGE='Invalid reminder interval'; END IF;
     form_meta:=form_meta||jsonb_build_object('reminder_interval_seconds',round(reminder_days*86400)::bigint);
    END IF;
   END IF;
   form_data:=jsonb_set(form_data,'{data}',form_meta);
  END IF;
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  form_link:=nullif(form_data->>'link','');
  IF source_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.forms source_form WHERE source_form.occasion=source_id AND source_form.link=form_link) THEN
   form_link:=(SELECT link FROM public.forms WHERE id=form_id);
  END IF;
  IF coalesce((payload->>'formLinkAutomatic')::boolean,false) THEN
   FOR j IN 1..20 LOOP
    -- Preserve the preview where still free; re-suggest if another writer won.
    IF form_link IS NULL OR EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=form_link AND form IS DISTINCT FROM form_id) THEN
     form_link:=public.suggest_occasion_setup_form_link(p_id,payload->>'title',NULL)->>'suggestion';
    END IF;
    BEGIN
     form_link:=public.reserve_public_link_internal('form',form_id,form_link,false);
     EXIT;
    EXCEPTION WHEN unique_violation THEN
     IF j=20 THEN RAISE; END IF;
     form_link:=NULL;
    END;
   END LOOP;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',false,'bank_account',selected_bank,'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF coalesce(payload->>'blueprintMode','')<>'Bez plánku' AND
   (payload->>'blueprintMode' IN ('Nový','Převzít') OR
    (payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb)) THEN
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   IF payload#>>'{blueprintLayoutDraft,layout,schemaVersion}'='2' THEN
    PERFORM public.copy_blueprint_text_resources_internal(NULL,d.id,new_id,payload#>'{blueprintLayoutDraft,layout}');
   END IF;
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,source_id,new_id,d.unit);
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features:=features||'[{"code":"blueprint","is_enabled":true}]';
  ELSE
   RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED';
  END IF;
  END IF;
 END IF;
 -- Plans are materialized through the existing price-wave commands, using
 -- newly mapped product IDs. No source IDs or second scheduler escape.
 IF coalesce((payload->>'priceWavesEnabled')::boolean,false) AND coalesce((payload->>'formEnabled')::boolean,true)
   AND EXISTS(SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
     WHERE p.occasion=new_id AND ff.form=form_id AND NOT coalesce(ff.is_hidden,false)
       AND p.price>0 AND NOT coalesce(p.is_hidden,false)) THEN
  FOR wave IN SELECT value FROM jsonb_array_elements(coalesce(payload->'priceWaves','[]')) LOOP
   saved_wave:=public.create_product_price_wave((SELECT link FROM public.occasions WHERE id=new_id),(wave->>'change_time')::timestamptz);
   FOR target IN SELECT value FROM jsonb_array_elements(coalesce(wave->'targets','[]')) LOOP
    wave_product:=(product_map->>(target->>'product'))::bigint;
    IF wave_product IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='Price wave product missing'; END IF;
    PERFORM public.save_product_wave_target((saved_wave->>'id')::bigint,wave_product,(saved_wave->>'revision')::bigint,
      (target->>'price')::numeric,(target->>'is_hidden')::boolean,NULL,NULL);
   END LOOP;
  END LOOP;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF has_tickets AND payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft'||'{"code":"ticket","is_enabled":true}'::jsonb;
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  INSERT INTO public.events(occasion,title,start_time,end_time,description)
  SELECT new_id,e->>'title',(e->>'start_time')::timestamptz,(e->>'end_time')::timestamptz,e->>'description'
  FROM jsonb_array_elements(coalesce(payload->'sourceProgram','[]')) e;
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 PERFORM public.admit_occasion_copy_v1(new_id,d.unit,d.organization,policies->'occasion.copy');
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

-- Canonical image copy functions

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
