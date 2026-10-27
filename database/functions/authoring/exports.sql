-- Export columns are generated from the shared closed contract. No selected SQL,
-- table name, raw order snapshot, QR, hold secret or credential can be requested.
CREATE OR REPLACE FUNCTION public.authorize_authoring_export(p_occasion bigint,p_organization bigint,p_unit bigint,p_dataset text,p_columns jsonb DEFAULT '[]')
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_dataset IN ('report','orders') THEN
  IF NOT public.can_read_orders(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order report/export denied'; END IF;
 ELSIF p_dataset='people' THEN
  IF NOT public.can_manage_occasion_participants(p_occasion) OR ((p_columns ?| ARRAY['email','phone','birthDate']) AND NOT public.can_read_participant_contacts(p_occasion)) THEN
   RAISE insufficient_privilege USING MESSAGE='participant export denied'; END IF;
 ELSIF p_dataset IN ('events','speakers','places') THEN PERFORM public.require_program_domain_internal_v1(p_occasion,p_dataset,false);
 ELSIF p_dataset='feedback' THEN
  IF NOT public.can_read_schedule_feedback(p_occasion) OR NOT public.get_is_event_feedback_enabled_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='feedback export denied'; END IF;
 ELSE RAISE invalid_parameter_value USING MESSAGE='unsupported export dataset'; END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.authorize_authoring_export(bigint,bigint,bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.authorize_authoring_export(bigint,bigint,bigint,text,jsonb) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_authoring_export_page(p_occasion bigint,p_organization bigint,p_unit bigint,p_dataset text,p_columns jsonb,p_after text DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE spec jsonb:=public.authoring_export_columns_internal_v1();rows jsonb; result jsonb; next_cursor text;
BEGIN
 PERFORM public.authorize_authoring_export(p_occasion,p_organization,p_unit,p_dataset,p_columns);
 IF (spec ? p_dataset) IS NOT TRUE OR p_limit NOT BETWEEN 1 AND 50 OR jsonb_typeof(p_columns) IS DISTINCT FROM 'array' OR jsonb_array_length(p_columns) NOT BETWEEN 1 AND 20
  OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_columns) c WHERE NOT(spec->p_dataset->'columns' ? c))
  OR jsonb_array_length(p_columns)<>(SELECT count(DISTINCT c) FROM jsonb_array_elements_text(p_columns) c) THEN
  RAISE invalid_parameter_value USING MESSAGE='closed export columns and page required'; END IF;
 IF p_dataset='orders' THEN
  result:=public.get_operator_orders_v1(p_occasion,p_organization,p_unit,p_limit,p_after::bigint);
  next_cursor:=result->>'nextCursor';
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',r->'id','symbol',r->'symbol','state',r->'state','createdAt',r->'createdAt','ticketCount',r->'ticketCount',
   'price',r->'price','currency',r->'currency','paid',r#>'{payment,paid}') ORDER BY n),'[]'::jsonb) INTO rows FROM jsonb_array_elements(result->'orders') WITH ORDINALITY x(r,n);
 ELSIF p_dataset='people' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."userId"),'[]'::jsonb) INTO rows FROM (
   SELECT ou."user" AS "userId",ui.name,ui.surname,ui.email_readonly AS email,ui.phone,ui.birth_date AS "birthDate",ou.role,
    coalesce((ou.data->>'is_volunteer')::boolean,false) AS "isVolunteer",coalesce(ou.is_approved,false) AS "isApproved",ou.data->>'note' AS note
   FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user" WHERE ou.occasion=p_occasion AND (p_after IS NULL OR ou."user">p_after::uuid) ORDER BY ou."user" LIMIT p_limit) page;
  IF jsonb_array_length(rows)=p_limit THEN next_cursor:=rows->-1->>'userId'; END IF;
 ELSIF p_dataset='events' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb) INTO rows FROM (
   SELECT e.id,e.title,e.start_time AS "startTime",e.end_time AS "endTime",e.max_participants AS "maxParticipants",coalesce(v.version,0) AS "aggregateVersion"
   FROM public.events e LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=e.id::text
   WHERE e.occasion=p_occasion AND (p_after IS NULL OR e.id>p_after::bigint) ORDER BY e.id LIMIT p_limit) page;
  IF jsonb_array_length(rows)=p_limit THEN next_cursor:=rows->-1->>'id'; END IF;
 ELSIF p_dataset='speakers' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb) INTO rows FROM (
   SELECT e.id,e.title,e.subtitle,e.description,coalesce(v.version,0) AS "aggregateVersion" FROM public.speakers e
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='speaker' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=e.id::text
   WHERE e.occasion=p_occasion AND (p_after IS NULL OR e.id>p_after::bigint) ORDER BY e.id LIMIT p_limit) page;
  IF jsonb_array_length(rows)=p_limit THEN next_cursor:=rows->-1->>'id'; END IF;
 ELSIF p_dataset='places' THEN
  SELECT coalesce(jsonb_agg(to_jsonb(page) ORDER BY page.id),'[]'::jsonb) INTO rows FROM (
   SELECT e.id,e.title,e.description,e.type,coalesce(v.version,0) AS "aggregateVersion" FROM public.places e
   LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=e.id::text
   WHERE e.occasion=p_occasion AND (p_after IS NULL OR e.id>p_after::bigint) ORDER BY e.id LIMIT p_limit) page;
  IF jsonb_array_length(rows)=p_limit THEN next_cursor:=rows->-1->>'id'; END IF;
 ELSIF p_dataset='feedback' THEN
  result:=public.get_event_feedback_export_page_internal_v1(p_occasion,p_after::bigint,p_limit);
  IF result->>'code'<>'200' THEN RAISE insufficient_privilege USING MESSAGE='feedback export denied'; END IF;
  -- Preserve the existing projection, but use stable feedback ID order for export pages.
  SELECT coalesce(jsonb_agg(r ORDER BY (r->>'feedback_id')::bigint),'[]'::jsonb) INTO rows FROM jsonb_array_elements(result->'data') r;
  IF jsonb_array_length(rows)=p_limit THEN next_cursor:=rows->-1->>'feedback_id'; END IF;
 END IF;
 -- Drop unselected columns in SQL before any personal data crosses the boundary.
 SELECT coalesce(jsonb_agg((SELECT jsonb_object_agg(k,v) FROM jsonb_each(r) x(k,v) WHERE p_columns ? k) ORDER BY n),'[]'::jsonb) INTO rows
 FROM jsonb_array_elements(coalesce(rows,'[]')) WITH ORDINALITY x(r,n);
 RETURN jsonb_build_object('columns',p_columns,'rows',rows,'nextCursor',next_cursor);
END $$;
REVOKE ALL ON FUNCTION public.get_authoring_export_page(bigint,bigint,bigint,text,jsonb,text,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_authoring_export_page(bigint,bigint,bigint,text,jsonb,text,integer) TO authenticated,service_role;
