-- An editor preview resolves the same inherited template/wrapper as delivery.
-- It never creates a capability, offer, intent, or reservation.
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_email_preview(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE f public.forms; occ public.occasions; resolved jsonb;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 resolved:=public.get_email_template_and_wrapper('waitlist_offer',
  jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit));
 RETURN resolved||jsonb_build_object('code',200,'occasionTitle',occ.title,'formLink',f.link);
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_email_preview(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_email_preview(bigint) TO authenticated;
