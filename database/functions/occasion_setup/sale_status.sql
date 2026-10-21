-- Read-only summary inside the already authorized unit catalogue. Checkout and
-- waitlist commands remain the owners of availability and reservations.
CREATE OR REPLACE FUNCTION public.get_occasion_sale_forms_internal(p_occasion bigint,p_at timestamptz DEFAULT statement_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',f.id,'is_open',f.is_open,
  'is_preparation',coalesce((d.value#>>'{schedule,sale_preparation}')::boolean,false),
  'start_time',nullif(coalesce(d.value#>>'{schedule,start_time}',d.value->>'start_time'),''),
  'end_time',nullif(coalesce(d.value#>>'{schedule,end_time}',d.value->>'end_time'),''),
  'enable_countdown',coalesce((coalesce(d.value#>>'{schedule,enable_countdown}',d.value->>'enable_countdown'))::boolean,false),
  'registration_mode',m.value,
  'has_availability',CASE
   WHEN m.value='blueprint' THEN EXISTS (
    -- Resolve the form's small offer before running expensive inventory checks.
    -- Without this boundary a hash join can evaluate every system product.
    WITH offered_products AS MATERIALIZED (
     SELECT p.id,offered.has_capacity
     FROM public.blueprint_form_products_internal(f.id) offered
     JOIN eshop.products p ON p.id=offered.product
     WHERE NOT p.is_hidden
    )
    SELECT 1 FROM offered_products p
    WHERE public.is_product_dynamically_available(p.id)
    AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0
    AND (p.has_capacity OR EXISTS (
     SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
     WHERE sb.blueprint=f.blueprint AND s.product=p.id AND NOT sb.blocked
      AND NOT EXISTS (
       SELECT 1 FROM unnest(public.blueprint_selection_unit_spots_internal(s.id)) member(id)
       JOIN eshop.spots occupied ON occupied.id=member.id
       WHERE occupied.order_product_ticket IS NOT NULL OR occupied.state='black'
        OR (occupied.secret IS NOT NULL AND occupied.secret_expiration_time>p_at))
    )))
   WHEN m.value='regular' THEN NOT EXISTS (
    SELECT 1 FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
     WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false)
     AND (pt.type='spot' OR ff.is_required)
     AND NOT EXISTS (
      WITH field_products AS MATERIALIZED (
       SELECT p.id FROM eshop.products p
       WHERE p.product_type=ff.product_type AND NOT p.is_hidden
      )
      SELECT 1 FROM field_products p WHERE public.is_product_dynamically_available(p.id)
      AND (public.blueprint_product_availability_internal(p.id)->>'available')::bigint>0))
   ELSE m.value='waitlist' END
 ) ORDER BY f.id),'[]'::jsonb)
 FROM public.forms f
 CROSS JOIN LATERAL (SELECT public.get_effective_form_data(f.id) AS value) d
 CROSS JOIN LATERAL (SELECT public.get_form_registration_mode_internal(f.id,greatest(p_at,nullif(coalesce(d.value#>>'{schedule,start_time}',d.value->>'start_time'),'')::timestamptz)) AS value) m
 WHERE f.occasion=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.get_occasion_sale_forms_internal(bigint,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
