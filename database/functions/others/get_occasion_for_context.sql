-- Object-derived context, shared by participant and editor client readers.
CREATE OR REPLACE FUNCTION public.get_occasion_for_context_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE o public.occasions; privileged boolean;
BEGIN
 SELECT * INTO o FROM public.occasions WHERE id=p_occasion;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='occasion unavailable'; END IF;
 privileged := public.can_read_occasion_editor_data(o.id);
 IF public.is_demo_occasion(o.id) AND NOT public.can_read_demo_occasion(o.id) THEN
   RAISE insufficient_privilege USING MESSAGE='occasion unavailable';
 END IF;
 IF privileged THEN
   RETURN to_jsonb(o);
 END IF;
 IF auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasion_users
     WHERE occasion=o.id AND "user"=auth.uid()) THEN
   RETURN to_jsonb(o)-'occasion_hidden';
 END IF;
 IF o.is_hidden IS DISTINCT FROM false OR o.is_open IS DISTINCT FROM true THEN
   RAISE insufficient_privilege USING MESSAGE='occasion unavailable';
 END IF;
 RETURN jsonb_build_object('id',o.id,'title',o.title,'description',o.description,
   'link',o.link,'start_time',o.start_time,'end_time',o.end_time,
   'is_open',o.is_open,'is_hidden',false,'is_promoted',o.is_promoted,
   'organization',o.organization,'unit',o.unit,
   'data',jsonb_build_object('timezone',o.data->'timezone'));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_for_context_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_occasion_for_context_v1(bigint) TO anon,authenticated,service_role;

ALTER FUNCTION public.get_occasion_for_context_v1(bigint) OWNER TO postgres;
