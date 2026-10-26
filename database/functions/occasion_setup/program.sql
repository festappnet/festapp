-- Only saved program configuration crosses this boundary. No attendees,
-- assignments, feedback, counters or timestamps are exported or copied.
CREATE OR REPLACE FUNCTION public.materialize_occasion_setup_program_internal(p_events jsonb,p_occasion bigint,p_unit bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE item jsonb; place_data jsonb; ref jsonb; new_event bigint; new_place bigint; new_role bigint; new_group bigint;
 event_map jsonb:='{}'; place_map jsonb:='{}'; role_map jsonb:='{}'; group_map jsonb:='{}'; child text;
BEGIN
 PERFORM public.check_is_editor_on_occasion(p_occasion);
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND unit=p_unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Program target unit mismatch'; END IF;
 IF jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN RAISE invalid_parameter_value USING MESSAGE='Invalid program configuration'; END IF;
 IF (SELECT count(*)<>count(DISTINCT e->>'id') FROM jsonb_array_elements(p_events) e WHERE e->>'id' IS NOT NULL) THEN
  RAISE invalid_parameter_value USING MESSAGE='Duplicate program identity'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_events) LOOP
  new_place:=NULL; place_data:=item->'place';
  IF jsonb_typeof(place_data)='object' THEN
   new_place:=(place_map->>(place_data->>'id'))::bigint;
   IF new_place IS NULL THEN
    INSERT INTO public.places(occasion,unit,title,description,type,coordinates,is_hidden,"order",icon)
    VALUES(p_occasion,p_unit,place_data->>'title',place_data->>'description',place_data->>'type',
      place_data->'coordinates',coalesce((place_data->>'is_hidden')::boolean,false),(place_data->>'order')::bigint,(place_data->>'icon')::bigint)
    RETURNING id INTO new_place;
    IF place_data->>'id' IS NOT NULL THEN place_map:=place_map||jsonb_build_object(place_data->>'id',new_place); END IF;
   END IF;
  END IF;
  INSERT INTO public.events(occasion,title,start_time,end_time,description,max_participants,is_hidden,is_group_event,split_for_men_women,type,place,"order")
  VALUES(p_occasion,item->>'title',(item->>'start_time')::timestamptz,(item->>'end_time')::timestamptz,item->>'description',
    (item->>'max_participants')::bigint,coalesce((item->>'is_hidden')::boolean,false),coalesce((item->>'is_group_event')::boolean,false),
    coalesce((item->>'split_for_men_women')::boolean,false),item->>'type',new_place,coalesce((item->>'order')::bigint,0)) RETURNING id INTO new_event;
  IF item->>'id' IS NOT NULL THEN event_map:=event_map||jsonb_build_object(item->>'id',new_event); END IF;
  FOR ref IN SELECT value FROM jsonb_array_elements(coalesce(item->'roles','[]')) LOOP
   new_role:=(role_map->>(ref->>'id'))::bigint;
   IF new_role IS NULL THEN
    INSERT INTO public.role_info(occasion,title) VALUES(p_occasion,ref->>'title') RETURNING id INTO new_role;
    role_map:=role_map||jsonb_build_object(ref->>'id',new_role);
   END IF;
   INSERT INTO public.event_roles(event,role) VALUES(new_event,new_role);
  END LOOP;
  FOR ref IN SELECT value FROM jsonb_array_elements(coalesce(item->'exclusive_groups','[]')) LOOP
   new_group:=(group_map->>(ref->>'id'))::bigint;
   IF new_group IS NULL THEN
    INSERT INTO public.exclusive_groups(occasion,title) VALUES(p_occasion,ref->>'title') RETURNING id INTO new_group;
    group_map:=group_map||jsonb_build_object(ref->>'id',new_group);
   END IF;
   INSERT INTO public.exclusive_events(event,"group") VALUES(new_event,new_group);
  END LOOP;
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(p_events) LOOP
  FOR child IN SELECT value FROM jsonb_array_elements_text(coalesce(item->'children','[]')) LOOP
   IF event_map->>(item->>'id') IS NULL OR event_map->>child IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='Program group reference missing'; END IF;
   INSERT INTO public.event_groups(event_parent,event_child) VALUES((event_map->>(item->>'id'))::bigint,(event_map->>child)::bigint);
  END LOOP;
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.materialize_occasion_setup_program_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
