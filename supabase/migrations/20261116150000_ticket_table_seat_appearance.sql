-- Table seat display is a typed ticket-template appearance, shared by preview and PDF.

-- SOURCE: others/ticket_layout.sql
-- Closed delivery contract. Missing attributes retain the PDF default without backfill.
CREATE OR REPLACE FUNCTION public.ticket_delivery_mode(p_feature jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
BEGIN
 IF NOT coalesce(p_feature ? 'delivery_mode',false) THEN RETURN 'pdf_attachment'; END IF;
 IF jsonb_typeof(p_feature->'delivery_mode') IS DISTINCT FROM 'string'
   OR p_feature->>'delivery_mode' NOT IN ('pdf_attachment','inline_qr','both') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid ticket delivery mode'; END IF;
 RETURN p_feature->>'delivery_mode';
END $$;
REVOKE ALL ON FUNCTION public.ticket_delivery_mode(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ticket_delivery_mode(jsonb) TO authenticated,service_role;

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
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(t) AS keys(key) WHERE keys.key NOT IN ('canvasGradient','canvasColor','canvasOpacity','backgroundCrop','pageMargin','backgroundTransform','fontId','flow','flowStep','qrAppearance','spotGroupAppearance','border','pageFit','page','ticketArea','elements')) THEN RAISE EXCEPTION 'Invalid template metadata'; END IF;
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
    IF t ? 'spotGroupAppearance' THEN
      IF jsonb_typeof(t->'spotGroupAppearance') IS DISTINCT FROM 'object'
        OR jsonb_typeof(t->'spotGroupAppearance'->'showSeat') IS DISTINCT FROM 'boolean'
        OR (SELECT count(*) FROM jsonb_object_keys(t->'spotGroupAppearance')) <> 1
      THEN RAISE EXCEPTION 'Invalid table appearance'; END IF;
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
DECLARE old_ticket jsonb; old_layout jsonb; next_layout jsonb; f jsonb; result jsonb:='[]'; found_ticket boolean:=false;
BEGIN
  IF jsonb_typeof(p_next) IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_array_elements(p_next) e WHERE e->>'code'='ticket')>1
  THEN RAISE EXCEPTION 'Invalid features'; END IF;
  SELECT value->'layout' INTO old_layout FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  SELECT value INTO old_ticket FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
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
      -- Older clients omitting the attribute cannot reset an explicit choice.
      IF NOT p_create AND NOT (f ? 'delivery_mode') AND old_ticket ? 'delivery_mode' THEN
        f:=f||jsonb_build_object('delivery_mode',old_ticket->'delivery_mode'); END IF;
      IF NOT p_create AND NOT (f ? 'wallet_enabled') AND old_ticket ? 'wallet_enabled' THEN
        f:=f||jsonb_build_object('wallet_enabled',old_ticket->'wallet_enabled'); END IF;
      IF NOT p_create AND NOT (f ? 'wallet_appearance') AND old_ticket ? 'wallet_appearance' THEN
        f:=f||jsonb_build_object('wallet_appearance',old_ticket->'wallet_appearance'); END IF;
      PERFORM public.validate_ticket_wallet_appearance(f);
      PERFORM public.ticket_wallet_enabled(f);
      PERFORM public.ticket_delivery_mode(f);
      IF p_create AND p_change IS NULL THEN next_layout:=f->'layout'; IF next_layout IS NOT NULL THEN PERFORM public.validate_ticket_layout(next_layout); END IF; END IF;
      f:=f-'layout'; IF next_layout IS NOT NULL THEN f:=f||jsonb_build_object('layout',next_layout); END IF;
    END IF;
    result:=result||jsonb_build_array(f);
  END LOOP;
  IF NOT found_ticket AND (next_layout IS NOT NULL OR old_ticket ? 'delivery_mode' OR old_ticket ? 'wallet_enabled' OR old_ticket ? 'wallet_appearance') THEN result:=result||jsonb_build_array((coalesce(old_ticket,'{}'::jsonb) || jsonb_build_object('code','ticket','is_enabled',false) || CASE WHEN next_layout IS NOT NULL THEN jsonb_build_object('layout',next_layout) ELSE '{}'::jsonb END)); END IF;
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
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_appearance) k WHERE k NOT IN ('background','ticket_type','wallet_appearance'))
  OR (p_appearance ? 'ticket_type' AND p_appearance->>'ticket_type' IS NOT NULL
    AND p_appearance->>'ticket_type' NOT IN ('wide','named')) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid ticket appearance'; END IF;
 PERFORM public.validate_ticket_wallet_appearance(p_appearance);
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

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','4a2bacea00089021e673b0ef3fd67237',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','e5418eafc472dc4076cf366b2e82df82',true,true),
  ('public.ticket_wallet_ready(bigint)','25dc8cba98b32f00f8f0980b207fa197',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','e57ee2a1c8cb4110d1a78b99f9894a96',true,true),
  ('public.validate_ticket_layout(jsonb)','a69c5ebb2b3e7dcf241202182c4dfa4a',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;
