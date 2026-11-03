create or replace function public.delete_entity_email_template(p_entity_type text, p_entity_id bigint, p_code text)
    returns void
    language plpgsql
    security definer
SET search_path = public, extensions
as
$$
begin
    if p_entity_type = 'occasion' then
        if (public.get_is_editor_on_occasion(p_entity_id) IS NOT TRUE 
            AND public.get_is_editor_order_on_occasion(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

        delete from public.email_templates
        where occasion = p_entity_id 
          and code = p_code;

    elsif p_entity_type = 'unit' then
        if (public.get_is_editor_on_unit(p_entity_id) IS NOT TRUE) then
            perform public.raise_error('permission_denied');
        end if;

        delete from public.email_templates
        where unit = p_entity_id
          and occasion is null
          and code = p_code;
    else
        raise exception 'Invalid entity type: %', p_entity_type;
    end if;
end;
$$;
