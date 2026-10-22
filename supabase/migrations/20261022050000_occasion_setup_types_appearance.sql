-- Reader-first shared appearance support; existing events are not rewritten.
BEGIN;
-- Layout validation and merge; authorization is owned by user_permissions/ticket_layout.sql.
CREATE OR REPLACE FUNCTION public.validate_ticket_layout(p_layout jsonb)
RETURNS void LANGUAGE plpgsql STABLE
SET search_path = public, extensions AS $$
DECLARE t jsonb; e jsonb; b jsonb; s jsonb; a jsonb; q jsonb; kind text; k text; ids text[]; bindings text[]; luminance double precision; background_luminance double precision;
BEGIN
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' OR p_layout->'schemaVersion' IS DISTINCT FROM '3'::jsonb OR NOT (p_layout ? 'schemaVersion')
    OR jsonb_typeof(p_layout->'templates') IS DISTINCT FROM 'object' OR p_layout->'templates'='{}'::jsonb OR octet_length(p_layout::text)>32768
  THEN RAISE EXCEPTION 'Invalid ticket layout'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_layout) AS keys(key) WHERE keys.key NOT IN ('schemaVersion','templates')) THEN RAISE EXCEPTION 'Invalid layout metadata'; END IF;
  IF (SELECT count(DISTINCT id) FROM (
    SELECT value->>'fontId' id FROM jsonb_each(p_layout->'templates')
    UNION ALL SELECT elem.value->'style'->>'fontId' FROM jsonb_each(p_layout->'templates') tmpl CROSS JOIN LATERAL jsonb_array_elements(tmpl.value->'elements') elem
  ) fonts WHERE id IS NOT NULL)>12 THEN RAISE EXCEPTION 'Too many ticket fonts'; END IF;
  FOR kind,t IN SELECT * FROM jsonb_each(p_layout->'templates') LOOP
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(t) AS keys(key) WHERE keys.key NOT IN ('canvasGradient','canvasColor','canvasOpacity','backgroundCrop','pageMargin','backgroundTransform','fontId','flow','flowStep','qrAppearance','border','pageFit','page','ticketArea','elements')) THEN RAISE EXCEPTION 'Invalid template metadata'; END IF;
    IF kind NOT IN ('wide','named') OR jsonb_typeof(t->'elements') IS DISTINCT FROM 'array'
      OR jsonb_array_length(t->'elements') NOT BETWEEN 2 AND 32
      OR (t ? 'pageFit' AND t->'pageFit' IS DISTINCT FROM '"ticket"'::jsonb)
      OR (NOT (t ? 'pageFit')
          AND t->'page' IS DISTINCT FROM '{"width":595.28,"height":841.89}'::jsonb
          AND t->'page' IS DISTINCT FROM '{"width":212.5,"height":387.5}'::jsonb)
    THEN RAISE EXCEPTION 'Invalid ticket template'; END IF;
    IF t ? 'canvasOpacity' AND (jsonb_typeof(t->'canvasOpacity') IS DISTINCT FROM 'number'
      OR (t->>'canvasOpacity')::numeric NOT BETWEEN 0 AND 1)
    THEN RAISE EXCEPTION 'Invalid ticket canvas opacity'; END IF;
    IF t ? 'canvasGradient' THEN
      IF jsonb_typeof(t->'canvasGradient') IS DISTINCT FROM 'array' OR jsonb_array_length(t->'canvasGradient')<>2 THEN RAISE EXCEPTION 'Invalid gradient'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_array_elements(t->'canvasGradient') c WHERE jsonb_typeof(c)<>'string' OR c#>>'{}' !~ '^[a-fA-F0-9]{6}$') THEN RAISE EXCEPTION 'Invalid gradient'; END IF;
    END IF;
    IF t ? 'canvasColor' AND (jsonb_typeof(t->'canvasColor') IS DISTINCT FROM 'string'
      OR (t->>'canvasColor' <> 'transparent' AND t->>'canvasColor' !~ '^[a-fA-F0-9]{6}$'))
    THEN RAISE EXCEPTION 'Invalid ticket canvas color'; END IF;
    IF t ? 'pageMargin' THEN
      IF t->>'pageFit' IS DISTINCT FROM 'ticket' OR jsonb_typeof(t->'pageMargin') IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION 'Invalid ticket page margin'; END IF;
      IF (t->>'pageMargin')::numeric NOT BETWEEN 0 AND 72 THEN RAISE EXCEPTION 'Invalid ticket page margin'; END IF;
    END IF;
    IF t->>'pageFit'='ticket' THEN
      IF jsonb_typeof(t->'page'->'width') IS DISTINCT FROM 'number'
        OR jsonb_typeof(t->'page'->'height') IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION 'Invalid ticket page'; END IF;
      IF (t->'page'->>'width')::numeric NOT BETWEEN 60 AND 842
        OR (t->'page'->>'height')::numeric NOT BETWEEN 60 AND 842
        OR t->'ticketArea'->'x' IS DISTINCT FROM COALESCE(t->'pageMargin','0'::jsonb)
        OR t->'ticketArea'->'y' IS DISTINCT FROM COALESCE(t->'pageMargin','0'::jsonb)
        OR abs((t->'ticketArea'->>'width')::numeric+2*COALESCE((t->>'pageMargin')::numeric,0)-(t->'page'->>'width')::numeric)>.001
        OR abs((t->'ticketArea'->>'height')::numeric+2*COALESCE((t->>'pageMargin')::numeric,0)-(t->'page'->>'height')::numeric)>.001
      THEN RAISE EXCEPTION 'Ticket page must match ticket area'; END IF;
    END IF;
    IF t ? 'font' AND COALESCE(t->>'font','') NOT IN ('futura','robotoSlab','roboto','russoOne') THEN RAISE EXCEPTION 'Invalid ticket font'; END IF;
    IF t ? 'border' AND jsonb_typeof(t->'border') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'Invalid ticket border'; END IF;
    IF t ? 'flowStep' AND (jsonb_typeof(t->'flowStep') IS DISTINCT FROM 'number' OR (t->>'flowStep')::numeric NOT BETWEEN 1 AND 842) THEN RAISE EXCEPTION 'Invalid ticket flow spacing'; END IF;
    IF t ? 'flow' THEN
      IF jsonb_typeof(t->'flow') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Invalid ticket flow'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(t->'flow') AS flow_item(value) WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(t->'elements') AS flow_element(value) WHERE flow_element.value->>'id'=flow_item.value AND flow_element.value->>'binding' NOT IN ('qr','logo')))
        OR (SELECT count(*)<>count(DISTINCT flow_item.value) FROM jsonb_array_elements_text(t->'flow') AS flow_item(value))
      THEN RAISE EXCEPTION 'Invalid ticket flow'; END IF;
    END IF;
    IF t ? 'qrAppearance' THEN
      IF jsonb_typeof(t->'qrAppearance') IS DISTINCT FROM 'object'
        OR COALESCE(t->'qrAppearance'->>'background','') !~ '^[a-fA-F0-9]{6}$'
        OR jsonb_typeof(t->'qrAppearance'->'opacity') IS DISTINCT FROM 'number'
        OR jsonb_typeof(t->'qrAppearance'->'margin') IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION 'Invalid QR appearance'; END IF;
      IF (t->'qrAppearance'->>'opacity')::numeric NOT BETWEEN 0 AND 1 OR (t->'qrAppearance'->>'margin')::numeric NOT BETWEEN 0 AND 8 THEN RAISE EXCEPTION 'Invalid QR appearance'; END IF;
    END IF;
    IF t ? 'font' THEN RAISE EXCEPTION 'Legacy font field in schema 2'; END IF;
    IF t ? 'fontId' THEN
      IF jsonb_typeof(t->'fontId')<>'string'
        OR NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=t->>'fontId')
      THEN RAISE EXCEPTION 'Invalid ticket font'; END IF;
    END IF;
    IF t ? 'backgroundCrop' THEN
      b:=t->'backgroundCrop';
      IF jsonb_typeof(b) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid background crop'; END IF;
      FOREACH k IN ARRAY ARRAY['x','y','width','height'] LOOP
        IF jsonb_typeof(b->k) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'Invalid background crop'; END IF;
      END LOOP;
      IF (b->>'x')::numeric<0 OR (b->>'y')::numeric<0
        OR (b->>'width')::numeric<.001 OR (b->>'height')::numeric<.001
        OR (b->>'x')::numeric+(b->>'width')::numeric>1.000001
        OR (b->>'y')::numeric+(b->>'height')::numeric>1.000001
      THEN RAISE EXCEPTION 'Invalid background crop'; END IF;
    END IF;
    IF t ? 'backgroundTransform' THEN
      b:=t->'backgroundTransform';
      IF jsonb_typeof(b) IS DISTINCT FROM 'object'
        OR jsonb_typeof(b->'scale') IS DISTINCT FROM 'number'
        OR jsonb_typeof(b->'x') IS DISTINCT FROM 'number'
        OR jsonb_typeof(b->'y') IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION 'Invalid background transform'; END IF;
      IF (b->>'scale')::numeric NOT BETWEEN .1 AND 10
        OR abs((b->>'x')::numeric)>10 OR abs((b->>'y')::numeric)>10
      THEN RAISE EXCEPTION 'Invalid background transform'; END IF;
    END IF;
    a:=t->'ticketArea'; ids:='{}'; bindings:='{}';
    FOR b IN SELECT a UNION ALL SELECT value->'box' FROM jsonb_array_elements(t->'elements') LOOP
      FOR k IN SELECT unnest(ARRAY['x','y','width','height']) LOOP
        IF jsonb_typeof(b->k) IS DISTINCT FROM 'number' OR (b->>k)::numeric<0 OR (b->>k)::numeric>842
        THEN RAISE EXCEPTION 'Invalid layout box'; END IF;
      END LOOP;
      IF (b->>'width')::numeric<1 OR (b->>'height')::numeric<1 THEN RAISE EXCEPTION 'Empty layout box'; END IF;
    END LOOP;
    IF (a->>'x')::numeric+(a->>'width')::numeric>(t->'page'->>'width')::numeric+.001
      OR (a->>'y')::numeric+(a->>'height')::numeric>(t->'page'->>'height')::numeric+.001
    THEN RAISE EXCEPTION 'Ticket outside page'; END IF;
    FOR e IN SELECT * FROM jsonb_array_elements(t->'elements') LOOP
      b:=e->'box'; s:=e->'style';
      IF s ? 'fontId' THEN
        IF e->>'binding' IN ('qr','logo') OR jsonb_typeof(s->'fontId')<>'string'
          OR NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=s->>'fontId')
        THEN RAISE EXCEPTION 'Invalid ticket font'; END IF;
      END IF;
      IF e->>'binding' IS NULL OR e->>'binding' NOT IN ('qr','ticketSymbol','spotGroup','productType','note','price','occasionTitle','occasionDatePlace','occasionStartTime','occasionPlace','orderName','logo','footer','text')
        OR (e->>'binding' NOT IN ('productType','text') AND e->>'binding'=ANY(bindings)) OR e->>'id'=ANY(ids) OR COALESCE(e->>'id','') !~ '^[a-zA-Z0-9_-]{1,40}$'
        OR jsonb_typeof(e->'visible') IS DISTINCT FROM 'boolean' OR jsonb_typeof(e->'locked') IS DISTINCT FROM 'boolean'
        OR (b->>'x')::numeric+(b->>'width')::numeric>(a->>'width')::numeric+.001
        OR (b->>'y')::numeric+(b->>'height')::numeric>(a->>'height')::numeric+.001
      THEN RAISE EXCEPTION 'Invalid layout element'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_object_keys(e) AS keys(key) WHERE keys.key NOT IN ('id','binding','productTypeId','label','text','box','visible','locked','style')) THEN RAISE EXCEPTION 'Invalid element metadata'; END IF;
      IF e->>'binding'='productType' THEN
        IF jsonb_typeof(e->'productTypeId') IS DISTINCT FROM 'number' OR jsonb_typeof(e->'label') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Invalid product field'; END IF;
        IF (e->>'productTypeId')::numeric NOT BETWEEN 1 AND 9007199254740991 OR trunc((e->>'productTypeId')::numeric)<>(e->>'productTypeId')::numeric
          OR e->>'label'<>btrim(e->>'label',U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') OR length(e->>'label')>120
          OR (SELECT count(*) FROM jsonb_array_elements(t->'elements') x WHERE x->'productTypeId'=e->'productTypeId')<>1
        THEN RAISE EXCEPTION 'Invalid product field'; END IF;
      ELSIF e ? 'productTypeId' OR e ? 'label' THEN RAISE EXCEPTION 'Invalid product metadata'; END IF;
      IF e->>'binding'='text' THEN
        IF jsonb_typeof(e->'text') IS DISTINCT FROM 'string' OR length(e->>'text')>2000 THEN RAISE EXCEPTION 'Invalid free text'; END IF;
      ELSIF e ? 'text' THEN RAISE EXCEPTION 'Unexpected free text'; END IF;
      ids:=array_append(ids,e->>'id'); bindings:=array_append(bindings,e->>'binding');
      IF jsonb_typeof(s->'fontSize') IS DISTINCT FROM 'number' OR jsonb_typeof(s->'minFontSize') IS DISTINCT FROM 'number'
        OR jsonb_typeof(s->'maxLines') IS DISTINCT FROM 'number' OR COALESCE(s->>'color','') !~ '^[a-fA-F0-9]{6}$'
        OR COALESCE(s->>'align','') NOT IN ('left','center','right')
        OR (s ? 'bold' AND jsonb_typeof(s->'bold') IS DISTINCT FROM 'boolean')
        OR (s ? 'italic' AND jsonb_typeof(s->'italic') IS DISTINCT FROM 'boolean')
        OR (s ? 'underline' AND jsonb_typeof(s->'underline') IS DISTINCT FROM 'boolean')
      THEN RAISE EXCEPTION 'Invalid layout style'; END IF;
      IF (s->>'fontSize')::numeric NOT BETWEEN 6 AND 72 OR (s->>'minFontSize')::numeric NOT BETWEEN 6 AND (s->>'fontSize')::numeric
        OR (s->>'maxLines')::numeric NOT BETWEEN 1 AND 12 OR (s->>'maxLines')::numeric<>trunc((s->>'maxLines')::numeric)
      THEN RAISE EXCEPTION 'Invalid text size'; END IF;
      IF e->>'binding' IN ('qr','ticketSymbol') AND e->'visible'<>'true'::jsonb THEN RAISE EXCEPTION 'Required ticket element hidden'; END IF;
      IF e->>'binding'='qr' THEN
        q:=b;
        SELECT sum((CASE WHEN channel<=.04045 THEN channel/12.92 ELSE power((channel+.055)/1.055,2.4) END)*weight)
          INTO luminance FROM (SELECT get_byte(decode(s->>'color','hex'),i)/255.0 AS channel, weight
            FROM (VALUES (0,.2126),(1,.7152),(2,.0722)) AS rgb(i,weight)) AS linear;
        SELECT sum((CASE WHEN channel<=.04045 THEN channel/12.92 ELSE power((channel+.055)/1.055,2.4) END)*weight)
          INTO background_luminance FROM (SELECT get_byte(decode(COALESCE(t->'qrAppearance'->>'background','FFFFFF'),'hex'),i)/255.0 AS channel, weight
            FROM (VALUES (0,.2126),(1,.7152),(2,.0722)) AS rgb(i,weight)) AS linear;
        IF b->'width'<>b->'height' OR (b->>'width')::numeric<60 OR (greatest(luminance,background_luminance)+.05)/(least(luminance,background_luminance)+.05)<4.5 THEN RAISE EXCEPTION 'Invalid QR dimensions or contrast'; END IF;
      END IF;
    END LOOP;
    IF NOT bindings @> ARRAY['qr','ticketSymbol'] THEN RAISE EXCEPTION 'Missing required ticket elements'; END IF;
    FOR e IN SELECT * FROM jsonb_array_elements(t->'elements') LOOP
      b:=e->'box';
      IF e->'visible'='true'::jsonb AND e->>'binding' NOT IN ('qr','logo')
        AND (b->>'x')::numeric<(q->>'x')::numeric+(q->>'width')::numeric
        AND (b->>'x')::numeric+(b->>'width')::numeric>(q->>'x')::numeric
        AND (b->>'y')::numeric<(q->>'y')::numeric+(q->>'height')::numeric
        AND (b->>'y')::numeric+(b->>'height')::numeric>(q->>'y')::numeric
      THEN RAISE EXCEPTION 'Text overlaps QR quiet zone'; END IF;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.merge_ticket_layout_features(p_old jsonb,p_next jsonb,p_change jsonb DEFAULT NULL,p_create boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path = public, extensions AS $$
DECLARE old_layout jsonb; next_layout jsonb; f jsonb; result jsonb:='[]'; found_ticket boolean:=false;
BEGIN
  IF jsonb_typeof(p_next) IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_array_elements(p_next) e WHERE e->>'code'='ticket')>1
  THEN RAISE EXCEPTION 'Invalid features'; END IF;
  SELECT value->'layout' INTO old_layout FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  next_layout:=old_layout;
  IF p_change IS NOT NULL THEN
    IF jsonb_typeof(p_change)<>'object' OR NOT (p_change ? 'expected' AND p_change ? 'next')
      OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_change) k WHERE k NOT IN ('expected','next','appearance')) THEN RAISE EXCEPTION 'Invalid ticket layout change'; END IF;
    IF COALESCE(old_layout,'null') IS DISTINCT FROM p_change->'expected' THEN
      RAISE EXCEPTION 'ticket_layout_conflict' USING ERRCODE='40001';
    END IF;
    -- A client must not downgrade a schema it does not understand.
    IF old_layout IS NOT NULL AND old_layout->'schemaVersion' IS DISTINCT FROM '3'::jsonb THEN RAISE EXCEPTION 'Unsupported ticket layout'; END IF;
    next_layout:=p_change->'next';
    IF next_layout IS NULL OR next_layout='null'::jsonb THEN RAISE EXCEPTION 'Ticket layout reset rejected'; END IF;
    PERFORM public.validate_ticket_layout(next_layout);
  END IF;
  FOR f IN SELECT * FROM jsonb_array_elements(p_next) LOOP
    IF f->>'code'='ticket' THEN
      found_ticket:=true;
      IF p_create AND p_change IS NULL THEN next_layout:=f->'layout'; IF next_layout IS NOT NULL THEN PERFORM public.validate_ticket_layout(next_layout); END IF; END IF;
      f:=f-'layout'; IF next_layout IS NOT NULL THEN f:=f||jsonb_build_object('layout',next_layout); END IF;
    END IF;
    result:=result||jsonb_build_array(f);
  END LOOP;
  IF NOT found_ticket AND next_layout IS NOT NULL THEN result:=result||jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',false,'layout',next_layout)); END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_ticket_layout_references(p_occasion bigint,p_layout jsonb)
RETURNS void LANGUAGE plpgsql STABLE SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.validate_ticket_layout(p_layout);
  IF EXISTS(SELECT 1 FROM jsonb_each(p_layout->'templates') t CROSS JOIN LATERAL jsonb_array_elements(t.value->'elements') e
    WHERE e->>'binding'='productType' AND NOT EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=(e->>'productTypeId')::bigint AND pt.occasion=p_occasion))
  THEN RAISE EXCEPTION 'ticket_product_type_missing'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.validate_ticket_layout_references(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.validate_ticket_layout_references(bigint,jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.ticket_layout_uses_product_type(p_occasion bigint,p_type bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT EXISTS(SELECT 1 FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f
 CROSS JOIN LATERAL jsonb_each(COALESCE(f->'layout'->'templates','{}')) t
 CROSS JOIN LATERAL jsonb_array_elements(t.value->'elements') e
 WHERE o.id=p_occasion AND f->>'code'='ticket' AND e->>'binding'='productType' AND (e->>'productTypeId')::bigint=p_type);
$$;
REVOKE ALL ON FUNCTION public.ticket_layout_uses_product_type(bigint,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ticket_layout_uses_product_type(bigint,bigint) TO service_role;

-- Only appearance fields may be copied from the ticket editor. Owned image metadata
-- is the authority for new backgrounds; no network resource is fetched by SQL.
CREATE OR REPLACE FUNCTION public.merge_ticket_appearance_internal_v1(p_occasion bigint,p_features jsonb,p_appearance jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='[]'; feature jsonb; background text; old_background text;
BEGIN
 IF p_appearance IS NULL THEN RETURN p_features; END IF;
 IF jsonb_typeof(p_appearance) IS DISTINCT FROM 'object'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_appearance) k WHERE k NOT IN ('background','ticket_type'))
  OR (p_appearance ? 'ticket_type' AND p_appearance->>'ticket_type' IS NOT NULL
    AND p_appearance->>'ticket_type' NOT IN ('wide','named')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid ticket appearance'; END IF;
 SELECT f->>'background' INTO old_background FROM jsonb_array_elements(p_features) f WHERE f->>'code'='ticket';
 background:=p_appearance->>'background';
 IF background IS NOT NULL AND background IS DISTINCT FROM old_background AND NOT EXISTS(
  SELECT 1 FROM public.images i JOIN public.occasions o ON o.id=p_occasion
  WHERE i.link=background AND (i.occasion=o.id OR i.unit=o.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='ticket background must belong to this occasion or unit'; END IF;
 FOR feature IN SELECT value FROM jsonb_array_elements(p_features) LOOP
  IF feature->>'code'='ticket' THEN feature:=feature||p_appearance; END IF;
  result:=result||jsonb_build_array(feature);
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Deterministic projection on the existing finalizer's authorized draft.
CREATE OR REPLACE FUNCTION public.normalize_occasion_setup_type_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
DECLARE payload jsonb:=p_data; event_kind text; appearance jsonb; shared_font text;
BEGIN
 event_kind:=payload->>'eventKind';
 IF event_kind IS NOT NULL AND (event_kind NOT IN ('regular','concert','ball') OR coalesce((payload->>'eventKindNeedsConfirmation')::boolean,false)) THEN
  RAISE invalid_parameter_value USING MESSAGE='Confirm event kind'; END IF;
 IF event_kind IS NOT NULL THEN
  payload:=jsonb_set(payload,'{formEnabled}','true');
  IF event_kind<>'ball' THEN payload:=payload || '{"blueprintMode":"none"}'; END IF;
  IF event_kind='regular' THEN payload:=payload-'ticketDraft'; END IF;
  IF event_kind<>'ball' AND jsonb_typeof(payload#>'{formDraft,fields}')='array' THEN
   payload:=jsonb_set(payload,'{formDraft,fields}',coalesce((SELECT jsonb_agg(field) FROM jsonb_array_elements(payload#>'{formDraft,fields}') field WHERE field->>'type' IS DISTINCT FROM 'spot' AND (event_kind<>'regular' OR field->>'type' IS DISTINCT FROM 'ticket')),'[]'::jsonb));
  END IF;
 END IF;
 IF event_kind IS NOT NULL AND (jsonb_typeof(payload->'formDraft') IS DISTINCT FROM 'object' OR jsonb_typeof(payload->'appearance') IS DISTINCT FROM 'object') THEN
  RAISE invalid_parameter_value USING MESSAGE='Active form and appearance required'; END IF;
 IF event_kind IN ('concert','ball') AND jsonb_typeof(payload->'ticketDraft') IS DISTINCT FROM 'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='Active ticket configuration required'; END IF;
 appearance:=payload->'appearance';
 IF appearance IS NOT NULL THEN
  IF jsonb_typeof(appearance)<>'object' OR coalesce(appearance->>'primary','') !~ '^[A-Fa-f0-9]{6}$' OR coalesce(appearance->>'secondary','') !~ '^[A-Fa-f0-9]{6}$'
    OR jsonb_typeof(appearance->'gradient') IS DISTINCT FROM 'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid shared appearance'; END IF;
  shared_font:=CASE appearance->>'fontFamily'
    WHEN 'Roboto' THEN 'builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f'
    WHEN 'Roboto Slab' THEN 'builtin:roboto-slab-static:b93b5ad2eada842f450bff812f180ac517c82916c9d0dda446322e8d275b4f09'
    WHEN 'Russo One' THEN 'builtin:russo-one-unpacked:54b087e1ffbcfe8837d59e8cbda823e5690cbb8101afe23b31f3a6c70b6dad6b' END;
  IF shared_font IS NULL AND coalesce((appearance->>'preserveSource')::boolean,false)=false THEN RAISE invalid_parameter_value USING MESSAGE='Unsupported shared font'; END IF;
  IF coalesce((appearance->>'preserveSource')::boolean,false)=false THEN
   IF replace(payload#>>'{formDraft,data,design,primary_color}','#','') IS DISTINCT FROM appearance->>'primary'
    OR replace(payload#>>'{formDraft,data,design,secondary_color}','#','') IS DISTINCT FROM appearance->>'secondary'
    OR payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily'
    OR payload#>>'{formDraft,data,design,background_mode}' IS DISTINCT FROM (CASE WHEN (appearance->>'gradient')::boolean THEN 'gradient' ELSE 'solid' END)
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared form style mismatch'; END IF;
   IF event_kind IN ('concert','ball') AND (payload#>'{ticketDraft,layout,templates}' IS NULL OR EXISTS(
    SELECT 1 FROM jsonb_each(payload#>'{ticketDraft,layout,templates}') t
    WHERE t.value->>'fontId' IS DISTINCT FROM shared_font OR t.value->>'canvasColor' IS DISTINCT FROM appearance->>'primary'
     OR (CASE WHEN (appearance->>'gradient')::boolean THEN t.value->'canvasGradient' IS DISTINCT FROM jsonb_build_array(appearance->>'primary',appearance->>'secondary') ELSE t.value ? 'canvasGradient' END)))
    THEN RAISE invalid_parameter_value USING MESSAGE='Shared ticket style mismatch'; END IF;
  END IF;
  -- A custom copied layout retains its detailed style until the user chooses
  -- a shared style. New shared styles are materialized by the one draft mapper.
  IF appearance->>'id'<>'custom' AND payload#>>'{formDraft,data,design,font_family}' IS DISTINCT FROM appearance->>'fontFamily' THEN
    RAISE invalid_parameter_value USING MESSAGE='Form appearance mismatch'; END IF;
 END IF;


 IF event_kind IS NOT NULL THEN payload:=jsonb_set(payload,'{formDraft,title}',payload->'title'); END IF;
 RETURN payload;
END $$;
REVOKE ALL ON FUNCTION public.normalize_occasion_setup_type_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- A single private projection serves the selected detail, initialization and
-- compatibility manifest. It never exports orders, occupancy or reservation IDs.
CREATE OR REPLACE FUNCTION public.occasion_setup_source_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',f.id,'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,
      'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
      'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
      'is_open',false,'blueprint',f.blueprint,
      'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'title',ff.title,'description',ff.description,'data',ff.data,'type',ff.type,
        'is_required',ff.is_required,'is_hidden',ff.is_hidden,'order',ff."order",
        'is_ticket_field',ff.is_ticket_field,
        'product_type_data',(SELECT jsonb_build_object('id',pt.id,'title',pt.title,
          'description',pt.description,'type',pt.type,'data',pt.data,
          'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'id',p.id,'title',p.title,'description',p.description,'price',p.price,
            'currency_code',p.currency_code,'maximum',p.maximum,'data',p.data,
            'is_hidden',p.is_hidden,'order',p."order") ORDER BY p."order",p.id)
            FROM eshop.products p WHERE p.product_type=pt.id),'[]'::jsonb))
          FROM eshop.product_types pt WHERE pt.id=ff.product_type)) ORDER BY ff."order",ff.id)
        FROM public.form_fields ff WHERE ff.form=f.id),'[]'::jsonb)) ORDER BY f.id)
      FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
    'blueprints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'blueprintLayoutDraft',CASE WHEN b.layout IS NULL THEN NULL ELSE jsonb_build_object(
        'layout',b.layout,
        'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',sb.node_id,'productId',spot.product,'title',spot.title,'groupNodeId',sb.group_node,'selectionUnitId',sb.selection_unit,'blocked',sb.blocked) ORDER BY sb.node_id)
          FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots spot ON spot.id=sb.spot WHERE sb.blueprint=b.id),'[]'),
        'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',gp.group_node,'productId',gp.product) ORDER BY gp.group_node) FROM eshop.blueprint_group_products gp WHERE gp.blueprint=b.id),'[]'),
        'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',ab.node_id,'productId',ab.product,'inventoryContextId',ab.inventory_context) ORDER BY ab.node_id) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=b.id),'[]')) END,
      'id',b.id,'title',b.title,'unavailableReason',CASE WHEN b.layout IS NULL THEN 'legacy_requires_reviewed_geometry' ELSE NULL END) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description,
      'max_participants',e.max_participants,'is_hidden',e.is_hidden,'is_group_event',e.is_group_event,
      'split_for_men_women',e.split_for_men_women,'type',e.type,'order',e."order",
      'place',(SELECT jsonb_build_object('id',p.id,'title',p.title,'description',p.description,'type',p.type,
        'coordinates',p.coordinates,'is_hidden',p.is_hidden,'order',p."order",'icon',p.icon) FROM public.places p WHERE p.id=e.place),
      'children',coalesce((SELECT jsonb_agg(eg.event_child ORDER BY eg.event_child) FROM public.event_groups eg
        JOIN public.events child ON child.id=eg.event_child AND child.occasion=o.id WHERE eg.event_parent=e.id),'[]'::jsonb),
      'roles',coalesce((SELECT jsonb_agg(jsonb_build_object('id',r.id,'title',r.title) ORDER BY r.id)
        FROM public.event_roles er JOIN public.role_info r ON r.id=er.role WHERE er.event=e.id),'[]'::jsonb),
      'exclusive_groups',coalesce((SELECT jsonb_agg(jsonb_build_object('id',g.id,'title',g.title) ORDER BY g.id)
        FROM public.exclusive_events ee JOIN public.exclusive_groups g ON g.id=ee."group" WHERE ee.event=e.id),'[]'::jsonb)
      ) ORDER BY e."order",e.id)
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) FROM public.occasions o WHERE o.id=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source_list(p_unit bigint,p_source_unit bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.units target JOIN public.units source ON source.organization=target.organization
   WHERE target.id=p_unit AND (p_source_unit IS NULL OR source.id=p_source_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source tenant denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('occasion',jsonb_build_object(
  'id',o.id,'title',o.title,'start_time',o.start_time,'end_time',o.end_time),
  'forms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'title',f.title)) FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
  'blueprints',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title)) FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb)) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.organization=(SELECT organization FROM public.units WHERE id=p_unit) AND (p_source_unit IS NULL OR o.unit=p_source_unit) AND public.can_copy_occasion_source(o.id)),'[]');
END $$;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_source(p_unit bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit)
  OR NOT public.can_copy_occasion_source(p_occasion)
  OR NOT EXISTS(SELECT 1 FROM public.occasions o JOIN public.units u ON u.organization=o.organization
    WHERE o.id=p_occasion AND u.id=p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN public.occasion_setup_source_internal(p_occasion);
END $$;

-- Compatibility for already deployed opt-in development clients. Remove once
-- all such clients use source_list/source; no separate projection is maintained.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_create_occasion(p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.occasion_setup_source_internal(o.id) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=p_unit),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) TO authenticated;

-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint; configuration_source bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 sale_mode text; sale_start timestamptz; sale_end timestamptz;
 blueprint_mode text; blueprint_id bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := public.normalize_occasion_setup_type_internal(d.data);
 blueprint_mode:=CASE payload->>'blueprintMode'
  WHEN 'Bez plánku' THEN 'none' WHEN 'Nový' THEN 'new' WHEN 'Převzít' THEN 'copy'
  ELSE payload->>'blueprintMode' END;
 IF blueprint_mode IS NULL THEN blueprint_mode:=CASE WHEN jsonb_typeof(payload->'blueprintLayoutDraft')='object' THEN 'copy' ELSE 'none' END; END IF;
 IF payload->>'eventKind'='ball' AND blueprint_mode='none' THEN RAISE invalid_parameter_value USING MESSAGE='Ball requires a hall'; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 -- The form owns its sale window. Absent intent keeps historical drafts closed.
 sale_mode:=coalesce(payload->>'saleMode','preparation');
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF sale_mode NOT IN ('preparation','scheduled','immediate') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
  sale_end:=coalesce(nullif(payload->>'saleEnd','')::timestamptz,(payload->>'end')::timestamptz);
  IF sale_end IS NULL OR sale_end>(payload->>'end')::timestamptz THEN
   RAISE invalid_parameter_value USING MESSAGE='Sale must end no later than the event'; END IF;
  IF sale_mode='scheduled' THEN
   sale_start:=nullif(payload->>'saleStart','')::timestamptz;
   IF sale_start IS NULL OR sale_start<=clock_timestamp() OR sale_start>=sale_end THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid scheduled sale start'; END IF;
  ELSIF sale_mode='immediate' THEN
   IF sale_end<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='Sale has already ended'; END IF;
   sale_start:=clock_timestamp();
  END IF;
 END IF;
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
 FOREACH configuration_source IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF configuration_source IS NOT NULL AND (NOT public.can_copy_occasion_source(configuration_source) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=configuration_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
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
 -- Selection is sufficient; current permissions, currencies and account
 -- fingerprint are still verified under locks before materialization.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed') THEN
  IF nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account selection required'; END IF;
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
   RAISE serialization_failure USING MESSAGE='Bank account details changed; select again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce(payload->>'eventKind','concert')<>'regular' AND coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF blueprint_mode<>'none' AND (
  NOT coalesce((payload->>'formEnabled')::boolean,true) OR
  NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='seat' AND binding->>'productId' IS NOT NULL AND NOT coalesce((binding->>'blocked')::boolean,false)
   UNION ALL
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='capacityArea' AND binding->>'productId' IS NOT NULL
    AND (binding->>'inventoryContextId' IS NOT NULL OR coalesce((binding->>'capacity')::numeric,0)>0)
  )) THEN RAISE invalid_parameter_value USING MESSAGE='Selected blueprint requires a form and sellable places'; END IF;
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
   'setup_listing_intent',coalesce((payload->>'listPubliclyOnPublish')::boolean,true),
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
  -- Explicit values also clear dates inherited from a source/default form.
  form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
    -'start_time'-'end_time'-'enable_countdown';
  form_meta:=jsonb_set(form_meta,'{schedule}',coalesce(nullif(form_meta->'schedule','null'::jsonb),'{}'::jsonb)
   ||jsonb_build_object('start_time',sale_start,'end_time',sale_end,
     'enable_countdown',coalesce((payload->>'saleCountdown')::boolean,false),
     'sale_preparation',sale_mode='preparation'));
  form_data:=jsonb_set(form_data,'{data}',form_meta);
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
  -- Active plan owns the public seat selector. Catalog products remain available without it.
  form_data:=jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb)||
   CASE WHEN blueprint_mode<>'none' THEN jsonb_build_array('{"order":-1}'::jsonb ||
     coalesce((SELECT f FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f WHERE f->>'type'='spot' LIMIT 1),'{}'::jsonb) ||
     '{"type":"spot","is_ticket_field":true,"is_hidden":false,"is_required":true}'::jsonb) ELSE '[]'::jsonb END);
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
   'is_open',sale_mode<>'preparation','bank_account',selected_bank,'form_fields',fields));
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
  IF blueprint_mode<>'none' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
     WHERE binding->>'productId' IS NULL OR product_map->>(binding->>'productId') IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
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
  PERFORM public.materialize_occasion_setup_program_internal(coalesce(payload->'sourceProgram','[]'),new_id,d.unit);
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
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id),
   'formLink',(SELECT link FROM public.forms WHERE id=form_id),'saleMode',sale_mode));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
