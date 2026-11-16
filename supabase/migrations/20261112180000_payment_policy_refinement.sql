-- Payment policy refinement: explicit authoring invalidates only actual changes.

-- SOURCE: others/update_email_template.sql
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
  v_changed bigint;
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
    IF NOT public.is_service_role() AND public.can_write_occasion_email_templates(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Occasion template write denied';
    END IF;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id=v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE='Invalid email template hierarchy';
    END IF;
    v_org := v_actual_org;
    IF NOT public.is_service_role() AND public.can_write_unit_email_templates(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Unit template write denied';
    END IF;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.can_manage_organization_email_templates(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE='Organization template write denied';
    END IF;
  END IF;

  PERFORM public.lock_email_template_hierarchy_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org));

  PERFORM public.validate_email_template_content_internal(v_code,p_data->>'html');

  -- An occasion override is identified by occasion + code. Ancestors are
  -- metadata, not identity; the partial unique index also fences concurrent saves.
  IF v_occ IS NOT NULL THEN
    INSERT INTO public.email_templates (html, occasion, subject, organization, code, unit, title)
    VALUES (p_data->>'html', v_occ, p_data->>'subject', v_org, v_code, v_unit, p_data->>'title')
    ON CONFLICT (occasion, code) WHERE occasion IS NOT NULL
    DO UPDATE SET html=EXCLUDED.html, subject=EXCLUDED.subject, title=EXCLUDED.title,
                  unit=EXCLUDED.unit, organization=EXCLUDED.organization
    WHERE (email_templates.html,email_templates.subject,email_templates.title,email_templates.unit,email_templates.organization)
      IS DISTINCT FROM (EXCLUDED.html,EXCLUDED.subject,EXCLUDED.title,EXCLUDED.unit,EXCLUDED.organization);
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org),true);
    END IF;
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
    WHERE id = v_existing_id AND (html,subject,title) IS DISTINCT FROM (p_data->>'html',p_data->>'subject',p_data->>'title');
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
  GET DIAGNOSTICS v_changed=ROW_COUNT;
  IF v_changed>0 THEN
    PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',v_occ,'unit',v_unit,'organization',v_org),true);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_email_template(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_email_template(jsonb) TO authenticated, service_role;

-- SOURCE: others/delete_entity_email_template.sql
create or replace function public.delete_entity_email_template(p_entity_type text, p_entity_id bigint, p_code text)
    returns void
    language plpgsql
    security definer
SET search_path = public, extensions
as
$$
declare
    v_changed bigint;
begin
    if p_entity_type = 'occasion' then
        if public.can_write_occasion_email_templates(p_entity_id) IS NOT TRUE then
            perform public.raise_error('permission_denied');
        end if;

        PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
          (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
          ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

        delete from public.email_templates
        where occasion = p_entity_id 
          and code = p_code;

    elsif p_entity_type = 'unit' then
        if (public.can_write_unit_email_templates(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

        PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
          (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
          ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

        delete from public.email_templates
        where unit = p_entity_id
          and occasion is null
          and code = p_code;
    else
        raise exception 'Invalid entity type: %', p_entity_type;
    end if;
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object(p_entity_type,p_entity_id),true);
    END IF;
end;
$$;

-- SOURCE: others/update_entity_email_banner.sql
-- null inherits the existing wrapper; empty text explicitly suppresses its image.
CREATE OR REPLACE FUNCTION public.email_banner_wrapper_internal(p_banner_url text,p_title text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_banner_url IS NULL THEN NULL ELSE
  '<div style="font-family: Arial, sans-serif; font-size: 16px; max-width: 680px; margin: 0 auto;">'
  ||CASE WHEN p_banner_url='' THEN '' ELSE '<div style="text-align: center;"><img src="'
    ||replace(replace(replace(replace(p_banner_url,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;')
    ||'" alt="'||replace(replace(replace(replace(coalesce(p_title,'Banner'),'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;')
    ||'" style="width: 100%; height: auto; display: block;"></div>' END
  ||'<div style="margin-top: 10px; margin-bottom: 10px; padding: 0 24px;">{{content}}</div></div>' END;
$$;
REVOKE ALL ON FUNCTION public.email_banner_wrapper_internal(text,text) FROM PUBLIC,anon,authenticated,service_role;

create or replace function public.update_entity_email_banner(p_entity_type text, p_entity_id bigint, p_banner_url text)
    returns void
    language plpgsql
    security definer
SET search_path = public, extensions
as
$$
declare
    v_org_id bigint;
    v_entity_title text;
    v_new_html text;
    v_before jsonb;
    v_changed bigint;
begin
    -- Authorize before taking private policy or hierarchy locks.
    IF p_entity_type='occasion' THEN
      IF public.can_write_occasion_email_templates(p_entity_id) IS NOT TRUE THEN
        PERFORM public.raise_error('permission_denied'); END IF;
    ELSIF p_entity_type='unit' THEN
      IF public.can_write_unit_email_templates(p_entity_id) IS NOT TRUE THEN
        PERFORM public.raise_error('permission_denied'); END IF;
    ELSE RAISE EXCEPTION 'Invalid entity type: %',p_entity_type;
    END IF;
    PERFORM public.lock_email_template_hierarchy_internal(CASE WHEN p_entity_type='occasion' THEN
      (SELECT jsonb_build_object('occasion',id,'unit',unit,'organization',organization) FROM public.occasions WHERE id=p_entity_id)
      ELSE (SELECT jsonb_build_object('unit',id,'organization',organization) FROM public.units WHERE id=p_entity_id) END);

    if p_entity_type = 'occasion' then
        SELECT data INTO v_before FROM public.occasions WHERE id=p_entity_id FOR UPDATE;
        -- Update Occasion Data
        update public.occasions
        set data = jsonb_set(coalesce(data, '{}'), '{email_banner}', coalesce(to_jsonb(p_banner_url),'null'::jsonb))
        where id = p_entity_id
        returning organization, title into v_org_id, v_entity_title;

    elsif p_entity_type = 'unit' then
        SELECT data INTO v_before FROM public.units WHERE id=p_entity_id FOR UPDATE;
        -- Update Unit Data
        update public.units
        set data = jsonb_set(coalesce(data, '{}'), '{email_banner}', coalesce(to_jsonb(p_banner_url),'null'::jsonb))
        where id = p_entity_id
        returning organization, title into v_org_id, v_entity_title;

    else
        raise exception 'Invalid entity type: %', p_entity_type;
    end if;

    IF v_before IS DISTINCT FROM (CASE WHEN p_entity_type='occasion'
      THEN (SELECT data FROM public.occasions WHERE id=p_entity_id)
      ELSE (SELECT data FROM public.units WHERE id=p_entity_id) END) THEN
      INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES(p_entity_type,p_entity_type,p_entity_id,p_entity_id::text,1)
      ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
      SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
    END IF;

    -- 2. Handle HTML Wrapper Logic
    if p_banner_url is not null then
        v_new_html := public.email_banner_wrapper_internal(p_banner_url, v_entity_title);

        -- Upsert Wrapper
        if p_entity_type = 'occasion' then
             -- For occasion, check existing wrapper
            if exists (select 1 from public.email_wrappers where occasion = p_entity_id) then
                update public.email_wrappers set html = v_new_html where occasion = p_entity_id AND html IS DISTINCT FROM v_new_html;
            else
                insert into public.email_wrappers (occasion, organization, unit, title, html)
                values (p_entity_id, v_org_id, (select unit from occasions where id = p_entity_id), 'Occasion Banner Wrapper', v_new_html);
            end if;
        elsif p_entity_type = 'unit' then
             -- For unit (occasion is null)
            if exists (select 1 from public.email_wrappers where unit = p_entity_id and occasion is null) then
                update public.email_wrappers set html = v_new_html where unit = p_entity_id and occasion is null AND html IS DISTINCT FROM v_new_html;
            else
                insert into public.email_wrappers (occasion, organization, unit, title, html)
                values (null, v_org_id, p_entity_id, 'Unit Banner Wrapper', v_new_html);
            end if;
        end if;
    else
        -- 3. Banner Removed -> Delete Wrapper
        if p_entity_type = 'occasion' then
            delete from public.email_wrappers where occasion = p_entity_id;
        elsif p_entity_type = 'unit' then
            delete from public.email_wrappers where unit = p_entity_id and occasion is null;
        end if;
    end if;
    GET DIAGNOSTICS v_changed=ROW_COUNT;
    IF v_changed>0 THEN
      PERFORM public.payment_template_write_scope_internal(jsonb_build_object(p_entity_type,p_entity_id),true);
    END IF;
end;
$$;

REVOKE ALL ON FUNCTION public.update_entity_email_banner(text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_entity_email_banner(text,bigint,text) TO authenticated;
