-- A small closed set of existing relationships, also used by restrictive RLS.
-- No caller can choose a relation or inject SQL.
CREATE OR REPLACE FUNCTION public.demo_entity_is_protected(p_kind text,p_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT CASE p_kind
 WHEN 'occasion' THEN public.is_demo_occasion(p_id)
 WHEN 'bank' THEN public.is_demo_bank_account(p_id)
 WHEN 'order' THEN EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'ticket' THEN EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'form' THEN EXISTS(SELECT 1 FROM public.forms WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'event' THEN EXISTS(SELECT 1 FROM public.events WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'pool' THEN EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'context' THEN EXISTS(SELECT 1 FROM public.inventory_contexts c JOIN public.inventory_pools p ON p.id=c.inventory_pool
   WHERE c.id=p_id AND public.is_demo_occasion(p.occasion))
 WHEN 'resource' THEN EXISTS(SELECT 1 FROM public.resources WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'product' THEN EXISTS(SELECT 1 FROM eshop.products WHERE id=p_id AND public.is_demo_occasion(occasion))
 WHEN 'payment' THEN EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=p_id AND public.is_demo_bank_account(bank_account))
 ELSE false END;
$$;
