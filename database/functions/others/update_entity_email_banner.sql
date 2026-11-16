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
