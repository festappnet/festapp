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
begin
    -- 1. Validate Entity Type and Permissions
    if p_entity_type = 'occasion' then
        if (public.get_is_editor_on_occasion(p_entity_id) IS NOT TRUE
            AND public.get_is_editor_order_on_occasion(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

        SELECT data INTO v_before FROM public.occasions WHERE id=p_entity_id FOR UPDATE;
        -- Update Occasion Data
        update public.occasions
        set data = jsonb_set(coalesce(data, '{}'), '{email_banner}', coalesce(to_jsonb(p_banner_url),'null'::jsonb))
        where id = p_entity_id
        returning organization, title into v_org_id, v_entity_title;

    elsif p_entity_type = 'unit' then
        if (public.get_is_editor_on_unit(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

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
        -- Construct Custom HTML
        v_new_html := '<div style="font-family: Arial, sans-serif; font-size: 16px; max-width: 680px; margin: 0 auto;">';
        v_new_html := v_new_html || '<div style="text-align: center;">';
        v_new_html := v_new_html || '<img src="' || p_banner_url || '" alt="' || coalesce(v_entity_title, 'Banner') || '" style="width: 100%; height: auto; display: block;">';
        v_new_html := v_new_html || '</div>';
        v_new_html := v_new_html || '<div style="margin-top: 10px; margin-bottom: 10px;">';
        v_new_html := v_new_html || '{{content}}';
        v_new_html := v_new_html || '</div></div>';

        -- Upsert Wrapper
        if p_entity_type = 'occasion' then
             -- For occasion, check existing wrapper
            if exists (select 1 from public.email_wrappers where occasion = p_entity_id) then
                update public.email_wrappers set html = v_new_html where occasion = p_entity_id;
            else
                insert into public.email_wrappers (occasion, organization, unit, title, html)
                values (p_entity_id, v_org_id, (select unit from occasions where id = p_entity_id), 'Occasion Banner Wrapper', v_new_html);
            end if;
        elsif p_entity_type = 'unit' then
             -- For unit (occasion is null)
            if exists (select 1 from public.email_wrappers where unit = p_entity_id and occasion is null) then
                update public.email_wrappers set html = v_new_html where unit = p_entity_id and occasion is null;
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
end;
$$;

REVOKE ALL ON FUNCTION public.update_entity_email_banner(text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_entity_email_banner(text,bigint,text) TO authenticated;
