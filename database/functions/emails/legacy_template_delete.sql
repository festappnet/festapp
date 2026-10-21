-- Preserve the old signature, void response, error and narrower admission.
-- Mutation itself has one owner in delete_entity_email_template.
CREATE OR REPLACE FUNCTION public.delete_occasion_email_template(p_occasion_id bigint,p_code text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_delete_legacy_occasion_email_template(p_occasion_id) THEN
   RAISE EXCEPTION 'User is not an editor for this occasion';
 END IF;
 PERFORM public.delete_entity_email_template('occasion',p_occasion_id,p_code);
END $$;
