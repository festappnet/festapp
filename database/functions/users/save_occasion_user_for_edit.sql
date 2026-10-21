CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit_internal_v1(input_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion bigint := (input_data->>'occasion')::bigint;
    v_user uuid := (input_data->>'user')::uuid;
    v_unit bigint;
    v_data jsonb := CASE WHEN jsonb_typeof(input_data->'data') = 'object'
                         THEN input_data->'data' ELSE '{}'::jsonb END;
    v_services jsonb := CASE WHEN jsonb_typeof(input_data->'services') = 'object'
                             THEN input_data->'services' ELSE '{}'::jsonb END;
    v_catalog jsonb;
    v_existing_services jsonb;
    v_code text;
    v_global_before jsonb;
BEGIN
    SELECT o.unit,
           CASE WHEN jsonb_typeof(o.services) = 'object'
                THEN o.services ELSE '{}'::jsonb END
      INTO v_unit, v_catalog
      FROM public.occasions o
     WHERE o.id = v_occasion;

    IF v_unit IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion not found');
    END IF;

    -- Keep the write boundary at occasion management level. In particular,
    -- a unit editor must not gain the ability to assign manager/editor flags
    -- through this SECURITY DEFINER function.
    IF NOT public.get_is_manager_on_occasion(v_occasion)
       AND NOT public.get_is_admin_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Not authorized to update occasion users');
    END IF;

    SELECT CASE WHEN jsonb_typeof(ou.services) = 'object'
                THEN ou.services ELSE '{}'::jsonb END
      INTO v_existing_services
      FROM public.occasion_users ou
     WHERE ou.occasion = v_occasion AND ou."user" = v_user;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion user not found');
    END IF;

    -- Every assigned accommodation code must still exist in this occasion's
    -- catalog. This keeps the grid select and persisted service data aligned.
    FOR v_code IN
        SELECT key FROM jsonb_each(
            CASE WHEN jsonb_typeof(v_services->'accommodation') = 'object'
                 THEN v_services->'accommodation' ELSE '{}'::jsonb END
        )
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(
                  CASE WHEN jsonb_typeof(v_catalog->'accommodation') = 'array'
                       THEN v_catalog->'accommodation' ELSE '[]'::jsonb END
              ) item
             WHERE item->>'code' = v_code
        ) AND NOT COALESCE((
            -- Historical assignments can outlive a removed catalog item.
            -- Preserve such a code on unrelated edits, but never allow a new
            -- unknown code to be introduced.
            jsonb_typeof(v_existing_services->'accommodation') = 'object'
            AND (v_existing_services->'accommodation') ? v_code
        ), false) THEN
            RETURN jsonb_build_object('code', 400, 'message', 'Unknown accommodation code: ' || v_code);
        END IF;
    END LOOP;

    SELECT to_jsonb(ui) INTO v_global_before FROM public.user_info ui WHERE id=v_user FOR UPDATE;
    UPDATE public.user_info
       SET data = COALESCE(user_info.data, '{}'::jsonb)
                  || public.get_user_profile_data_patch(v_data),
           name = COALESCE(v_data->>'name', user_info.name),
           surname = COALESCE(v_data->>'surname', user_info.surname),
           sex = COALESCE(v_data->>'sex', user_info.sex),
           phone = CASE
               WHEN v_data ? 'phone' THEN v_data->>'phone'
               ELSE user_info.phone
           END,
           birth_date = CASE
               WHEN v_data ? 'birthDate'
                   THEN NULLIF(v_data->>'birthDate', '')::date
               ELSE user_info.birth_date
           END
     WHERE id = v_user;

    PERFORM public.publish_user_profile_change_internal_v1(v_user,v_occasion,v_global_before);

    UPDATE public.occasion_users
       SET data = v_data,
           -- A grid may edit only one service family. Merge top-level service
           -- keys so changing accommodation never erases food (and vice versa).
           -- An explicitly supplied empty object still clears that family.
           services = COALESCE(occasion_users.services, '{}'::jsonb) || v_services,
           role = CASE WHEN input_data ? 'role' THEN (input_data->>'role')::int ELSE role END,
           is_editor = COALESCE((input_data->>'is_editor')::boolean, is_editor),
           is_editor_view = COALESCE((input_data->>'is_editor_view')::boolean, is_editor_view),
           is_editor_order = COALESCE((input_data->>'is_editor_order')::boolean, is_editor_order),
           is_editor_order_view = COALESCE((input_data->>'is_editor_order_view')::boolean, is_editor_order_view),
           is_cleaning_crew = COALESCE((input_data->>'is_cleaning_crew')::boolean, is_cleaning_crew),
           is_cleaning_blocked = COALESCE((input_data->>'is_cleaning_blocked')::boolean, is_cleaning_blocked),
           is_receptionist = COALESCE((input_data->>'is_receptionist')::boolean, is_receptionist),
           is_approver = COALESCE((input_data->>'is_approver')::boolean, is_approver),
           is_approved = COALESCE((input_data->>'is_approved')::boolean, is_approved),
           is_manager = COALESCE((input_data->>'is_manager')::boolean, is_manager)
     WHERE occasion = v_occasion AND "user" = v_user;

    RETURN jsonb_build_object('code', 200, 'message', 'Occasion user updated');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$;

-- Released grid facade. Baseline is read under the membership lock.
CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint:=(input_data->>'occasion')::bigint; usr uuid:=(input_data->>'user')::uuid; ver bigint; r jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.get_is_manager_on_occasion(oc) OR public.get_is_admin_on_occasion(oc)) THEN RETURN jsonb_build_object('code',403); END IF;
 PERFORM 1 FROM public.user_info WHERE id=usr FOR UPDATE;
 PERFORM 1 FROM public.occasion_users WHERE occasion=oc AND "user"=usr FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404); END IF;
 SELECT coalesce(v.version,0) INTO ver FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=usr::text;
 input_data:=jsonb_set(input_data,'{data}',CASE WHEN jsonb_typeof(input_data->'data')='object' THEN (input_data->'data')-'is_invited' ELSE '{}' END);
 r:=public.save_profile_client_sync_v1(oc,usr,extensions.gen_random_uuid(),ver,input_data);
 RETURN jsonb_build_object('code',r->'code','message',r#>'{data,message}');
END $$;
REVOKE ALL ON FUNCTION public.save_occasion_user_for_edit_internal_v1(jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_occasion_user_for_edit(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_user_for_edit(jsonb) TO authenticated;
