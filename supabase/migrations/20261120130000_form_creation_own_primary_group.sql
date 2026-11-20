-- A new form owns a fresh primary admission group; a form bound to the seating plan shares the plan's group.

-- SOURCE: eshop_forms/form_creation_domain.sql
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    seat_blueprint BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true,"design":{"presale_header":"event_and_date"}}'::jsonb;
BEGIN
    SELECT public.resolve_payment_method_policy_internal(o.organization,o.unit)->>'preferredMethod' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default='cash' THEN
      initial_data := initial_data || '{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}'::jsonb;
    ELSIF public.payment_method_is_online_internal(payment_default) THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    IF NOT (initial_data ? 'payments') THEN initial_data:=initial_data||jsonb_build_object('payments',jsonb_build_object('bankEnabled',payment_default='bank' AND public.payment_method_policy_enabled_internal((SELECT unit FROM public.occasions WHERE id=p_occasion_id),'bank'))); END IF;
    -- Same scope lock, taken first, as other form/product/plan writers.
    PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion_id]);
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        NULL, -- New forms inherit the occasion policy; legacy stored durations stay custom.
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Seated occasions bind the occasion plan first: all its forms sell the same seats.
    IF EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion_id AND
      jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
      INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order")
      VALUES(new_form_id,'spot',true,true,false,-1);
      PERFORM public.sync_form_blueprint_internal(new_form_id);
      SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;
      seat_blueprint := (new_form->>'blueprint')::bigint;
    END IF;

    IF seat_blueprint IS NOT NULL THEN
      -- Reuse the plan's admission group deterministically: the 'spot' group of
      -- most products bound to its seats/areas (as blueprint_form_products_internal
      -- offers them), lowest ID on ties. No unseated starter beside the plan.
      SELECT p.product_type INTO new_product_type_id
      FROM (SELECT s.product FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
            WHERE sb.blueprint=seat_blueprint AND s.blueprint=seat_blueprint AND s.occasion=p_occasion_id
            UNION ALL
            SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=seat_blueprint) bound
      JOIN eshop.products p ON p.id=bound.product AND p.occasion=p_occasion_id
      JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot' AND pt.occasion=p_occasion_id
      -- The primary-product guard below requires a visible variant.
      WHERE EXISTS(SELECT 1 FROM eshop.products v WHERE v.product_type=pt.id AND NOT v.is_hidden)
      GROUP BY p.product_type ORDER BY count(*) DESC, p.product_type LIMIT 1;
    END IF;

    IF new_product_type_id IS NULL THEN
      -- Otherwise (no plan, or a plan without bound admission products) every new
      -- form owns a fresh primary group and starter variant.
      -- Never bind another form's group: it would share live stock and orders.
      INSERT INTO eshop.product_types(title, type, occasion)
      VALUES ('Spot', 'spot', p_occasion_id)
      RETURNING id INTO new_product_type_id;

      INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
      VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    PERFORM public.assert_form_primary_products_internal(new_form_id);

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;
