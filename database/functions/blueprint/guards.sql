-- Every blueprint writer takes this scope before form/order/product/inventory/spot
-- locks. Sorted occasion IDs allow bulk ticket commands spanning occasions.
CREATE OR REPLACE FUNCTION public.lock_blueprint_scope_internal(p_occasions bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE n bigint;
BEGIN
 FOR n IN SELECT DISTINCT x FROM unnest(p_occasions) x WHERE x IS NOT NULL ORDER BY x LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('blueprint:'||n::text,0));
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.check_blueprint_selection_units_internal(p_spots bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings selected
   JOIN eshop.blueprint_seat_bindings member ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
   WHERE selected.spot=ANY(p_spots) AND selected.selection_unit IS NOT NULL
   AND NOT member.spot=ANY(coalesce(p_spots,'{}'::bigint[]))) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SELECTION_UNIT';
 END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings selected
   JOIN eshop.blueprint_seat_bindings member ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
   JOIN eshop.spots s ON s.id=member.spot JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=opt.ticket
   WHERE selected.spot=ANY(p_spots) AND selected.selection_unit IS NOT NULL AND t.state='used') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SELECTION_UNIT_USED';
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.blueprint_selection_unit_spots_internal(p_spot bigint)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(array_agg(member.spot ORDER BY member.spot),ARRAY[p_spot])
 FROM eshop.blueprint_seat_bindings selected JOIN eshop.blueprint_seat_bindings member
 ON member.blueprint=selected.blueprint AND member.selection_unit=selected.selection_unit
 WHERE selected.spot=p_spot AND selected.selection_unit IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.lock_blueprint_scope_internal(bigint[]),public.check_blueprint_selection_units_internal(bigint[]),public.blueprint_selection_unit_spots_internal(bigint) FROM PUBLIC,anon,authenticated;
