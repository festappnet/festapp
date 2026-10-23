CREATE OR REPLACE FUNCTION public.blueprint_seat_order_selection_internal(p_occasion bigint,p_blueprint bigint,p_spots bigint[],p_max integer)
RETURNS bigint[] LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 IF coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>p_max OR array_position(p_spots,NULL) IS NOT NULL
  OR (SELECT count(DISTINCT id) FROM unnest(p_spots) id)<>cardinality(p_spots) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid order seat selection'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot
  WHERE b.blueprint=p_blueprint AND s.blueprint=p_blueprint AND s.occasion=p_occasion AND b.spot=ANY(p_spots))<>cardinality(p_spots) THEN
  RAISE insufficient_privilege USING MESSAGE='order seat selection unavailable'; END IF;
 -- Expand each requested atomic unit once, including singleton seats. The
 -- canonical unit helper is authoritative; no copy of group semantics in MCP.
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM (
  SELECT DISTINCT coalesce(b.selection_unit::text,'spot:'||b.spot) unit,min(b.spot) representative
  FROM eshop.blueprint_seat_bindings b WHERE b.blueprint=p_blueprint AND b.spot=ANY(p_spots)
  GROUP BY coalesce(b.selection_unit::text,'spot:'||b.spot)) selected
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(selected.representative)) member;
 IF cardinality(ids)>p_max THEN RAISE program_limit_exceeded USING MESSAGE='expanded order selection exceeds operation limit'; END IF;
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(ids) AND occasion=p_occasion AND blueprint=p_blueprint)<>cardinality(ids) THEN
  RAISE insufficient_privilege USING MESSAGE='expanded order selection unavailable'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_seat_order_selection_internal(bigint,bigint,bigint[],integer) FROM PUBLIC,anon,authenticated,service_role;

-- Cancelling a selected ticket also releases every other seat on that ticket.
-- Keep new-order targets distinct from this larger affected closure.
CREATE OR REPLACE FUNCTION public.blueprint_order_affected_spots_internal(p_spots bigint[])
RETURNS bigint[] LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT ARRAY(SELECT id FROM (
  SELECT unnest(p_spots) id UNION SELECT s.id FROM eshop.spots s
  JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
  WHERE i.ticket IN(SELECT selected.ticket FROM eshop.spots target
   JOIN eshop.order_product_ticket selected ON selected.id=target.order_product_ticket WHERE target.id=ANY(p_spots))) affected ORDER BY id)
$$;
REVOKE ALL ON FUNCTION public.blueprint_order_affected_spots_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;
