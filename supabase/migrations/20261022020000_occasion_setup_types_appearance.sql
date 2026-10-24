-- Readers must ship before the wizard writes canvasGradient. No live data rewrite.
BEGIN;
-- Canonical public-link suggestion used by the existing draft link RPC.
CREATE OR REPLACE FUNCTION public.suggest_public_link(p_kind text,p_title text,p_unit bigint)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE candidate text; base text; attempt integer;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Public link suggestion denied'; END IF;
 IF p_kind NOT IN ('form','occasion') OR p_kind IS NULL THEN RAISE invalid_parameter_value; END IF;
 base:=trim(both '_' FROM regexp_replace(public.f_unaccent(left(coalesce(p_title,''),200)),'[^a-z0-9_-]+','_','g'));
 base:=trim(both '-_' FROM left(regexp_replace(base,'[-_]{2,}','_','g'),60));
 IF base='' THEN base:=public.random_public_link_internal(); END IF;
 FOR attempt IN 1..20 LOOP
  candidate:=CASE WHEN attempt=1 THEN base ELSE base||'_'||public.random_public_link_internal() END;
  IF (p_kind='form' AND NOT EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=candidate))
   OR (p_kind='occasion' AND NOT candidate=ANY(public.occasion_reserved_public_paths_internal())
    AND NOT EXISTS(SELECT 1 FROM public.occasion_link_reservations WHERE slug=candidate)) THEN RETURN candidate; END IF;
 END LOOP;
 RAISE unique_violation USING MESSAGE='Public link allocation exhausted';
END $$;
REVOKE ALL ON FUNCTION public.suggest_public_link(text,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.suggest_public_link(text,text,bigint) TO authenticated;

-- Canonical source: database/functions/others/ticket_layout.sql
-- Layout writes are accepted only through the explicit occasion-save boundary.
CREATE OR REPLACE FUNCTION public.can_edit_ticket_layout(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT auth.uid() IS NOT NULL AND COALESCE((SELECT public.get_is_editor_on_unit(o.unit)
    FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_edit_ticket_layout(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_edit_ticket_layout(bigint) TO authenticated;

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
      IF e->>'binding' IS NULL OR e->>'binding' NOT IN ('qr','ticketSymbol','spotGroup','productType','note','price','occasionTitle','occasionDatePlace','occasionStartTime','occasionPlace','orderName','logo','footer')
        OR (e->>'binding'<>'productType' AND e->>'binding'=ANY(bindings)) OR e->>'id'=ANY(ids) OR COALESCE(e->>'id','') !~ '^[a-zA-Z0-9_-]{1,40}$'
        OR jsonb_typeof(e->'visible') IS DISTINCT FROM 'boolean' OR jsonb_typeof(e->'locked') IS DISTINCT FROM 'boolean'
        OR (b->>'x')::numeric+(b->>'width')::numeric>(a->>'width')::numeric+.001
        OR (b->>'y')::numeric+(b->>'height')::numeric>(a->>'height')::numeric+.001
      THEN RAISE EXCEPTION 'Invalid layout element'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_object_keys(e) AS keys(key) WHERE keys.key NOT IN ('id','binding','productTypeId','label','box','visible','locked','style')) THEN RAISE EXCEPTION 'Invalid element metadata'; END IF;
      IF e->>'binding'='productType' THEN
        IF jsonb_typeof(e->'productTypeId') IS DISTINCT FROM 'number' OR jsonb_typeof(e->'label') IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'Invalid product field'; END IF;
        IF (e->>'productTypeId')::numeric NOT BETWEEN 1 AND 9007199254740991 OR trunc((e->>'productTypeId')::numeric)<>(e->>'productTypeId')::numeric
          OR e->>'label'<>btrim(e->>'label',U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') OR length(e->>'label')>120
          OR (SELECT count(*) FROM jsonb_array_elements(t->'elements') x WHERE x->'productTypeId'=e->'productTypeId')<>1
        THEN RAISE EXCEPTION 'Invalid product field'; END IF;
      ELSIF e ? 'productTypeId' OR e ? 'label' THEN RAISE EXCEPTION 'Invalid product metadata'; END IF;
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

-- Canonical source: database/functions/occasion_setup/sources.sql
-- One internal configuration projection, shared by new detail and legacy manifest.
CREATE OR REPLACE FUNCTION public.occasion_setup_source_internal(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',f.id,'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,'bank_account',f.bank_account,
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
      'id',b.id,'title',b.title,'configuration',b.configuration,'groups',b.groups,
      'background_svg',b.background_svg,
      'objects',COALESCE((SELECT jsonb_agg((obj - 'state' - 'order_product_ticket' - 'secret' - 'secret_expiration_time') ||
        jsonb_build_object('state','available','product',coalesce(to_jsonb(s.product),obj->'product'),'title',COALESCE(s.title,obj->>'title')))
        FROM jsonb_array_elements(COALESCE(b.objects,'[]'::jsonb)) obj
        LEFT JOIN eshop.spots s ON s.id=NULLIF(obj->>'id','')::bigint AND s.blueprint=b.id),'[]'::jsonb)) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
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
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
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
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit))
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
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Source access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.occasion_setup_source_internal(o.id) ORDER BY o.start_time DESC,o.id DESC)
  FROM public.occasions o WHERE o.unit=p_unit),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_source_list(bigint,bigint),public.get_occasion_setup_source(bigint,bigint),public.get_occasion_setup_sources(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_payment_context(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Payment settings access denied'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,
  'account_number',b.account_number,'supported_currencies',b.supported_currencies,'type',b.type)
  ORDER BY u.priority,b.id) FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
  WHERE u.unit=p_unit AND b.type IS DISTINCT FROM 'CASH'),'[]');
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_payment_context(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_payment_context(bigint) TO authenticated;

-- Canonical source: database/functions/occasion_setup/drafts.sql
-- Round in the event tenant's civil time; a single captured instant owns defaults.
CREATE OR REPLACE FUNCTION public.occasion_setup_default_start_internal(p_now timestamptz,p_timezone text DEFAULT 'Europe/Prague')
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public, extensions AS $$
 SELECT (date_trunc('hour',local_now) + ceil(extract(epoch FROM (local_now-date_trunc('hour',local_now)))/1800)*interval '30 minutes') AT TIME ZONE p_timezone
 FROM (SELECT (p_now AT TIME ZONE p_timezone)+interval '30 days' local_now) x;
$$;
REVOKE ALL ON FUNCTION public.occasion_setup_default_start_internal(timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;

-- Drafts are private workspace objects, never public occasions.
CREATE TABLE IF NOT EXISTS public.occasion_setup_drafts (
  id uuid PRIMARY KEY,
  unit bigint NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  author uuid NOT NULL REFERENCES auth.users(id),
  data jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(data) = 'object' AND octet_length(data::text) <= 262144),
  revision bigint NOT NULL DEFAULT 1,
  current_step integer NOT NULL DEFAULT 0 CHECK (current_step BETWEEN 0 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.occasion_setup_drafts DROP CONSTRAINT IF EXISTS occasion_setup_drafts_current_step_check;
ALTER TABLE public.occasion_setup_drafts ADD CONSTRAINT occasion_setup_drafts_current_step_check CHECK (current_step BETWEEN 0 AND 6);
CREATE INDEX IF NOT EXISTS occasion_setup_drafts_unit_idx ON public.occasion_setup_drafts(unit);
ALTER TABLE public.occasion_setup_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.occasion_setup_drafts FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_drafts(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY updated_at DESC)
    FROM public.occasion_setup_drafts d WHERE unit = p_unit AND NOT (d.data ? 'finalizedOccasion')), '[]'::jsonb);
END $$;

-- Terminal receipts remain readable to an already-open wizard, independently
-- of the resumable list. Never infer completion from a missing list item.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_draft(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='Draft access denied';
  END IF;
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_draft(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_draft(uuid) TO authenticated;

-- Run the canonical creator inside a rollback-only subtransaction. Its
-- complete configuration survives in a PL/pgSQL variable, but no occasion,
-- form, product, reminders or other rows escape into the normal application.
-- PostgreSQL sequences may advance; those IDs are draft-local references.
CREATE OR REPLACE FUNCTION public.build_occasion_setup_configuration(p_unit bigint, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE configuration jsonb; organization_id bigint;
  default_start timestamptz := public.occasion_setup_default_start_internal(now(),coalesce((SELECT data->>'timezone' FROM public.units WHERE id=p_unit),'Europe/Prague'));
  provisional_link text := 'draft-' || p_id::text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT organization INTO organization_id FROM public.units WHERE id = p_unit;
  BEGIN
    PERFORM public.update_occasion_internal_v1(jsonb_build_object(
      'unit',p_unit,'organization',organization_id,'title','',
      'link',provisional_link,'is_hidden',true,'is_open',false,
      'start_time',default_start,'end_time',default_start+interval '3 days'));
    SELECT public.occasion_setup_source_internal(id) INTO configuration
      FROM public.occasions WHERE link=provisional_link AND unit=p_unit;
    IF configuration IS NULL THEN RAISE EXCEPTION 'Creation configuration missing'; END IF;
    RAISE EXCEPTION 'Rollback provisional creation' USING ERRCODE = 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN
    -- Variables retain their values while all writes in the block roll back.
    NULL;
  END;
  configuration := jsonb_set(configuration,'{occasion,link}','""'::jsonb);
  configuration := jsonb_set(configuration,'{forms}',coalesce((SELECT jsonb_agg(jsonb_set(jsonb_set(jsonb_set(f,'{link}','""'::jsonb),'{deadline_duration_seconds}','null'::jsonb),'{data}',coalesce(nullif(f->'data','null'::jsonb),'{}'::jsonb)-'is_reminder_enabled'))
    FROM jsonb_array_elements(configuration->'forms') f),'[]'::jsonb));
  configuration := configuration || jsonb_build_object('communicationDefaults',coalesce((SELECT jsonb_strip_nulls(jsonb_build_object('reply_to',data->'reply_to','communication_tone',data->'communication_tone','is_reminder_enabled',data->'is_reminder_enabled','reminder_interval_seconds',data->'reminder_interval_seconds')) FROM public.units WHERE id=p_unit),'{}'::jsonb));
  RETURN configuration;
END $$;
REVOKE ALL ON FUNCTION public.build_occasion_setup_configuration(bigint,uuid) FROM PUBLIC,anon,authenticated;

-- Client-generated UUID makes canonical draft initialization safe to retry.
CREATE OR REPLACE FUNCTION public.create_occasion_setup_draft(p_id uuid, p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; is_new boolean; policy jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  -- Serialize identical UUIDs before inspecting existence, without charging retries.
  PERFORM pg_advisory_xact_lock(hashtextextended('draft:'||p_id::text,0));
  is_new:=NOT EXISTS(SELECT 1 FROM public.occasion_setup_drafts WHERE id=p_id);
  IF is_new THEN
    policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,(SELECT organization FROM public.units WHERE id=p_unit));
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,
      (SELECT organization FROM public.units WHERE id=p_unit),0,true,true,policy);
  END IF;
  INSERT INTO public.occasion_setup_drafts(id,unit,organization,author)
    SELECT p_id,id,organization,auth.uid() FROM public.units WHERE id = p_unit
    ON CONFLICT (id) DO NOTHING;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF d.unit IS DISTINCT FROM p_unit OR d.author IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF NOT (d.data ? 'defaultConfiguration') THEN
    IF NOT is_new THEN
      policy:=public.abuse_effective_rules_v1('occasion.draft',p_unit,d.organization);
      PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,0,false,true,policy);
    END IF;
    configuration := public.build_occasion_setup_configuration(p_unit,p_id);
    UPDATE public.occasion_setup_drafts SET data =
      jsonb_build_object('defaultConfiguration',configuration,
        'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true,'eventKind','regular')
      || d.data WHERE id = p_id RETURNING * INTO d;
    PERFORM public.admit_occasion_draft_v1(auth.uid(),p_unit,d.organization,octet_length(d.data::text),false,false,policy);
  END IF;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.initialize_occasion_setup_draft_defaults(p_id uuid, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts; configuration jsonb; policy jsonb;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'defaultConfiguration' THEN
    IF NOT (d.data->'defaultConfiguration' ? 'communicationDefaults') AND NOT (d.data ? 'finalizedOccasion') THEN
      IF d.revision IS DISTINCT FROM p_expected_revision THEN
        RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
      UPDATE public.occasion_setup_drafts SET data=jsonb_set(data,'{defaultConfiguration,communicationDefaults}',
        coalesce((SELECT jsonb_strip_nulls(jsonb_build_object('reply_to',u.data->'reply_to','communication_tone',u.data->'communication_tone','is_reminder_enabled',u.data->'is_reminder_enabled','reminder_interval_seconds',u.data->'reminder_interval_seconds')) FROM public.units u WHERE u.id=d.unit),'{}'::jsonb)),revision=revision+1,updated_at=now()
        WHERE id=p_id RETURNING * INTO d;
    END IF;
    RETURN to_jsonb(d);
  END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  policy:=public.abuse_effective_rules_v1('occasion.draft',d.unit,d.organization);
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,0,false,true,policy);
  configuration := public.build_occasion_setup_configuration(d.unit,p_id);
  UPDATE public.occasion_setup_drafts SET data =
    jsonb_build_object('defaultConfiguration',configuration,
      'formDraft',configuration->'forms'->0,'formDefaultsFollowEvent',true)
    || d.data, revision = revision+1, updated_at=now()
    WHERE id=p_id RETURNING * INTO d;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(d.data::text),false,false,policy);
  RETURN to_jsonb(d);
END $$;
REVOKE ALL ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_occasion_setup_draft_defaults(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_occasion_setup_draft(p_id uuid, p_expected_revision bigint, p_data jsonb, p_step integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
  p_data := p_data - 'finalizedOccasion' - 'finalizeResponse';
  IF p_data IS NULL OR jsonb_typeof(p_data) <> 'object' OR octet_length(p_data::text) > 262144 OR p_step IS NULL OR p_step NOT BETWEEN 0 AND 6 THEN
    RAISE EXCEPTION 'Invalid draft' USING ERRCODE = '22023'; END IF;
  IF p_data ? 'eventKind' AND p_data->>'eventKind' NOT IN ('regular','concert','ball') THEN RAISE invalid_parameter_value USING MESSAGE='Invalid event kind'; END IF;
  IF d.data ? 'copy_locale' THEN p_data := jsonb_set(p_data,'{copy_locale}',d.data->'copy_locale'); END IF;
  IF p_data ? 'copy_locale' AND p_data->>'sourceId' IS NOT NULL
     AND coalesce((p_data->>'copy_title_edited')::boolean,false)=false AND coalesce(p_data->>'title','')='' THEN
    IF NOT public.can_copy_occasion_source((p_data->>'sourceId')::bigint) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint AND organization=d.organization) THEN
      RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
    IF d.revision=p_expected_revision+1 AND d.data->>'sourceId'=p_data->>'sourceId' THEN
      p_data := jsonb_set(p_data,'{title}',d.data->'title');
    ELSE
      p_data := jsonb_set(p_data,'{title}',to_jsonb(public.copy_occasion_title_internal(
        (SELECT title FROM public.occasions WHERE id=(p_data->>'sourceId')::bigint),p_data->>'copy_locale')));
    END IF;
  END IF;
  IF d.revision = p_expected_revision + 1 AND d.data = p_data AND d.current_step = p_step THEN RETURN to_jsonb(d); END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001'; END IF;
  PERFORM public.admit_occasion_draft_v1(auth.uid(),d.unit,d.organization,octet_length(p_data::text),false,false);
  UPDATE public.occasion_setup_drafts SET data = p_data, current_step = p_step,
    revision = revision + 1, updated_at = now() WHERE id = p_id RETURNING * INTO d;
  RETURN to_jsonb(d);
END $$;

CREATE OR REPLACE FUNCTION public.delete_occasion_setup_draft(p_id uuid, p_unit bigint, p_expected_revision bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO d FROM public.occasion_setup_drafts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF d.unit <> p_unit THEN RAISE EXCEPTION 'Draft access denied' USING ERRCODE = '42501'; END IF;
  IF d.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'Draft changed in another session' USING ERRCODE = '40001';
  END IF;
  DELETE FROM public.occasion_setup_drafts WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_drafts(bigint), public.create_occasion_setup_draft(uuid,bigint),
  public.save_occasion_setup_draft(uuid,bigint,jsonb,integer), public.delete_occasion_setup_draft(uuid,bigint,bigint) TO authenticated;

-- Draft previews use the same private access/revision and document admission
-- as the editor, never a borrowed production occasion or a service-role read.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_ticket_preview(p_id uuid,p_revision bigint,p_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.revision IS DISTINCT FROM p_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed'; END IF;
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='Preview bytes required'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('ticket.preview',d.unit,d.organization),
  jsonb_build_object('actor',auth.uid(),'unit',d.unit,'organization',d.organization),jsonb_build_object('ticket.preview.payload.bytes',p_bytes));
 RETURN public.bound_document_data_v1(jsonb_build_object('data',d.data,'organization',d.organization));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_ticket_preview(uuid,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_ticket_preview(uuid,bigint,bigint) TO authenticated;

-- Canonical source: database/functions/occasion_setup/finalize.sql
-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE event_kind text; appearance jsonb; shared_font text; paid boolean; policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 blueprint_mode text; blueprint_id bigint; objects jsonb := '[]'; obj jsonb; v_commit public.client_commits%ROWTYPE;
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
 event_kind:=payload->>'eventKind';
 IF event_kind IS NOT NULL AND (event_kind NOT IN ('regular','concert','ball') OR coalesce((payload->>'eventKindNeedsConfirmation')::boolean,false)) THEN
  RAISE invalid_parameter_value USING MESSAGE='Confirm event kind'; END IF;
 IF event_kind IS NOT NULL THEN
  payload:=jsonb_set(payload,'{formEnabled}','true');
  IF event_kind<>'ball' THEN payload:=payload || '{"blueprintMode":"none"}'; END IF;
  IF event_kind='regular' THEN payload:=payload-'ticketDraft'; END IF;
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

 blueprint_mode := CASE payload->>'blueprintMode'
  WHEN 'none' THEN 'none' WHEN 'Bez plánku' THEN 'none'
  WHEN 'new' THEN 'new' WHEN 'Nový' THEN 'new'
  WHEN 'copy' THEN 'copy' WHEN 'Převzít' THEN 'copy'
  WHEN NULL THEN 'none' ELSE payload->>'blueprintMode' END;
 -- Old drafts without a mode were valid inline plans; keep that explicit legacy adapter.
 IF blueprint_mode IS NULL THEN blueprint_mode := CASE WHEN jsonb_array_length(coalesce(payload->'blueprintObjects','[]'))>0 THEN 'copy' ELSE 'none' END; END IF;
 IF event_kind='ball' AND blueprint_mode='none' THEN RAISE invalid_parameter_value USING MESSAGE='Ball requires seats'; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 IF blueprint_mode<>'none' AND (
  coalesce((payload->>'formEnabled')::boolean,true) IS NOT TRUE OR
  payload->'formDraft' IS NULL OR payload->'formDraft'='null'::jsonb OR
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload->'blueprintObjects','[]')) o WHERE o->>'type'='spot')
 ) THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint requires a form and sellable seats'; END IF;
 source_id := (payload->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH source_id IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 source_id := (payload->>'sourceId')::bigint;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF nullif(payload->>'start','') IS NULL OR nullif(payload->>'end','') IS NULL OR (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 IF payload->'ticketDraft' IS NOT NULL AND payload->'ticketDraft'<>'null'::jsonb THEN features := features || jsonb_build_array((payload->'ticketDraft')-'layout'); END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN features := features || '[{"code":"form","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'features',features,'data',jsonb_build_object('client_sync_v1',false) || CASE WHEN event_kind IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('eventKind',event_kind) END || CASE WHEN nullif(btrim(payload->>'replyTo'),'') IS NOT NULL THEN jsonb_build_object('reply_to',btrim(payload->>'replyTo')) ELSE '{}'::jsonb END);
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
 IF event_kind IS NOT NULL THEN
  form_data:=jsonb_set(form_data,'{title}',payload->'title');
 END IF;
 SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f,
  LATERAL jsonb_array_elements(coalesce(f->'product_type_data'->'products',f->'product_type'->'products','[]')) p
  WHERE coalesce((p->>'price')::numeric,0)>0 AND coalesce((p->>'is_hidden')::boolean,false)=false) INTO paid;
 IF NOT paid AND event_kind IS NOT NULL THEN
  form_data:=jsonb_set(form_data,'{data}',coalesce(nullif(form_data->'data','null'::jsonb),'{}')-ARRAY['payments','is_reminder_enabled','reminder_interval_seconds']);
  form_data:=form_data || '{"bank_account":null,"deadline_duration_seconds":null}';
 END IF;

 IF nullif(btrim(payload->>'replyTo'),'') IS NOT NULL AND (length(payload->>'replyTo')>254 OR payload->>'replyTo' !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+[.][^[:space:]<>@]+$') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid reply address'; END IF;
 IF coalesce(payload->>'communicationTone','inherit') NOT IN ('inherit','formal','informal') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid communication tone'; END IF;
 IF payload ? 'communicationTone' THEN
  form_data:=jsonb_set(form_data,'{data}',coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'communication_tone' ||
   CASE WHEN payload->>'communicationTone' IN ('formal','informal') THEN jsonb_build_object('communication_tone',payload->>'communicationTone') ELSE '{}'::jsonb END);
 END IF;
 -- A copied source's schedule is never the creation intent of the destination.
 IF payload ? 'saleMode' THEN
  form_data:=jsonb_set(form_data,'{data}',(coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time'-'enable_countdown') ||
   jsonb_build_object('schedule',(coalesce(nullif(form_data#>'{data,schedule}','null'::jsonb),'{}'::jsonb)-'start_time'-'end_time') || jsonb_build_object('sale_preparation',payload->>'saleMode'='preparation')));
 END IF;
 IF payload->>'saleMode' NOT IN ('preparation','scheduled','immediate') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
 IF payload->>'saleMode' IN ('scheduled','immediate') THEN
  IF coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) > (payload->>'end')::timestamptz OR
     coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz) <= now() OR
     (payload->>'saleMode'='scheduled' AND ((payload->>'saleStart') IS NULL OR (payload->>'saleStart')::timestamptz <= now() OR
       (payload->>'saleStart')::timestamptz >= coalesce((payload->>'saleEnd')::timestamptz,(payload->>'end')::timestamptz))) THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid sale interval'; END IF;
  form_data:=jsonb_set(form_data,'{data}',coalesce(form_data->'data','{}'::jsonb) || jsonb_build_object('schedule',jsonb_build_object(
    'start_time',CASE WHEN payload->>'saleMode'='scheduled' THEN payload->>'saleStart' ELSE now()::text END,
    'end_time',coalesce(payload->>'saleEnd',payload->>'end'))));
 END IF;
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Seat selection belongs to the active plan, never a stale form toggle.
  form_data := jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb) ||
   CASE WHEN blueprint_mode<>'none' THEN '[{"type":"spot","is_ticket_field":true,"is_hidden":false,"order":-1}]'::jsonb ELSE '[]'::jsonb END);
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
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(nullif(form_data->>'link',''),(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',coalesce(payload->>'saleMode','preparation') IN ('scheduled','immediate'),'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  -- Validate configured bank routes using the checkout's exact linked-account,
  -- non-cash and supported-currency predicates. Account priority stays checkout-owned.
  IF coalesce(form_data#>'{data,payments,bankEnabled}','true'::jsonb)='true'::jsonb AND EXISTS(
    SELECT 1 FROM eshop.products p WHERE p.occasion=new_id AND p.price>0
      AND NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts u JOIN eshop.bank_accounts b ON b.id=u.bank_account
        WHERE u.unit=d.unit AND b.type IS DISTINCT FROM 'CASH' AND b.supported_currencies @> ARRAY[p.currency_code::text]
          AND (nullif(form_data->>'bank_account','') IS NULL OR b.id=(form_data->>'bank_account')::bigint))) THEN
    RAISE invalid_parameter_value USING MESSAGE='No valid bank route for the selected currencies';
  END IF;
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
   FOR obj IN SELECT value FROM jsonb_array_elements(payload->'blueprintObjects') LOOP
    -- Editor/source models contain read-only occupancy. Only configuration
    -- crosses the create boundary; the general blueprint command stays strict.
    obj := obj-ARRAY['id','state','order_product_ticket','secret','secret_expiration_time'];
    IF obj->>'type'='spot' AND (obj->>'product' IS NULL OR product_map->>(obj->>'product') IS NULL) THEN
     RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
    IF obj->>'product' IS NOT NULL THEN obj := jsonb_set(obj,'{product}',coalesce(product_map->(obj->>'product'),'null'::jsonb)); END IF;
    objects := objects || jsonb_build_array(obj);
   END LOOP;
   result := public.update_blueprint_internal_v1(jsonb_build_object('occasion',new_id,'organization',d.organization,
    'title',payload->>'blueprintTitle','configuration',jsonb_build_object('dimensions',jsonb_build_object(
     'width',coalesce((payload->>'blueprintWidth')::numeric,12),'height',coalesce((payload->>'blueprintHeight')::numeric,8))),
    'groups',coalesce(payload->'blueprintGroups','[]'),'objects',objects,'background_svg',payload->>'blueprintBackground'));
   IF (result->>'code')::int NOT IN (200,201) THEN RAISE EXCEPTION '%',result; END IF;
   blueprint_id := (result->>'blueprint_id')::bigint;
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features := features || '[{"code":"blueprint","is_enabled":true}]';
  END IF;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft';
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

COMMIT;
