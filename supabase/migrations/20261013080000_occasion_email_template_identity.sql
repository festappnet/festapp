-- Keep the override under current ancestry, then the newest ID. Only the
-- vstupenky.online tenant has known duplicates. Refuse an unreviewed other-tenant repair.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.email_templates et JOIN public.occasions o ON o.id=et.occasion
    GROUP BY et.occasion,et.code,o.organization
    HAVING count(*)>1 AND o.organization IS DISTINCT FROM 3
  ) THEN
    RAISE EXCEPTION 'Unreviewed email template duplicates outside organization 3';
  END IF;
END $$;
WITH ranked AS (
  SELECT et.id, row_number() OVER (
    PARTITION BY et.occasion,et.code
    ORDER BY (et.unit IS NOT DISTINCT FROM o.unit) DESC,
             (et.organization IS NOT DISTINCT FROM o.organization) DESC,et.id DESC
  ) AS priority
  FROM public.email_templates et JOIN public.occasions o ON o.id=et.occasion
  WHERE o.organization=3
)
DELETE FROM public.email_templates et USING ranked r WHERE et.id=r.id AND r.priority>1;
CREATE UNIQUE INDEX IF NOT EXISTS email_templates_occasion_code_unique
  ON public.email_templates(occasion,code) WHERE occasion IS NOT NULL;

-- Shared content selector for both the editor and actual email preparation.
-- Callers authorize access and resolve/validate the hierarchy before calling.
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

  -- An occasion override is identified by occasion + code. Ancestors are
  -- metadata, not identity; the partial unique index also fences concurrent saves.
  IF v_occ IS NOT NULL THEN
    INSERT INTO public.email_templates (html, occasion, subject, organization, code, unit, title)
    VALUES (p_data->>'html', v_occ, p_data->>'subject', v_org, v_code, v_unit, p_data->>'title')
    ON CONFLICT (occasion, code) WHERE occasion IS NOT NULL
    DO UPDATE SET html=EXCLUDED.html, subject=EXCLUDED.subject, title=EXCLUDED.title,
                  unit=EXCLUDED.unit, organization=EXCLUDED.organization;
    RETURN;
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

CREATE OR REPLACE FUNCTION public.get_all_email_templates(p_context jsonb)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  email_data jsonb;
  v_occ  bigint;
  v_unit bigint;
  v_org  bigint;

  v_effective_org bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
  is_app_supported boolean := false;
BEGIN
  -- 1. Extract context values from the JSON parameter
  v_occ  := CASE
              WHEN p_context ? 'occasion' AND (p_context->>'occasion') IS NOT NULL
              THEN (p_context->>'occasion')::bigint
              ELSE NULL
            END;
  v_unit := CASE
              WHEN p_context ? 'unit' AND (p_context->>'unit') IS NOT NULL
              THEN (p_context->>'unit')::bigint
              ELSE NULL
            END;
  v_org  := CASE
              WHEN p_context ? 'organization' AND (p_context->>'organization') IS NOT NULL
              THEN (p_context->>'organization')::bigint
              ELSE NULL
            END;

  -- Resolve ancestors from the requested object; never trust mixed tenant IDs.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org
    FROM public.occasions WHERE id = v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_editor_view_on_occasion(v_occ) IS NOT TRUE
       AND public.get_is_editor_order_view_on_occasion(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Occasion template access denied';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id = v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_manager_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_view_on_unit(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Unit template access denied';
    END IF;
    v_org := v_actual_org;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.get_is_admin_on_organization(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Organization template access denied';
    END IF;
  END IF;
  v_effective_org := v_org;

  -- 3. Check if App is Supported for the effective organization
  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
  END IF;

  -- 5. Retrieve email templates
  SELECT jsonb_agg(public.get_resolved_email_template(result.code,
    jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org)) ORDER BY result.code)
    INTO email_data
  FROM (
    SELECT DISTINCT et.code
    FROM public.email_templates et
    WHERE
      -- A. Filter based on context (Scope)
      (
           (v_occ IS NOT NULL AND et.occasion = v_occ)
        OR (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL)
        OR (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL)
        OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
      )
      -- B. Filter based on App Support (New Logic)
      AND (
        is_app_supported IS TRUE
        OR
        et.code NOT IN ('SIGN_IN_CODE', 'RESET_PASSWORD', 'APP_LINKS',
                        'ACCOUNT_DELETION_CONFIRM', 'ACCOUNT_DELETION_COMPLETE')
      )
  ) result;

  IF email_data IS NULL THEN
    email_data := '[]'::jsonb;
  END IF;

  RETURN email_data;
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_email_templates(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_email_templates(jsonb) TO authenticated, service_role;

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
NOTIFY pgrst, 'reload schema';
