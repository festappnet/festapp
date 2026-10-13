CREATE OR REPLACE FUNCTION public.get_email_template_and_wrapper(p_code text, p_context jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  result jsonb;
  email_template jsonb;
  email_wrapper jsonb;
  v_occ bigint;
  v_unit bigint;
  v_org bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
BEGIN
  -- Extract context values. The ->> operator handles missing keys by returning SQL NULL.
  v_occ := (p_context->>'occasion')::bigint;
  v_unit := (p_context->>'unit')::bigint;
  v_org  := (p_context->>'organization')::bigint;

  -- Resolve ancestors even for an occasion-only context. Missing IDs must never
  -- become wildcards that select another occasion's template or wrapper.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org FROM public.occasions WHERE id=v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
       OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE EXCEPTION 'Invalid email template hierarchy';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id=v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE EXCEPTION 'Invalid email template hierarchy';
    END IF;
    v_org := v_actual_org;
  END IF;

  email_template := public.get_resolved_email_template(p_code, jsonb_build_object(
    'occasion',v_occ,'unit',v_unit,'organization',v_org));

  -- Retrieve the most specific email wrapper using the same logic.
  SELECT to_jsonb(t)
  INTO email_wrapper
  FROM (
    SELECT
      ew.id,
      ew.title,
      ew.organization,
      ew.unit,
      ew.html,
      ew.created_at
    FROM public.email_wrappers ew
    WHERE (
      (v_occ IS NOT NULL AND ew.occasion=v_occ)
      OR (v_unit IS NOT NULL AND ew.unit=v_unit AND ew.occasion IS NULL)
      OR (v_org IS NOT NULL AND ew.organization=v_org AND ew.unit IS NULL AND ew.occasion IS NULL)
      OR (ew.organization IS NULL AND ew.unit IS NULL AND ew.occasion IS NULL)
    )
    ORDER BY
         CASE WHEN ew.occasion IS NOT DISTINCT FROM v_occ THEN 0 ELSE 1 END,
         CASE WHEN ew.unit IS NOT DISTINCT FROM v_unit THEN 0 ELSE 1 END,
         CASE WHEN ew.organization IS NOT DISTINCT FROM v_org THEN 0 ELSE 1 END,
         ew.id
    LIMIT 1
  ) t;

  -- Build the final result object, ensuring JSON nulls are used for missing records.
  result := jsonb_build_object(
              'template', COALESCE(email_template, 'null'::jsonb),
              'wrapper',  COALESCE(email_wrapper, 'null'::jsonb)
            );
  RETURN result;
END;
$$;