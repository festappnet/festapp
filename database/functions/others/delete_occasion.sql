CREATE OR REPLACE FUNCTION public.delete_occasion_internal_v1(oc bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_id BIGINT;
BEGIN
  PERFORM public.check_occasion_writable(oc);

  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = oc;

  IF NOT public.can_delete_occasion_in_unit(unit_id) THEN RAISE EXCEPTION 'User is not manager.'; END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=oc));

-- ***********************************************************
  -- 0. SAFETY CHECK: Strict Order Check
  --    Prevent deletion if ANY order exists (even storno).
  -- ***********************************************************
  IF EXISTS (
      SELECT 1
      FROM eshop.orders
      WHERE occasion = oc
  ) THEN
      RAISE EXCEPTION 'Cannot delete occasion % because it contains orders (including storno).', oc;
  END IF;

  -- ***********************************************************
  -- 1. Delete records that depend on 'events'.
  -- ***********************************************************
  PERFORM public.lock_blueprint_scope_internal(ARRAY[oc]);
  DELETE FROM public.form_seating_transitions WHERE occasion=oc;
  DELETE FROM public.scanner_settings WHERE occasion_id=oc;

  DELETE FROM public.event_groups
    WHERE event_parent IN (SELECT id FROM public.events WHERE occasion = oc)
       OR event_child  IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_roles
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users_saved
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.exclusive_events
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  -- ***********************************************************
  -- 2. Delete the 'events' themselves.
  -- ***********************************************************
  DELETE FROM public.events
    WHERE occasion = oc;

  -- ***********************************************************
  -- 3. Delete 'orders' dependent records.
  -- ***********************************************************
  DELETE FROM eshop.order_product_ticket
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.orders_history
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.bank_account_requests
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  -- ***********************************************************
  -- 4. Delete form-related records.
  -- ***********************************************************
  DELETE FROM public.form_fields
    WHERE form IN (SELECT id FROM public.forms WHERE occasion = oc);

  DELETE FROM public.notification_center_source_state WHERE source_key LIKE 'form-availability:%'
    AND (state->>'formId')::bigint IN (SELECT id FROM public.forms WHERE occasion=oc);
  DELETE FROM public.forms
    WHERE occasion = oc;

  -- ***********************************************************
  -- 5. Delete records from tables that reference the occasion directly.
  -- ***********************************************************
  DELETE FROM public.email_templates
    WHERE occasion = oc;

  DELETE FROM public.email_wrappers
    WHERE occasion = oc;

  DELETE FROM public.information
    WHERE occasion = oc;

  DELETE FROM public.information_hidden
    WHERE occasion = oc;

  DELETE FROM public.log_notifications
    WHERE occasion = oc;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='occasion_deleted',data='{}',prepared=NULL,recipient=NULL,occasion=NULL,unit=NULL
    WHERE occasion = oc;

  DELETE FROM public.log_emails
    WHERE occasion = oc;

  DELETE FROM public.news
    WHERE occasion = oc;

  DELETE FROM public.occasion_users
    WHERE occasion = oc;

  DELETE FROM public.user_news
    WHERE occasion = oc;

  -- Resources can reference places and own slots referenced by copied spots.
  -- Remove them before places; slot references detach through their FK rules.
  DELETE FROM public.resources
    WHERE occasion = oc OR inventory_pool IN (
      SELECT id FROM public.inventory_pools WHERE occasion = oc);

  DELETE FROM public.places
    WHERE occasion = oc;

  DELETE FROM public.role_info
    WHERE occasion = oc;

  DELETE FROM public.user_groups
    WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion = oc);

  DELETE FROM public.user_group_info
    WHERE occasion = oc;

  DELETE FROM public.exclusive_groups
    WHERE occasion = oc;

  -- ***********************************************************
  -- 6. Delete remaining records from the eshop schema.
  -- ***********************************************************
  DELETE FROM eshop.tickets
    WHERE occasion = oc;

  -- Configuration bindings depend on seats/products as well as their plan.
  DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_group_products WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);

  DELETE FROM eshop.spots
    WHERE occasion = oc;

  DELETE FROM eshop.products
    WHERE occasion = oc;

  DELETE FROM eshop.product_types
    WHERE occasion = oc;

  DELETE FROM eshop.planned_changes
    WHERE occasion = oc;

  DELETE FROM eshop.bank_account_requests
    WHERE occasion = oc;


  DELETE FROM eshop.blueprints
    WHERE occasion = oc;

  -- Blueprint area bindings and product mappings no longer retain contexts.
  DELETE FROM public.inventory_contexts
    WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion = oc);
  DELETE FROM public.inventory_pools
    WHERE occasion = oc;

  -- Delete orders (Safe now: we checked for non-storno orders at step 0,
  -- and deleted dependents in step 3).
  DELETE FROM eshop.orders
    WHERE occasion = oc;

  -- ***********************************************************
  -- 7. Null out referencing images.
  -- ***********************************************************
  UPDATE public.images
    SET occasion = NULL
    WHERE occasion = oc;

  -- ***********************************************************
  -- 8. Finally, delete the occasion itself.
  -- ***********************************************************
  DELETE FROM public.occasions
    WHERE id = oc;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_occasion_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_occasion(oc bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN
  PERFORM public.delete_occasion_client_sync_v1(oc,extensions.gen_random_uuid());
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion(bigint) TO authenticated;
