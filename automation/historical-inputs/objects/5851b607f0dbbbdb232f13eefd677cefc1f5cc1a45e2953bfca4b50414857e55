-- Shared content selector for both the editor and actual email preparation.
-- Callers authorize access and resolve/validate the hierarchy before calling.
CREATE OR REPLACE FUNCTION public.get_resolved_email_template(p_code text, p_context jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
  SELECT to_jsonb(et)
  FROM public.email_templates et
  WHERE et.code=p_code AND (
    ((p_context->>'occasion')::bigint IS NOT NULL AND et.occasion=(p_context->>'occasion')::bigint)
    OR ((p_context->>'unit')::bigint IS NOT NULL AND et.unit=(p_context->>'unit')::bigint AND et.occasion IS NULL)
    OR ((p_context->>'organization')::bigint IS NOT NULL AND et.organization=(p_context->>'organization')::bigint AND et.unit IS NULL AND et.occasion IS NULL)
    OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
  )
  ORDER BY
    CASE WHEN et.occasion IS NOT NULL THEN 1 WHEN et.unit IS NOT NULL THEN 2
         WHEN et.organization IS NOT NULL THEN 3 ELSE 4 END,
    CASE WHEN et.unit IS NOT DISTINCT FROM (p_context->>'unit')::bigint THEN 0 ELSE 1 END,
    CASE WHEN et.organization IS NOT DISTINCT FROM (p_context->>'organization')::bigint THEN 0 ELSE 1 END,
    et.id DESC
  LIMIT 1;
$$;
-- Invoker privileges retain table RLS; privileged callers own authorization.
REVOKE ALL ON FUNCTION public.get_resolved_email_template(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_resolved_email_template(text,jsonb) TO service_role;
