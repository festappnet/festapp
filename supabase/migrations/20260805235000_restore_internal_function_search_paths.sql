-- Restore the execution context carried by legacy SECURITY DEFINER functions
-- before they were renamed behind the client-sync v1 facades. A facade uses an
-- empty search_path deliberately; an internal function must therefore own its
-- canonical application search_path instead of inheriting the facade's value.

ALTER FUNCTION public.confirm_blueprint_order_change_internal_v1(bigint[], jsonb)
  SET search_path = public, extensions;
ALTER FUNCTION public.create_form_internal_v1(bigint, text, text)
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_form_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_occasion_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_order_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_product_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.delete_unit_user_internal_v1(uuid, bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.duplicate_form_to_occasion_internal_v1(bigint, text)
  SET search_path = public, extensions;
ALTER FUNCTION public.game_guess_internal_v1(bigint, text)
  SET search_path = public, extensions;
ALTER FUNCTION public.game_update_settings_internal_v1(bigint, timestamptz, timestamptz)
  SET search_path = public, extensions;
ALTER FUNCTION public.import_users_from_tickets_ws_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.storno_tickets_bulk_internal_v1(bigint[])
  SET search_path = public, extensions;
ALTER FUNCTION public.swap_spot_tickets_internal_v1(bigint, bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_blueprint_internal_v1(jsonb)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_form_internal_v1(jsonb)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_order_and_tickets_to_storno_ws_internal_v1(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_product_inventory_contexts_internal_v1(bigint, jsonb)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_spot_assignments_internal_v1(jsonb)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_unit_internal_v1(bigint, text, jsonb)
  SET search_path = public, extensions;

-- The public version is the canonical RPC used by PostgREST. This same-signature
-- eshop copy is an obsolete pre-cutover implementation and has no dependants.
DO $$
BEGIN
  IF to_regprocedure(
    'public.get_products_for_ticket_all_available(bigint)'
  ) IS NULL THEN
    RAISE EXCEPTION
      'canonical public.get_products_for_ticket_all_available(bigint) is missing';
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS eshop.get_products_for_ticket_all_available(bigint);
