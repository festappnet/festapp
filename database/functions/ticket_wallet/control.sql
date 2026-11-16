-- Installed during expansion so the old and new claim owner share one fence.
CREATE OR REPLACE FUNCTION public.pause_ticket_wallet(p_organization bigint,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM pg_advisory_xact_lock(hashtextextended('wallet-claim:'||p_organization,0));
 UPDATE eshop.ticket_wallet_integrations SET paused=p_paused WHERE organization=p_organization;
 IF NOT FOUND THEN RAISE EXCEPTION 'wallet_integration_missing'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.pause_ticket_wallet(bigint,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pause_ticket_wallet(bigint,boolean) TO service_role;
