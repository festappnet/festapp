-- Canonical source: database/functions/others/update_email_template.sql
CREATE OR REPLACE FUNCTION public.update_email_template(p_data jsonb)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  v_occ   bigint;
  v_unit  bigint;
  v_org   bigint;
  v_code  text;
  v_existing_id bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
BEGIN
  -- Extract values from input JSON.
  v_occ  := CASE WHEN p_data ? 'occasion' THEN (p_data ->> 'occasion')::bigint ELSE NULL END;
  v_unit := CASE WHEN p_data ? 'unit' THEN (p_data ->> 'unit')::bigint ELSE NULL END;
  v_org := (p_data ->> 'organization')::bigint;
  v_code := p_data ->> 'code';

  -- Resolve the actual hierarchy before authorizing template writes.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org FROM public.occasions WHERE id=v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE='Invalid email template hierarchy';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
    IF NOT public.is_service_role() AND public.get_is_editor_on_occasion(v_occ) IS NOT TRUE
       AND public.get_is_editor_order_on_occasion(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Occasion template write denied';
    END IF;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id=v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE='Invalid email template hierarchy';
    END IF;
    v_org := v_actual_org;
    IF NOT public.is_service_role() AND public.get_is_editor_on_unit(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Unit template write denied';
    END IF;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.get_is_admin_on_organization(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Organization template write denied';
    END IF;
  END IF;

  -- Try to find an existing email template matching the given context and code.
  SELECT id
    INTO v_existing_id
  FROM public.email_templates
  WHERE
    ((occasion = v_occ) OR (occasion IS NULL AND v_occ IS NULL))
    AND ((unit = v_unit) OR (unit IS NULL AND v_unit IS NULL))
    AND ((organization = v_org) OR (organization IS NULL AND v_org IS NULL))
    AND code = v_code
  LIMIT 1;

  IF FOUND THEN
    -- Update the existing record.
    UPDATE public.email_templates
    SET
      html    = p_data ->> 'html',
      subject = p_data ->> 'subject',
      title   = p_data ->> 'title'
    WHERE id = v_existing_id;
  ELSE
    -- Insert a new record.
    INSERT INTO public.email_templates (
      html,
      occasion,
      subject,
      organization,
      code,
      unit,
      title
    )
    VALUES (
      p_data ->> 'html',
      v_occ,
      p_data ->> 'subject',
      v_org,
      v_code,
      v_unit,
      p_data ->> 'title'
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_email_template(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_email_template(jsonb) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
