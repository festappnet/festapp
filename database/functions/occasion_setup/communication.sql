CREATE OR REPLACE FUNCTION public.get_occasion_setup_communication(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; u public.units; manager boolean; version bigint; snapshot record;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 SELECT row_u,coalesce(v.version,0) AS aggregate_version INTO snapshot FROM public.units row_u
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='unit' AND v.scope_type='unit'
   AND v.scope_id=row_u.id AND v.aggregate_id=row_u.id::text WHERE row_u.id=d.unit;
 u:=snapshot.row_u; version:=snapshot.aggregate_version;
 manager:=public.get_is_manager_on_unit(d.unit);
 RETURN jsonb_build_object('canManage',manager,
  'firstEvent',NOT EXISTS(SELECT 1 FROM public.occasions WHERE unit=d.unit),
  'defaults',jsonb_build_object('replyTo',nullif(btrim(u.data->>'reply_to'),''),
    'tone',CASE WHEN u.data->>'communication_tone'='informal' THEN 'informal' ELSE 'formal' END,
    'remindersEnabled',coalesce((u.data->>'is_reminder_enabled')::boolean,true),
    'leadSeconds',coalesce((u.data->>'reminder_interval_seconds')::bigint,86400)),
  'unit',CASE WHEN manager THEN jsonb_build_object('id',u.id,'title',u.title,'data',u.data,'aggregate_version',coalesce(version,0)) ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_communication(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_communication(uuid) TO authenticated;
