-- SQL work is deliberately rolled back after capturing the authoritative result.
-- The existing financial owner is executed; preview maintains no alternate maths.
CREATE OR REPLACE FUNCTION public.preview_blueprint_swap(p_spot_1 bigint,p_spot_2 bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; occ bigint;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_spot_1,p_spot_2);
 IF occ IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 BEGIN
  result:=public.apply_blueprint_seat_swap_internal(p_spot_1,p_spot_2);
  RAISE SQLSTATE 'BP001' USING MESSAGE='rollback successful swap preview';
 EXCEPTION WHEN SQLSTATE 'BP001' THEN NULL;
 WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
 WHEN OTHERS THEN result:=jsonb_build_object('code',409,'reason',SQLERRM,'issues',jsonb_build_array(jsonb_build_object('reason',SQLERRM)));
 END;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_swap(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_swap(bigint,bigint) TO authenticated;
