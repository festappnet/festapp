-- Catalog counts cover all created orders in the authorized scope, including
-- stock and waitlist. The occasion sales report has its own sales population.
-- A NULL form list selects occasion totals. A non-NULL list selects form totals.
CREATE OR REPLACE FUNCTION public.get_order_catalog_counts_internal(p_occasions bigint[],p_forms bigint[])
RETURNS TABLE(occasion_id bigint,form_id bigint,total bigint,storno bigint,paid_or_sent bigint,ordered bigint,used bigint)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT o.occasion,CASE WHEN p_forms IS NOT NULL THEN f.id END,
  count(*),count(*) FILTER (WHERE o.state='storno'),
  count(*) FILTER (WHERE o.state IN ('paid','sent')),
  count(*) FILTER (WHERE o.state='ordered'),count(*) FILTER (WHERE o.state='used')
 FROM eshop.orders o
 LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion AND p_forms IS NOT NULL
 WHERE o.occasion=ANY(p_occasions) AND (p_forms IS NULL OR f.id=ANY(p_forms))
 GROUP BY 1,2;
$$;
REVOKE ALL ON FUNCTION public.get_order_catalog_counts_internal(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;
