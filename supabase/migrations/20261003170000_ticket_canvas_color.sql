CREATE OR REPLACE FUNCTION public.validate_ticket_layout(p_layout jsonb)
RETURNS void LANGUAGE plpgsql STABLE
SET search_path = public, extensions AS $$
DECLARE t jsonb; e jsonb; b jsonb; s jsonb; a jsonb; q jsonb; kind text; k text; ids text[]; bindings text[]; luminance double precision; background_luminance double precision;
BEGIN
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' OR p_layout->'schemaVersion' NOT IN ('1'::jsonb,'2'::jsonb) OR NOT (p_layout ? 'schemaVersion')
    OR jsonb_typeof(p_layout->'templates') IS DISTINCT FROM 'object' OR p_layout->'templates'='{}'::jsonb OR octet_length(p_layout::text)>32768
  THEN RAISE EXCEPTION 'Invalid ticket layout'; END IF;
  IF (SELECT count(DISTINCT id) FROM (
    SELECT value->>'fontId' id FROM jsonb_each(p_layout->'templates')
    UNION ALL SELECT elem.value->'style'->>'fontId' FROM jsonb_each(p_layout->'templates') tmpl CROSS JOIN LATERAL jsonb_array_elements(tmpl.value->'elements') elem
  ) fonts WHERE id IS NOT NULL)>12 THEN RAISE EXCEPTION 'Too many ticket fonts'; END IF;
  FOR kind,t IN SELECT * FROM jsonb_each(p_layout->'templates') LOOP
    IF kind NOT IN ('wide','named') OR jsonb_typeof(t->'elements') IS DISTINCT FROM 'array'
      OR jsonb_array_length(t->'elements') NOT BETWEEN 2 AND 11
      OR (t ? 'pageFit' AND t->'pageFit' IS DISTINCT FROM '"ticket"'::jsonb)
      OR (NOT (t ? 'pageFit')
          AND t->'page' IS DISTINCT FROM '{"width":595.28,"height":841.89}'::jsonb
          AND t->'page' IS DISTINCT FROM '{"width":212.5,"height":387.5}'::jsonb)
    THEN RAISE EXCEPTION 'Invalid ticket template'; END IF;
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
      IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(t->'flow') v WHERE v NOT IN ('spotGroup','food','note','price'))
        OR (SELECT count(*)<>count(DISTINCT v) FROM jsonb_array_elements_text(t->'flow') v)
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
    IF p_layout->>'schemaVersion'='2' AND t ? 'font' THEN RAISE EXCEPTION 'Legacy font field in schema 2'; END IF;
    IF t ? 'fontId' THEN
      IF p_layout->>'schemaVersion'='1' OR jsonb_typeof(t->'fontId')<>'string'
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
        IF p_layout->>'schemaVersion'='1' OR e->>'binding' IN ('qr','logo') OR jsonb_typeof(s->'fontId')<>'string'
          OR NOT EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=s->>'fontId')
        THEN RAISE EXCEPTION 'Invalid ticket font'; END IF;
      END IF;
      IF e->>'binding' IS NULL OR e->>'binding' NOT IN ('qr','ticketSymbol','spotGroup','food','note','price','occasionTitle','occasionDatePlace','orderName','logo','footer')
        OR e->>'binding'=ANY(bindings) OR e->>'id'=ANY(ids) OR COALESCE(e->>'id','') !~ '^[a-zA-Z0-9_-]{1,40}$'
        OR jsonb_typeof(e->'visible') IS DISTINCT FROM 'boolean' OR jsonb_typeof(e->'locked') IS DISTINCT FROM 'boolean'
        OR (b->>'x')::numeric+(b->>'width')::numeric>(a->>'width')::numeric+.001
        OR (b->>'y')::numeric+(b->>'height')::numeric>(a->>'height')::numeric+.001
      THEN RAISE EXCEPTION 'Invalid layout element'; END IF;
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
