-- The single presentation policy for a purchased seat or standing allocation.
CREATE OR REPLACE FUNCTION public.order_seating_placement_internal(p_kind text,p_title text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE catalog jsonb;
 label_key text;
 title text:=nullif(trim(p_title),'');
 prefix text;
BEGIN
  -- BEGIN GENERATED SEATING LABELS
  catalog:=$labels${"cs":{"table":"Stůl","group":"Skupina","couch":"Gauč","row":"Řada","standingPlace":"Místo na stání","seat":"Místo"},"de":{"table":"Tisch","group":"Gruppe","couch":"Sofa","row":"Reihe","standingPlace":"Stehplatz","seat":"Sitzplatz"},"en":{"table":"Table","group":"Group","couch":"Couch","row":"Row","standingPlace":"Standing place","seat":"Seat"},"es":{"table":"Mesa","group":"Grupo","couch":"Sofá","row":"Fila","standingPlace":"Lugar de pie","seat":"Asiento"},"pl":{"table":"Stół","group":"Grupa","couch":"Kanapa","row":"Rząd","standingPlace":"Miejsce stojące","seat":"Miejsce"},"sk":{"table":"Stôl","group":"Skupina","couch":"Gauč","row":"Rad","standingPlace":"Miesto na státie","seat":"Miesto"},"uk":{"table":"Стіл","group":"Група","couch":"Диван","row":"Ряд","standingPlace":"Стояче місце","seat":"Місце"}}$labels$::jsonb;
  -- END GENERATED SEATING LABELS
 label_key:=CASE p_kind WHEN 'standing' THEN 'standingPlace'
  WHEN 'table' THEN 'table' WHEN 'couch' THEN 'couch' WHEN 'row' THEN 'row'
  ELSE CASE WHEN title ~ '^[0-9]+$' THEN 'group' END END;
 IF label_key IS NULL AND title IS NULL THEN RETURN NULL; END IF;
 IF label_key IS NOT NULL AND title IS NOT NULL THEN
  SELECT variants.prefix INTO prefix
  FROM jsonb_each(catalog) locale
  CROSS JOIN LATERAL (SELECT locale.value->>label_key AS prefix) variants
  WHERE lower(title)=lower(variants.prefix)
     OR starts_with(lower(title),lower(variants.prefix)||' ')
     OR starts_with(lower(title),lower(variants.prefix)||':')
  ORDER BY length(variants.prefix) DESC LIMIT 1;
  IF prefix IS NOT NULL THEN
   title:=nullif(ltrim(substr(title,length(prefix)+1),' :'),'');
  END IF;
 END IF;
 RETURN jsonb_strip_nulls(jsonb_build_object('labelKey',label_key,'value',title,
   'separator',CASE WHEN label_key='standingPlace' THEN ': ' END));
END $$;
REVOKE ALL ON FUNCTION public.order_seating_placement_internal(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_seating_placement_internal(text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.order_present_seating_internal(p_item jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT (p_item-'placement') || CASE WHEN placement IS NULL THEN '{}'::jsonb
   ELSE jsonb_build_object('placement',placement) END
 FROM (SELECT CASE WHEN p_item->'is_standing'='true'::jsonb
    THEN public.order_seating_placement_internal('standing',p_item->>'standing_area_title')
    ELSE public.order_seating_placement_internal(p_item->>'spot_group_kind',p_item->>'spot_group_title') END AS placement) formatted;
$$;
REVOKE ALL ON FUNCTION public.order_present_seating_internal(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_present_seating_internal(jsonb) TO service_role;
