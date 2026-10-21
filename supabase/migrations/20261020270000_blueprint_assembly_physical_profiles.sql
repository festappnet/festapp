-- Typed assembly roots retain their physical seating profiles across document contexts.
-- Canonical source: database/functions/blueprint/canonical_validation.sql
-- Canonical declaration validation consumes the generated core metadata.
CREATE OR REPLACE FUNCTION public.blueprint_validate_leaves_internal(p_value jsonb,p_rules jsonb)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE entry record; rule jsonb; value jsonb;
BEGIN
 IF jsonb_typeof(p_value) IS DISTINCT FROM 'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_value) LOOP
  rule:=p_rules->entry.key;value:=entry.value;
  IF rule IS NULL OR value='null'::jsonb THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
  IF rule ? 'enum' AND NOT(rule->'enum' @> jsonb_build_array(value)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
  IF rule ? 'type' AND jsonb_typeof(value) IS DISTINCT FROM (CASE WHEN rule->>'type'='integer' THEN 'number' ELSE rule->>'type' END) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
  IF rule->>'type' IN ('number','integer') THEN
   IF rule->>'type'='integer' AND value::numeric<>trunc(value::numeric) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
   IF (rule ? 'minimum' AND value::numeric<(rule->>'minimum')::numeric) OR (rule ? 'maximum' AND value::numeric>(rule->>'maximum')::numeric) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
  ELSIF rule->>'type'='string' THEN
   IF (rule ? 'minLength' AND length(value#>>'{}')<(rule->>'minLength')::int) OR (rule ? 'pattern' AND (value#>>'{}') !~ (rule->>'pattern')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_DECLARATION',DETAIL=entry.key;END IF;
   IF entry.key='fontFamilyId' AND NOT EXISTS(SELECT 1 FROM public.ticket_font_families WHERE id=value#>>'{}') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_FONT_FAMILY_UNAVAILABLE';END IF;
  END IF;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_validate_leaves_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_validate_style_internal(p_style jsonb,p_kind text)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE meta jsonb:=public.blueprint_contract_metadata_internal(); pattern jsonb; value jsonb;
BEGIN
 IF jsonb_typeof(p_style) IS DISTINCT FROM 'object' OR (p_kind='group' AND p_style<>'{}') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STYLE';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_style) key WHERE NOT(meta->'styleSchemas'->p_kind->'properties' ? key)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_UNKNOWN_STYLE';END IF;
 PERFORM public.blueprint_validate_leaves_internal(p_style-ARRAY['label','strokePattern'],meta->'visual');
 IF p_style ? 'label' THEN PERFORM public.blueprint_validate_leaves_internal(p_style->'label',meta->'label');END IF;
 IF p_style ? 'strokePattern' THEN
  pattern:=p_style->'strokePattern';
  IF jsonb_typeof(pattern) IS DISTINCT FROM 'object' OR coalesce(pattern->>'type','') NOT IN ('solid','dashed','dotted','custom') OR EXISTS(SELECT 1 FROM jsonb_object_keys(pattern) key WHERE key<>'type' AND (pattern->>'type'<>'custom' OR key<>'lengths')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STROKE_PATTERN';END IF;
  IF pattern->>'type'='custom' THEN
   IF jsonb_typeof(pattern->'lengths') IS DISTINCT FROM 'array' OR jsonb_array_length(pattern->'lengths') NOT BETWEEN 1 AND 32 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STROKE_PATTERN';END IF;
   FOR value IN SELECT * FROM jsonb_array_elements(pattern->'lengths') LOOP
    IF jsonb_typeof(value)<>'number' OR value::numeric<=0 OR value::numeric>1000000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_STROKE_PATTERN';END IF;
   END LOOP;
  END IF;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_validate_style_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_grid_contains_internal(p_ring jsonb,p_x numeric,p_y numeric)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE a jsonb;b jsonb; crossings int:=0;i int;size int:=jsonb_array_length(p_ring);
BEGIN
 FOR i IN 0..size-1 LOOP
  a:=p_ring->i;b:=p_ring->((i+1)%size);
  IF p_x BETWEEN least((a->>0)::numeric,(b->>0)::numeric) AND greatest((a->>0)::numeric,(b->>0)::numeric)
   AND p_y BETWEEN least((a->>1)::numeric,(b->>1)::numeric) AND greatest((a->>1)::numeric,(b->>1)::numeric) THEN RETURN false;END IF;
  IF ((a->>1)::numeric>p_y)<>((b->>1)::numeric>p_y) AND p_x<(a->>0)::numeric THEN crossings:=crossings+1;END IF;
 END LOOP;
 RETURN crossings%2=1;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_grid_contains_internal(jsonb,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_grid_cell_filled_internal(p_surface jsonb,p_x numeric,p_y numeric)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_surface->>'type'='grid'
  AND public.blueprint_grid_contains_internal(p_surface->'outer',p_x+0.5,p_y+0.5)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_surface->'holes') hole WHERE public.blueprint_grid_contains_internal(hole,p_x+0.5,p_y+0.5)),false)
$$;
REVOKE ALL ON FUNCTION public.blueprint_grid_cell_filled_internal(jsonb,numeric,numeric) FROM PUBLIC,anon,authenticated,service_role;

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

CREATE OR REPLACE FUNCTION public.blueprint_validate_path_internal(p_path jsonb)
RETURNS int LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE command jsonb;arity int; coordinate jsonb;
BEGIN
 IF jsonb_typeof(p_path) IS DISTINCT FROM 'array' OR jsonb_array_length(p_path)>200000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PATH';END IF;
 FOR command IN SELECT * FROM jsonb_array_elements(p_path) LOOP
  IF jsonb_typeof(command)<>'array' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PATH';END IF;
  arity:=(public.blueprint_contract_metadata_internal()->'pathArities'->>(command->>0))::int;
  IF arity IS NULL OR jsonb_array_length(command)<>arity+1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PATH';END IF;
  FOR coordinate IN SELECT value FROM jsonb_array_elements(command) WITH ORDINALITY WHERE ordinality>1 LOOP
   IF jsonb_typeof(coordinate)<>'number' OR abs(coordinate::numeric)>1000000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PATH';END IF;
  END LOOP;
 END LOOP;
 RETURN jsonb_array_length(p_path);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_validate_path_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_validate_gradient_internal(p_gradient jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE key text; v jsonb; prev numeric:=-1; expected int;
BEGIN
 IF jsonb_typeof(p_gradient) IS DISTINCT FROM 'object' OR coalesce(p_gradient->>'type','') NOT IN ('linear','radial') OR coalesce(p_gradient->>'spread','') NOT IN ('pad','repeat','reflect') OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_gradient) k WHERE k NOT IN ('type','colors','stops','spread') AND (p_gradient->>'type'='linear' AND k NOT IN ('from','to') OR p_gradient->>'type'='radial' AND k NOT IN ('center','radius','focal','matrix'))) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;
 IF jsonb_typeof(p_gradient->'colors') IS DISTINCT FROM 'array' OR jsonb_typeof(p_gradient->'stops') IS DISTINCT FROM 'array' OR jsonb_array_length(p_gradient->'colors') NOT BETWEEN 2 AND 1024 OR jsonb_array_length(p_gradient->'colors')<>jsonb_array_length(p_gradient->'stops') OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_gradient->'colors') c WHERE c !~ '^#[0-9a-fA-F]{8}$') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;
 FOR v IN SELECT * FROM jsonb_array_elements(p_gradient->'stops') LOOP
  IF jsonb_typeof(v)<>'number' OR v::numeric<prev OR v::numeric NOT BETWEEN 0 AND 1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;prev:=v::numeric;
 END LOOP;
 FOREACH key IN ARRAY CASE WHEN p_gradient->>'type'='linear' THEN ARRAY['from','to'] ELSE ARRAY['center','matrix','focal'] END LOOP
  IF key='focal' AND (NOT p_gradient ? key OR p_gradient->key='null') THEN CONTINUE;END IF;
  expected:=CASE WHEN key='matrix' THEN 6 ELSE 2 END;
  IF jsonb_typeof(p_gradient->key) IS DISTINCT FROM 'array' OR jsonb_array_length(p_gradient->key)<>expected THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;
  FOR v IN SELECT * FROM jsonb_array_elements(p_gradient->key) LOOP IF jsonb_typeof(v)<>'number' OR abs(v::numeric)>1000000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;END LOOP;
 END LOOP;
 IF p_gradient->>'type'='radial' AND (jsonb_typeof(p_gradient->'radius') IS DISTINCT FROM 'number' OR (p_gradient->>'radius')::numeric<=0 OR (p_gradient->>'radius')::numeric>1000000000) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_GRADIENT';END IF;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_validate_gradient_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_validate_vector_internal(p_graphic jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE command jsonb;depth int:=0;segments int:=0;key text; value jsonb;allowed text[];
BEGIN
 IF jsonb_typeof(p_graphic) IS DISTINCT FROM 'object' OR p_graphic->>'type' IS DISTINCT FROM 'vector' OR p_graphic->>'version' IS DISTINCT FROM '1' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_graphic) k WHERE k NOT IN ('type','version','width','height','commands')) OR jsonb_typeof(p_graphic->'commands') IS DISTINCT FROM 'array' OR jsonb_array_length(p_graphic->'commands')>10000 OR octet_length(p_graphic::text)>8388608 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR';END IF;
 FOREACH key IN ARRAY ARRAY['width','height'] LOOP value:=p_graphic->key;IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR value::numeric<=0 OR value::numeric>1000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR';END IF;END LOOP;
 FOR command IN SELECT * FROM jsonb_array_elements(p_graphic->'commands') LOOP
  IF jsonb_typeof(command)<>'object' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_COMMAND';END IF;
  allowed:=CASE command->>'op' WHEN 'path' THEN ARRAY['op','path','fillRule','fill','stroke','strokeWidth','strokeCap','strokeJoin','miterLimit','fillGradient','strokeGradient'] WHEN 'clip' THEN ARRAY['op','path','fillRule'] WHEN 'layer' THEN ARRAY['op','opacity'] WHEN 'restore' THEN ARRAY['op'] ELSE NULL END;
  IF allowed IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(command) k WHERE NOT(k=ANY(allowed))) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_COMMAND';END IF;
  IF command->>'op'='restore' THEN depth:=depth-1;
  ELSIF command->>'op'='layer' THEN
   value:=command->'opacity';IF jsonb_typeof(value) IS DISTINCT FROM 'number' OR value::numeric NOT BETWEEN 0 AND 1 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_OPACITY';END IF;depth:=depth+1;
  ELSE
   segments:=segments+public.blueprint_validate_path_internal(command->'path');
   IF coalesce(command->>'fillRule','') NOT IN ('nonzero','evenodd') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_FILL';END IF;
   IF command->>'op'='clip' THEN depth:=depth+1;
   ELSE
    FOREACH key IN ARRAY ARRAY['fill','stroke'] LOOP IF command ? key AND command->key<>'null' AND coalesce(command->>key,'') !~ '^#[0-9a-fA-F]{8}$' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PAINT';END IF;END LOOP;
    IF jsonb_typeof(command->'strokeWidth') IS DISTINCT FROM 'number' OR (command->>'strokeWidth')::numeric NOT BETWEEN 0 AND 1000000000 OR coalesce(command->>'strokeCap','') NOT IN ('butt','round','square') OR coalesce(command->>'strokeJoin','') NOT IN ('miter','round','bevel') OR jsonb_typeof(command->'miterLimit') IS DISTINCT FROM 'number' OR (command->>'miterLimit')::numeric NOT BETWEEN 1 AND 1000000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_VECTOR_PAINT';END IF;
    FOREACH key IN ARRAY ARRAY['fillGradient','strokeGradient'] LOOP IF command ? key AND command->key<>'null' THEN PERFORM public.blueprint_validate_gradient_internal(command->key);END IF;END LOOP;
   END IF;
  END IF;
  IF depth NOT BETWEEN 0 AND 32 OR segments>200000 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_VECTOR_LIMIT';END IF;
 END LOOP;
 IF depth<>0 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_UNBALANCED_VECTOR';END IF;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_validate_vector_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
REVOKE ALL ON FUNCTION public.blueprint_canonical_geometry_projection_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
