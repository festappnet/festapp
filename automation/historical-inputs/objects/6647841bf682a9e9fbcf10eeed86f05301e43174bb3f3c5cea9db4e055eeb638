CREATE OR REPLACE FUNCTION public.get_resources_for_inventory_pool(p_inventory_pool_id BIGINT)
RETURNS SETOF public.resources -- Returns a table of resource rows
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_occasion_id BIGINT;
BEGIN
  -- First, find the occasion associated with the requested inventory pool.
  -- This is crucial for the permission check.
  SELECT p.occasion
  INTO v_occasion_id
  FROM public.inventory_pools p
  WHERE p.id = p_inventory_pool_id;

  -- If the pool doesn't exist, we can't proceed.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory Pool with ID % not found.', p_inventory_pool_id;
  END IF;

  -- If the pool isn't linked to an occasion, deny access as we cannot check permissions.
  IF v_occasion_id IS NULL THEN
    RAISE EXCEPTION 'The parent Inventory Pool with ID % is not linked to an occasion.', p_inventory_pool_id;
  END IF;

  -- Perform the security check to ensure the calling user has editor rights on the occasion.
  -- This prevents users from one occasion from viewing data from another.
  PERFORM public.check_is_editor_order_view_on_occasion(v_occasion_id);

  -- If the permission check is successful, return all resources
  -- that belong to the specified inventory pool.
  RETURN QUERY
  SELECT *
  FROM public.resources
  WHERE inventory_pool = p_inventory_pool_id
  ORDER BY id;
END;
$$;