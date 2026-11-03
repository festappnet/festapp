-- Caller owns authorization and its existing receipt. This helper does not
-- cancel, refund, reprice or delete anything and has no external execution grant.
CREATE OR REPLACE FUNCTION public.admit_order_mutation_v1(p_occasion bigint,p_items bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE un bigint; org bigint;
BEGIN
 IF auth.uid() IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order actor required'; END IF;
 SELECT unit,organization INTO STRICT un,org FROM public.occasions WHERE id=p_occasion;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('order.mutation',un,org),
  jsonb_build_object('actor',auth.uid(),'unit',un,'organization',org),jsonb_build_object('order.mutation.items',p_items));
END $$;
REVOKE ALL ON FUNCTION public.admit_order_mutation_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
