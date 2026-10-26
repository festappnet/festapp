CREATE OR REPLACE FUNCTION public.get_external_services(p_order_id bigint)
  RETURNS TABLE (
    id bigint,
    type text,
    data jsonb,
    unit bigint
  )
  LANGUAGE sql
SET search_path = public, extensions
AS $$
  SELECT
    es.id,
    es.type,
    es.data,
    es.unit
  FROM eshop.external_services AS es
  JOIN public.occasions         AS o   ON es.unit       = o.unit
  JOIN eshop.orders            AS ord ON ord.occasion  = o.id
  WHERE ord.id = p_order_id;
$$;
