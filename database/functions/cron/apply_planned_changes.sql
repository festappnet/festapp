-- The canonical entrypoint retains Client Sync v1 delivery.
CREATE OR REPLACE FUNCTION public.apply_planned_changes_client_sync_v1()
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_candidate record; v_change eshop.planned_changes%ROWTYPE;
  v_product eshop.products%ROWTYPE; v_occasion bigint; v_impacts jsonb; v_changed integer;
  v_failure text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  -- Serializes workers, including backlog across multiple instants of one product.
  IF NOT pg_try_advisory_xact_lock(7310420261004::bigint) THEN RETURN; END IF;
  FOR v_candidate IN SELECT id,subject_id,change_type FROM eshop.planned_changes
    WHERE change_time<=now() AND NOT applied AND failed_at IS NULL ORDER BY change_time,id
  LOOP
    -- Same lock order as editor commands: subject, then plan. Recheck after lock.
    IF v_candidate.change_type IN ('products.price','products.is_hidden') THEN
      PERFORM 1 FROM eshop.products WHERE id=v_candidate.subject_id FOR UPDATE;
    ELSIF v_candidate.change_type='forms.is_open' THEN
      PERFORM 1 FROM public.forms WHERE id=v_candidate.subject_id FOR UPDATE;
    END IF;
    SELECT * INTO v_change FROM eshop.planned_changes WHERE id=v_candidate.id FOR UPDATE;
    IF NOT FOUND OR v_change.applied OR v_change.failed_at IS NOT NULL OR v_change.change_time>now() THEN CONTINUE; END IF;
    BEGIN
      v_changed:=0; v_occasion:=NULL; v_impacts:='[]'::jsonb;
      IF v_change.change_type IN ('products.price','products.is_hidden') THEN
        SELECT * INTO v_product FROM eshop.products WHERE id=v_change.subject_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SUBJECT'; END IF;
        SELECT occasion INTO v_occasion FROM eshop.product_types WHERE id=v_product.product_type;
        IF v_occasion IS NULL OR v_change.occasion IS DISTINCT FROM v_occasion
          OR v_product.occasion IS DISTINCT FROM v_occasion THEN RAISE EXCEPTION 'INVALID_OCCASION'; END IF;
        IF v_change.change_type='products.price' THEN
          PERFORM public.validate_product_price(v_change.new_value::numeric,v_product.data,v_product.currency_code);
          UPDATE eshop.products SET price=v_change.new_value::numeric,updated_at=now()
          WHERE id=v_change.subject_id AND price IS DISTINCT FROM v_change.new_value::numeric;
        ELSE
          UPDATE eshop.products SET is_hidden=v_change.new_value::boolean,updated_at=now()
          WHERE id=v_change.subject_id AND is_hidden IS DISTINCT FROM v_change.new_value::boolean;
        END IF;
        GET DIAGNOSTICS v_changed=ROW_COUNT;
      ELSIF v_change.change_type='forms.is_open' THEN
        SELECT occasion INTO v_occasion FROM public.forms WHERE id=v_change.subject_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SUBJECT'; END IF;
        IF v_occasion IS NULL OR v_change.occasion IS DISTINCT FROM v_occasion THEN RAISE EXCEPTION 'INVALID_OCCASION'; END IF;
        UPDATE public.forms SET is_open=v_change.new_value::boolean WHERE id=v_change.subject_id;
      ELSE RAISE EXCEPTION 'UNKNOWN_CHANGE_TYPE'; END IF;
      IF v_changed>0 THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory','userId',ou."user")),'[]'::jsonb)
          INTO v_impacts FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
          ON ou.ticket=opt.ticket AND ou.occasion=v_occasion WHERE opt.product=v_change.subject_id;
        PERFORM public.record_client_sync_commit_v1(v_occasion,
          'inventory.product.planned','inventory',jsonb_build_array(jsonb_build_object(
          'entityType','product','entityId',v_change.subject_id,'operation','update',
          'safeLabel','Scheduled product change','changedFields',jsonb_build_array(split_part(v_change.change_type,'.',2)))),
          '{}',v_impacts,'[]','service','planned_change:'||v_change.id::text);
      END IF;
      UPDATE eshop.planned_changes SET applied=true,revision=revision+1 WHERE id=v_change.id;
    EXCEPTION WHEN OTHERS THEN
      -- This subtransaction rolls back price AND sync on any failure.
      v_failure := CASE WHEN SQLERRM IN ('INVALID_SUBJECT','INVALID_OCCASION','UNKNOWN_CHANGE_TYPE',
        'INVALID_PRODUCT_PRICE','DEPOSIT_AMOUNT_TOO_HIGH') THEN SQLERRM
        WHEN SQLSTATE IN ('22P02','22003') THEN 'INVALID_VALUE' ELSE 'APPLICATION_FAILED' END;
      UPDATE eshop.planned_changes SET failed_at=clock_timestamp(),failure_code=v_failure,revision=revision+1 WHERE id=v_change.id;
    END;
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.apply_planned_changes_client_sync_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes_client_sync_v1() TO service_role;
CREATE OR REPLACE FUNCTION public.apply_planned_changes()
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT public.apply_planned_changes_client_sync_v1();
$$;
REVOKE ALL ON FUNCTION public.apply_planned_changes() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes() TO service_role;
