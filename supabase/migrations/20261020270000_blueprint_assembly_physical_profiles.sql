-- Typed assembly roots retain their physical seating profiles across document contexts.
-- Canonical source: database/functions/blueprint/canonical_validation.sql
-- Canonical declaration validation consumes the generated core metadata.
























CREATE OR REPLACE FUNCTION public.blueprint_canonical_geometry_projection_internal(p_doc jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE meta jsonb:=public.blueprint_contract_metadata_internal(); entry record; n jsonb; next_node jsonb; nodes jsonb:='[]'; a jsonb; placement jsonb; attachments jsonb:='[]'; index_nodes jsonb; attachment_seats text[]:='{}'; seat_node jsonb; target_node jsonb; presets jsonb:='[]'; field text;value jsonb;graphic jsonb;crop jsonb;
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
  IF n ? 'assembly' THEN
   IF jsonb_typeof(n->'assembly')<>'object' OR coalesce(n#>>'{assembly,kind}','') NOT IN ('rows','bus','compartments','couch') OR EXISTS(SELECT 1 FROM jsonb_object_keys(n->'assembly') k WHERE k<>'kind' AND NOT(meta->'assemblyFields' ? k)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_ASSEMBLY';END IF;
   PERFORM public.blueprint_validate_leaves_internal((n->'assembly')-'kind',meta->'assembly');
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
  next_node:=next_node-ARRAY['style','seating','childStyles','assembly','graphic','originalSource'];
  nodes:=nodes||jsonb_build_array(next_node);
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
  IF target_node->>'kind'='table' THEN attachments:=attachments||jsonb_build_array((a-ARRAY['placement','rotationMode'])||jsonb_build_object('kind','perimeter','t',0.5,'gap',0));END IF;
 END LOOP;
 FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_doc->'presets','[]')) LOOP
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN ('id','title','description','document','version')) OR (a->'document' ? 'presets' AND jsonb_array_length(a#>'{document,presets}')>0) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRESET';END IF;
  presets:=presets||jsonb_build_array(jsonb_set(a,'{document}',public.blueprint_canonical_geometry_projection_internal(a->'document')));
 END LOOP;
 RETURN (p_doc-ARRAY['styles','seatingDefaults','textPolicy'])||jsonb_build_object('schemaVersion',1,'nodes',nodes,'attachments',attachments,'presets',presets,
  'defaultTextStyle',jsonb_build_object('fontId','geometry-validation-only','size',24,'color','#222222FF'));
END $$;
