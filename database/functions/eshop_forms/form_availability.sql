-- Sole owner of the manual/time gate, including the legacy inclusive end.
CREATE OR REPLACE FUNCTION public.get_form_availability_from_config_internal(p_config jsonb,p_at timestamptz)
RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH c AS (SELECT (p_config->>'manualOpen')::boolean manual_open,
 (p_config->>'startAt')::timestamptz start_at,(p_config->>'endAt')::timestamptz end_at), gate AS (
 SELECT *,CASE WHEN NOT manual_open THEN 'manual_closed' WHEN p_at<start_at THEN 'before_start'
 WHEN p_at>end_at THEN 'ended' ELSE 'open' END value FROM c)
 SELECT p_config||jsonb_build_object('gate',value,'isWindowOpen',value='open','nextEvaluationAt',
 CASE WHEN manual_open IS NOT FALSE THEN (SELECT min(t) FROM (VALUES(start_at),(end_at+interval '1 microsecond')) b(t) WHERE t>p_at) END) FROM gate;
$$;
CREATE OR REPLACE FUNCTION public.get_form_availability_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.get_form_availability_from_config_internal(jsonb_build_object('manualOpen',f.is_open,
 'startAt',nullif(coalesce(d#>>'{schedule,start_time}',d->>'start_time'),'')::timestamptz,
 'endAt',nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz),p_at)
 FROM public.forms f CROSS JOIN LATERAL (SELECT public.get_effective_form_data(f.id) d) data WHERE f.id=p_form;
$$;
REVOKE ALL ON FUNCTION public.get_form_availability_from_config_internal(jsonb,timestamptz),
 public.get_form_availability_snapshot_internal(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
