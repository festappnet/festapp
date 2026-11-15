-- One actual-term projection for PDFs, Wallet and order changes. Sales-window
-- metadata is deliberately absent from this owner.
CREATE OR REPLACE FUNCTION public.order_term_occasion_internal(p_order bigint)
RETURNS public.occasions LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occ public.occasions; form public.forms;
BEGIN
 SELECT oc.* INTO occ FROM public.occasions oc JOIN eshop.orders o ON o.occasion=oc.id WHERE o.id=p_order;
 SELECT f.* INTO form FROM public.forms f JOIN eshop.orders o ON o.form=f.id WHERE o.id=p_order AND f.occasion=occ.id;
 occ.start_time:=coalesce(form.term_start_at,occ.start_time);
 -- An unknown term end must not become a fabricated expiry at its start.
 occ.end_time:=CASE WHEN form.term_start_at IS NOT NULL THEN form.term_end_at ELSE occ.end_time END;
 RETURN occ;
END $$;
REVOKE ALL ON FUNCTION public.order_term_occasion_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_order_wallet_term_domain_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE term public.occasions;
BEGIN
 term:=public.order_term_occasion_internal(p_order);
 IF term.end_time IS NULL THEN RETURN; END IF;
 UPDATE eshop.ticket_wallet_capabilities SET event_end_at=term.end_time,expires_at=term.end_time+interval '7 days'
 WHERE order_id=p_order AND occasion=term.id AND organization=term.organization AND revoked_at IS NULL AND reissue_after IS NULL AND event_end_at IS DISTINCT FROM term.end_time;
 UPDATE eshop.ticket_wallet_collections SET event_end_at=term.end_time,expires_at=term.end_time+interval '7 days'
 WHERE order_id=p_order AND occasion=term.id AND organization=term.organization AND revoked_at IS NULL AND event_end_at IS DISTINCT FROM term.end_time;
END $$;
REVOKE ALL ON FUNCTION public.refresh_order_wallet_term_domain_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
