-- Accept validated schema-2 font IDs when the editor upgrades a legacy layout.
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
    IF jsonb_typeof(p_change)<>'object' OR NOT (p_change ? 'expected' AND p_change ? 'next') THEN RAISE EXCEPTION 'Invalid ticket layout change'; END IF;
    IF COALESCE(old_layout,'null') IS DISTINCT FROM p_change->'expected' THEN
      RAISE EXCEPTION 'ticket_layout_conflict' USING ERRCODE='40001';
    END IF;
    -- A client must not downgrade a schema it does not understand.
    IF old_layout IS NOT NULL AND old_layout->'schemaVersion' NOT IN ('1'::jsonb,'2'::jsonb) THEN RAISE EXCEPTION 'Unsupported ticket layout'; END IF;
    next_layout:=p_change->'next';
    IF old_layout->>'schemaVersion'='2' AND next_layout->>'schemaVersion'='1' THEN RAISE EXCEPTION 'Ticket layout downgrade'; END IF;
    IF next_layout IS DISTINCT FROM 'null'::jsonb THEN PERFORM public.validate_ticket_layout(next_layout); ELSE next_layout:=NULL; END IF;
    -- Old clients discard appearance fields they do not understand. Fail closed
    -- instead of turning a migrated original back into an approximate preset.
    -- A validated schema-2 fontId is the current editor's explicit replacement.
    IF EXISTS(SELECT 1 FROM jsonb_each(COALESCE(old_layout->'templates','{}'::jsonb)) old
      WHERE old.value ? 'font' AND NOT COALESCE(next_layout->'templates'->old.key ? 'font',false)
        AND NOT COALESCE(next_layout->>'schemaVersion'='2'
          AND next_layout->'templates'->old.key ? 'fontId',false))
    THEN RAISE EXCEPTION 'Ticket editor update required'; END IF;
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
