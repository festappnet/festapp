-- Authenticate the grid request before the service opens the encrypted link.
CREATE OR REPLACE FUNCTION public.get_order_overview_admin_context(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id;
 IF public.get_is_editor_order_view_on_occasion(o.occasion) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='Order viewer required';
 END IF;
 RETURN jsonb_build_object('orderId',o.id,'recipient',o.data->>'email');
END $$;
REVOKE ALL ON FUNCTION public.get_order_overview_admin_context(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_overview_admin_context(bigint) TO authenticated;
