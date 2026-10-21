-- Canonical document 2 is the only runtime input. Historical data uses explicit offline import.

-- Source: database/functions/blueprint/geometry_validation.sql


REVOKE ALL ON FUNCTION public.validate_blueprint_polygon_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated;

-- Storage boundary validation. Numeric limits and authoring keys mirror the
-- public layout protocol; commercial identities never belong in the document.
CREATE OR REPLACE FUNCTION public.validate_blueprint_geometry_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n jsonb; value jsonb; field text; index_nodes jsonb; current_node jsonb; seen text[]; depth int; a jsonb; ids text[]; referenced text; shape text;
 geometry_keys text[];
BEGIN
 SELECT array_agg(value) INTO geometry_keys FROM jsonb_array_elements_text(public.blueprint_contract_metadata_internal()->'nodeGeometryKeys') keys(value);
 IF jsonb_typeof(p_doc) IS DISTINCT FROM 'object' OR p_doc->>'schemaVersion' IS DISTINCT FROM '2' OR p_doc->>'symbolSetVersion' IS DISTINCT FROM '1'
  OR jsonb_typeof(p_doc->'nodes') IS DISTINCT FROM 'array' OR jsonb_typeof(p_doc->'canvas') IS DISTINCT FROM 'object' THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_LAYOUT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_doc) key WHERE key<>ALL(ARRAY['schemaVersion','symbolSetVersion','canvas','styles','textPolicy','seatingDefaults','nodes','sections','selectionUnits','attachments','background','presets'])) THEN
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
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}') INTO index_nodes FROM jsonb_array_elements(p_doc->'nodes') x;
 IF (SELECT count(*) FROM jsonb_array_elements(p_doc->'nodes'))<>(SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(p_doc->'nodes') x) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_NODE'; END IF;
 FOR n IN SELECT * FROM jsonb_array_elements(p_doc->'nodes') LOOP
  IF jsonb_typeof(n) IS DISTINCT FROM 'object' OR coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
   OR coalesce(n->>'kind','') NOT IN ('group','table','seat','furniture','capacityArea','shape','text','vector','image')
   OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key<>ALL(geometry_keys||ARRAY['id','kind','parentId','transform','width','height','z','locked','label','style','childStyles','seating','surface','assembly','graphic','originalSource'])) THEN
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
  IF n ? 'locked' AND jsonb_typeof(n->'locked')<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN';END IF;
  IF n ? 'obstacle' AND jsonb_typeof(n->'obstacle')<>'boolean' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_NODE_BOOLEAN';END IF;
  IF n ? 'capacity' AND (jsonb_typeof(n->'capacity')<>'number' OR (n->>'capacity')::numeric<0 OR (n->>'capacity')::numeric<>trunc((n->>'capacity')::numeric)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
  shape:=n->>'shape';
  IF shape IS NOT NULL AND shape NOT IN ('rect','rectangle','roundedRect','ellipse','oval','circle','round','polygon','polyline','line','arrow') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SHAPE'; END IF;
  IF n->>'symbol' IS NOT NULL AND n->>'symbol' NOT IN ('chair','bench','sofa','wheelchair','driver') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SYMBOL'; END IF;
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
 UNION ALL SELECT item.value FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) item LOOP
  IF coalesce(n->>'id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' OR n->>'id'=ANY(ids) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_OR_INVALID_ID'; END IF;
  ids:=array_append(ids,n->>'id');
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) LOOP
  IF coalesce(index_nodes->(a->>'rootId')->>'kind','')<>'group' OR coalesce(a->>'title','')='' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SECTION'; END IF;
  IF a->'outline' IS NOT NULL AND a->'outline'<>'null'::jsonb THEN PERFORM public.validate_blueprint_polygon_internal(a->'outline',true); END IF;
 END LOOP;
 IF EXISTS(SELECT attachment->>'seatId' FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) attachment GROUP BY attachment->>'seatId' HAVING count(*)>1)
  OR EXISTS(SELECT section->>'rootId' FROM jsonb_array_elements(coalesce(p_doc->'sections','[]')) section GROUP BY section->>'rootId' HAVING count(*)>1) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_DUPLICATE_AUTHORING_REFERENCE'; END IF;
 IF jsonb_array_length(coalesce(p_doc->'presets','[]'))>100 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_PRESET_LIMIT'; END IF;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF coalesce(a->>'title','')='' OR jsonb_typeof(a->'document') IS DISTINCT FROM 'object' OR jsonb_array_length(coalesce(a#>'{document,nodes}','[]'))>2000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET'; END IF;
  PERFORM public.validate_blueprint_geometry_internal(a->'document');
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_geometry_internal(jsonb) FROM PUBLIC,anon,authenticated;



-- Source: database/functions/blueprint/canonical_validation.sql

-- Canonical declaration validation consumes the generated core metadata.

REVOKE ALL ON FUNCTION public.blueprint_validate_leaves_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_style_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_grid_contains_internal(jsonb,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_grid_cell_filled_internal(jsonb,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_canonical_surface_projection_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_path_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_gradient_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_vector_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_validate_assembly_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.validate_blueprint_canonical_declarations_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE meta jsonb:=public.blueprint_contract_metadata_internal(); entry record; n jsonb; next_node jsonb; a jsonb; placement jsonb; index_nodes jsonb; attachment_seats text[]:='{}'; seat_node jsonb; target_node jsonb; field text;value jsonb;graphic jsonb;crop jsonb;
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
  IF jsonb_typeof(n)<>'object' OR (n->>'kind'<>'group' AND NOT(meta->'styleKinds' ? (n->>'kind'))) OR EXISTS(SELECT 1 FROM jsonb_object_keys(n) key WHERE key NOT IN ('id','kind','parentId','transform','width','height','z','locked','label','style','childStyles','seating','surface','assembly','graphic','originalSource') AND NOT(meta->'nodeGeometryKeys' ? key)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_CANONICAL_NODE';END IF;
  IF n ? 'originalSource' THEN
   value:=n->'originalSource';
   IF n->>'kind'<>'vector' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_UNEXPECTED_ORIGINAL_SOURCE';END IF;
   PERFORM public.blueprint_validate_leaves_internal(value,meta->'originalSource');
   IF NOT(value ?& ARRAY['format','text','sha256']) OR octet_length(convert_to(value->>'text','UTF8'))>(meta->>'originalSourceBytesMax')::bigint
    OR encode(extensions.digest(convert_to(value->>'text','UTF8'),'sha256'),'hex') IS DISTINCT FROM value->>'sha256' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ORIGINAL_SOURCE';END IF;
  END IF;
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
   IF n ? 'surface' OR n ? 'childStyles' OR (n ? 'seating' AND NOT(n->>'kind' IN ('group','furniture') AND coalesce(n#>>'{assembly,kind}','') IN ('rows','bus','compartments','couch'))) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TABLE_RECORD_ON_OTHER_KIND';END IF;
   IF n ? 'seating' THEN PERFORM public.blueprint_validate_leaves_internal(n->'seating',meta->'seating');END IF;
   next_node:=n;
  END IF;
  IF n ? 'assembly' THEN PERFORM public.blueprint_validate_assembly_internal(n->'assembly',n->>'kind');END IF;
  IF n->>'kind'='vector' THEN
   PERFORM public.blueprint_validate_vector_internal(n->'graphic');next_node:=jsonb_set(next_node,'{kind}','"shape"');
  ELSIF n->>'kind'='image' THEN
   graphic:=n->'graphic';crop:=graphic->'crop';
   IF jsonb_typeof(graphic) IS DISTINCT FROM 'object' OR graphic->>'type' IS DISTINCT FROM 'bitmap' OR nullif(graphic->>'assetRef','') IS NULL OR coalesce(graphic->>'hash','') !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_object_keys(graphic) k WHERE k NOT IN ('type','assetRef','hash','crop')) OR jsonb_typeof(crop) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(crop) k WHERE k NOT IN ('x','y','width','height')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP';END IF;
   FOREACH field IN ARRAY ARRAY['x','y','width','height'] LOOP IF jsonb_typeof(crop->field) IS DISTINCT FROM 'number' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP_CROP';END IF;END LOOP;
   IF (crop->>'x')::numeric<0 OR (crop->>'y')::numeric<0 OR (crop->>'width')::numeric<=0 OR (crop->>'height')::numeric<=0 OR (crop->>'x')::numeric+(crop->>'width')::numeric>1 OR (crop->>'y')::numeric+(crop->>'height')::numeric>1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_BITMAP_CROP';END IF;
   next_node:=jsonb_set(next_node,'{kind}','"shape"');
  ELSIF n ? 'graphic' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_UNEXPECTED_GRAPHIC';END IF;
 END LOOP;
 SELECT coalesce(jsonb_object_agg(item->>'id',item),'{}') INTO index_nodes FROM jsonb_array_elements(p_doc->'nodes') item;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'attachments','[]')) LOOP
  seat_node:=index_nodes->(a->>'seatId');target_node:=index_nodes->(a->>'targetId');
  IF coalesce(seat_node->>'kind','')<>'seat' OR seat_node->>'parentId' IS DISTINCT FROM a->>'targetId'
   OR NOT(coalesce(target_node->>'kind','')='table' OR (coalesce(target_node->>'kind','') IN ('group','furniture') AND coalesce(target_node#>>'{assembly,kind}','') IN ('rows','bus','compartments','couch')))
   OR a->>'seatId'=ANY(attachment_seats) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ATTACHMENT';END IF;
  attachment_seats:=array_append(attachment_seats,a->>'seatId');
  placement:=a->'placement';
  IF jsonb_typeof(a)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN ('id','seatId','targetId','placement','rotationMode')) OR coalesce(a->>'rotationMode','') NOT IN ('auto','manual') OR jsonb_typeof(placement) IS DISTINCT FROM 'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
  IF placement->>'mode' IN ('automatic','free') THEN
   IF placement-'mode'<>'{}' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
  ELSIF placement->>'mode'='sidePinned' THEN
   IF target_node->>'kind'<>'table' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SIDE_PIN';END IF;
   IF placement ? 'cell' THEN
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(placement) k WHERE k NOT IN ('mode','cell','face')) OR jsonb_typeof(placement->'cell')<>'array' OR jsonb_array_length(placement->'cell')<>2 OR coalesce(placement->>'face','') NOT IN ('top','right','bottom','left') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_PIN';END IF;
    FOR value IN SELECT * FROM jsonb_array_elements(placement->'cell') LOOP IF jsonb_typeof(value)<>'number' OR value::numeric<>trunc(value::numeric) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_PIN';END IF;END LOOP;
    IF target_node#>>'{surface,type}' IS DISTINCT FROM 'grid'
     OR NOT public.blueprint_grid_cell_filled_internal(target_node->'surface',(placement#>>'{cell,0}')::numeric,(placement#>>'{cell,1}')::numeric)
     OR public.blueprint_grid_cell_filled_internal(target_node->'surface',(placement#>>'{cell,0}')::numeric+CASE placement->>'face' WHEN 'right' THEN 1 WHEN 'left' THEN -1 ELSE 0 END,(placement#>>'{cell,1}')::numeric+CASE placement->>'face' WHEN 'bottom' THEN 1 WHEN 'top' THEN -1 ELSE 0 END)
     THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRID_PIN_BOUNDARY';END IF;
   ELSE
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(placement) k WHERE k NOT IN ('mode','side','t')) OR coalesce(placement->>'side','') NOT IN ('top','right','bottom','left','perimeter') OR jsonb_typeof(placement->'t') IS DISTINCT FROM 'number' OR (placement->>'t')::numeric NOT BETWEEN 0 AND 1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SIDE_PIN';END IF;
    IF (placement->>'side'='perimeter' AND target_node#>>'{surface,type}' IS DISTINCT FROM 'circle') OR (placement->>'side'<>'perimeter' AND target_node#>>'{surface,type}' IS DISTINCT FROM 'rect') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_SIDE_PIN_SURFACE';END IF;
   END IF;
  ELSE RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PLACEMENT';END IF;
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN ('id','title','description','document','version')) OR (a->'document' ? 'presets' AND jsonb_array_length(a#>'{document,presets}')>0) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET';END IF;
  PERFORM public.validate_blueprint_canonical_declarations_internal(a->'document');
 END LOOP;
 RETURN;
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_canonical_declarations_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;



-- Source: database/functions/blueprint/validation.sql

-- One canonical document contract; resource readiness is authorized by Save.
CREATE OR REPLACE FUNCTION public.validate_blueprint_layout_internal(p_doc jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.validate_blueprint_canonical_declarations_internal(p_doc);
 PERFORM public.validate_blueprint_geometry_internal(p_doc);
END $$;
REVOKE ALL ON FUNCTION public.validate_blueprint_layout_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;



-- Source: database/functions/blueprint/canonical_resource_projection.sql


REVOKE ALL ON FUNCTION public.blueprint_layout_asset_refs_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.blueprint_canonical_asset_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.check_blueprint_bitmap_resources_internal(jsonb,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_layout_resources_internal(p_layout jsonb,p_occasion bigint,p_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';END IF;
 RETURN public.blueprint_canonical_text_resources_internal(p_layout,p_occasion,NULL,true)||jsonb_build_object('assets',public.blueprint_canonical_asset_resources_internal(p_layout,p_occasion,p_unit));
END $$;
REVOKE ALL ON FUNCTION public.blueprint_layout_resources_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;


REVOKE ALL ON FUNCTION public.copy_blueprint_text_resources_internal(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Internal caller supplies a source occasion and/or the authorized setup unit.
-- Only exact referenced processed manifests are copied into the new aggregate.

REVOKE ALL ON FUNCTION public.copy_blueprint_canonical_bitmap_resources_internal(bigint,bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Viewers receive geometry and prepared paint only. Original imported SVG and
-- private reusable presets stay in the permission-checked authoring projection.

REVOKE ALL ON FUNCTION public.blueprint_public_document_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;



-- Source: database/functions/blueprint/save.sql

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
  PERFORM public.check_blueprint_text_resources_internal(doc,b.occasion);
  text_ids:=public.blueprint_text_resource_ids_internal(doc,b.occasion);
  IF jsonb_typeof(p_blueprint->'textResourceIds') IS DISTINCT FROM 'array'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_blueprint->'textResourceIds') id WHERE jsonb_typeof(id)<>'string')
    OR (SELECT coalesce(array_agg(id ORDER BY id),'{}'::text[]) FROM jsonb_array_elements_text(p_blueprint->'textResourceIds') id) IS DISTINCT FROM text_ids
    THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_REFS_MISMATCH'; END IF;

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
  IF assignment_mode NOT IN ('inherit','override') OR NOT c ? 'productAssignmentMode' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
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



-- Source: database/functions/occasion_setup/blueprint_layout.sql

-- Unit-scoped preparation uses the existing ticket preview admission policy.

REVOKE ALL ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_blueprint_resources(p_draft uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; doc jsonb; source_id bigint; resources jsonb; source_resources jsonb;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 source_id:=(d.data->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 doc:=coalesce(d.data#>'{blueprintLayoutDraft,layout}',jsonb_build_object(
  'schemaVersion',2,'symbolSetVersion',1,'canvas',jsonb_build_object('x',0,'y',0,'width',2400,'height',1600,'fill','#FFFFFFFF'),
  'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,'textPolicy',jsonb_build_object('language','und','direction','auto'),
  'nodes','[]'::jsonb,'sections','[]'::jsonb,'selectionUnits','[]'::jsonb,'attachments','[]'::jsonb,'presets','[]'::jsonb));
 IF doc->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';END IF;
  resources:=public.blueprint_canonical_text_resources_internal(doc,NULL,p_draft,true);
  source_resources:=CASE WHEN source_id IS NULL THEN '{}'::jsonb ELSE public.blueprint_canonical_text_resources_internal(doc,source_id,NULL,true) END;
  resources:=resources||jsonb_build_object(
   'fontFamilies',coalesce(source_resources->'fontFamilies','{}')||(resources->'fontFamilies'),
   'textLayouts',coalesce(source_resources->'textLayouts','{}')||(resources->'textLayouts'),
   'numberSymbols',coalesce(source_resources->'numberSymbols','{}')||(resources->'numberSymbols'),
   'assets',public.blueprint_canonical_asset_resources_internal(doc,source_id,NULL)||public.blueprint_canonical_asset_resources_internal(doc,NULL,d.unit));
  RETURN public.bound_document_data_v1(jsonb_build_object('resources',resources));
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
 PERFORM public.validate_blueprint_layout_internal(doc);
 IF p_source IS NOT NULL THEN PERFORM public.copy_blueprint_text_resources_internal(p_source,NULL,p_target,doc);END IF;
 PERFORM public.check_blueprint_text_resources_internal(doc,p_target);
 PERFORM public.copy_blueprint_canonical_bitmap_resources_internal(p_source,p_unit,p_target,doc);
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
 result:=public.save_blueprint_layout_internal_v1(jsonb_build_object('occasion',p_target,'expected_layout_revision',0,'title','Blueprint','layout',doc,'seatChanges',seats,'groupProductChanges',groups,'areaBindingChanges',areas)||jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(doc,p_target))));
 RETURN (result->>'blueprint_id')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.materialize_setup_blueprint_layout_internal(jsonb,jsonb,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;



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
       PERFORM public.copy_blueprint_text_resources_internal(oc,NULL,new_occ,v_copied_layout);
       PERFORM public.check_blueprint_text_resources_internal(v_copied_layout,new_occ);
      PERFORM public.check_blueprint_image_resource_internal(v_copied_layout,new_occ);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, occasion, updated_at,layout,layout_revision,layout_text_resource_ids)
    VALUES (now(), rec.data, rec.title, v_organization, new_occ, now(),v_copied_layout,0,CASE WHEN v_copied_layout IS NULL THEN '{}'::text[] ELSE public.blueprint_text_resource_ids_internal(v_copied_layout,new_occ) END)
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



DROP FUNCTION IF EXISTS public.blueprint_canonical_geometry_projection_internal(jsonb);
DROP FUNCTION IF EXISTS public.validate_blueprint_geometry_internal(jsonb,boolean);
DROP FUNCTION IF EXISTS public.blueprint_layout_resources_legacy_internal(jsonb,bigint,bigint);
DROP FUNCTION IF EXISTS public.blueprint_layout_font_dependencies_internal(jsonb);
DROP FUNCTION IF EXISTS public.register_blueprint_layout_font(text,jsonb);
-- The former layout_outline cache is retained as private historical data only.
