DO $$
DECLARE result jsonb; org bigint; unit_id bigint; occasion_id bigint;
    form_key uuid := gen_random_uuid();
BEGIN
    INSERT INTO public.organizations(title) VALUES ('Ticket cap checkout fixture') RETURNING id INTO org;
    INSERT INTO public.units(organization,title) VALUES (org,'Ticket cap fixture') RETURNING id INTO unit_id;
    INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
        VALUES (org,unit_id,'Ticket cap fixture','ticket-cap-'||form_key,now(),now()+interval '1 day') RETURNING id INTO occasion_id;
    INSERT INTO public.forms(key,occasion,link,is_open)
        VALUES (form_key,occasion_id,'ticket-cap-'||form_key,true);
    IF public.ticket_order_limit() < 1 THEN
        RAISE EXCEPTION 'Global ticket cap must be positive';
    END IF;
    result := public.create_ticket_order_internal_v1(jsonb_build_object(
        'form', form_key,
        'ticket', (SELECT jsonb_agg('{}'::jsonb)
            FROM generate_series(1, public.ticket_order_limit() + 1))));
    IF result->>'code' <> '1023' THEN
        RAISE EXCEPTION 'Oversized order must fail before writing tickets: %', result;
    END IF;
    IF EXISTS (SELECT 1 FROM eshop.orders WHERE occasion=occasion_id)
       OR EXISTS (SELECT 1 FROM eshop.tickets WHERE occasion=occasion_id) THEN
        RAISE EXCEPTION 'Oversized checkout left an order or tickets behind';
    END IF;
    result := public.create_ticket_order_internal_v1(jsonb_build_object(
        'form', form_key,
        'ticket', (SELECT jsonb_agg('{}'::jsonb)
            FROM generate_series(1, public.ticket_order_limit()))));
    IF result->>'code' = '1023' THEN
        RAISE EXCEPTION 'Exactly the global cap must pass the count gate';
    END IF;
END $$;

DO $$
DECLARE actor uuid; org bigint; unit_id bigint; occ bigint; form_id bigint;
    result jsonb; payload jsonb; link text := 'ticket-limit-' || gen_random_uuid();
BEGIN
    PERFORM create_user_for_test('ticket-limit-editor', 'ticket-limit@example.invalid');
    actor := get_user_id('ticket-limit-editor');
    INSERT INTO public.organizations(title) VALUES ('Ticket limit test') RETURNING id INTO org;
    INSERT INTO public.units(organization,title) VALUES (org,'Ticket limit test') RETURNING id INTO unit_id;
    INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
        VALUES (org,unit_id,'Ticket limit test',link,now(),now()+interval '1 day') RETURNING id INTO occ;
    UPDATE public.user_info SET organization=org WHERE id=actor;
    INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor_view,is_editor)
        VALUES (occ,actor,true,true,true,true);
    PERFORM set_config('request.jwt.claim.sub',actor::text,true);
    PERFORM set_config('request.jwt.claim.role','authenticated',true);
    INSERT INTO public.forms(occasion,title,link) VALUES (occ,'Ticket limit',link) RETURNING id INTO form_id;
    payload := jsonb_build_object('id',form_id,'occasion',occ,'link',link,'title','Ticket limit',
        'form_fields', jsonb_build_array(jsonb_build_object('type','ticket','data',
            jsonb_build_object('max_tickets',public.ticket_order_limit()+1))));
    result := public.update_form_internal_v1(payload);
    IF result->>'code' <> '400' THEN
        RAISE EXCEPTION 'Form must reject oversized ticket setting: %', result;
    END IF;
    IF EXISTS (SELECT 1 FROM public.form_fields WHERE form=form_id) THEN
        RAISE EXCEPTION 'Rejected form settings must not persist fields';
    END IF;
    payload := jsonb_set(payload,'{form_fields,0,data,max_tickets}',to_jsonb(public.ticket_order_limit()));
    result := public.update_form_internal_v1(payload);
    IF result->>'code' <> '200' THEN
        RAISE EXCEPTION 'Form must allow exactly the global cap: %', result;
    END IF;
END $$;
