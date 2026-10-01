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
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path = public, extensions AS $$
DECLARE t jsonb; e jsonb; b jsonb; s jsonb; a jsonb; q jsonb; kind text; k text; ids text[]; bindings text[];
BEGIN
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' OR p_layout->'schemaVersion' IS DISTINCT FROM '1'::jsonb
    OR jsonb_typeof(p_layout->'templates') IS DISTINCT FROM 'object' OR p_layout->'templates'='{}'::jsonb OR octet_length(p_layout::text)>32768
  THEN RAISE EXCEPTION 'Invalid ticket layout'; END IF;
  FOR kind,t IN SELECT * FROM jsonb_each(p_layout->'templates') LOOP
    IF kind NOT IN ('wide','named') OR jsonb_typeof(t->'elements') IS DISTINCT FROM 'array'
      OR jsonb_array_length(t->'elements') NOT BETWEEN 2 AND 11
      OR (t ? 'pageFit' AND t->'pageFit' IS DISTINCT FROM '"ticket"'::jsonb)
      OR (NOT (t ? 'pageFit') AND kind='wide' AND t->'page' IS DISTINCT FROM '{"width":595.28,"height":841.89}'::jsonb)
      OR (NOT (t ? 'pageFit') AND kind='named' AND t->'page' IS DISTINCT FROM '{"width":212.5,"height":387.5}'::jsonb)
    THEN RAISE EXCEPTION 'Invalid ticket template'; END IF;
    IF t->>'pageFit'='ticket' THEN
      IF jsonb_typeof(t->'page'->'width') IS DISTINCT FROM 'number'
        OR jsonb_typeof(t->'page'->'height') IS DISTINCT FROM 'number'
      THEN RAISE EXCEPTION 'Invalid ticket page'; END IF;
      IF (t->'page'->>'width')::numeric NOT BETWEEN 60 AND 842
        OR (t->'page'->>'height')::numeric NOT BETWEEN 60 AND 842
        OR t->'ticketArea'->'x' IS DISTINCT FROM '0'::jsonb
        OR t->'ticketArea'->'y' IS DISTINCT FROM '0'::jsonb
        OR t->'ticketArea'->'width' IS DISTINCT FROM t->'page'->'width'
        OR t->'ticketArea'->'height' IS DISTINCT FROM t->'page'->'height'
      THEN RAISE EXCEPTION 'Ticket page must match ticket area'; END IF;
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
      THEN RAISE EXCEPTION 'Invalid layout style'; END IF;
      IF (s->>'fontSize')::numeric NOT BETWEEN 6 AND 72 OR (s->>'minFontSize')::numeric NOT BETWEEN 6 AND (s->>'fontSize')::numeric
        OR (s->>'maxLines')::numeric NOT BETWEEN 1 AND 12 OR (s->>'maxLines')::numeric<>trunc((s->>'maxLines')::numeric)
      THEN RAISE EXCEPTION 'Invalid text size'; END IF;
      IF e->>'binding' IN ('qr','ticketSymbol') AND e->'visible'<>'true'::jsonb THEN RAISE EXCEPTION 'Required ticket element hidden'; END IF;
      IF e->>'binding'='qr' THEN
        q:=b;
        IF b->'width'<>b->'height' OR (b->>'width')::numeric<60 OR upper(s->>'color') NOT IN ('000000','2A2A2A','17365D','123B20','401529') THEN RAISE EXCEPTION 'Invalid QR dimensions'; END IF;
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
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE
SET search_path = public, extensions AS $$
DECLARE old_layout jsonb; next_layout jsonb; f jsonb; result jsonb:='[]'; found_ticket boolean:=false;
BEGIN
  IF jsonb_typeof(p_next) IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_array_elements(p_next) e WHERE e->>'code'='ticket')>1
  THEN RAISE EXCEPTION 'Invalid features'; END IF;
  SELECT value->'layout' INTO old_layout FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  next_layout:=old_layout;
  IF p_change IS NOT NULL THEN
    IF jsonb_typeof(p_change)<>'object' OR NOT (p_change ? 'expected' AND p_change ? 'next') THEN RAISE EXCEPTION 'Invalid ticket layout change'; END IF;
    IF COALESCE(old_layout,'null') IS DISTINCT FROM p_change->'expected' THEN
      RAISE EXCEPTION 'ticket_layout_conflict' USING ERRCODE='40001';
    END IF;
    -- A client must not downgrade a schema it does not understand.
    IF old_layout IS NOT NULL AND old_layout->'schemaVersion' IS DISTINCT FROM '1'::jsonb THEN RAISE EXCEPTION 'Unsupported ticket layout'; END IF;
    next_layout:=p_change->'next'; PERFORM public.validate_ticket_layout(next_layout);
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
