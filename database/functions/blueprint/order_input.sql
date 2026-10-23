-- One form/seat transport builder used by legacy preparation and the atomic
-- replacement aggregate. It prices nothing; finalization owns actual totals.
CREATE OR REPLACE FUNCTION public.blueprint_order_input_internal(p_spots bigint[],p_input jsonb,p_analysis jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE form_key uuid; tickets jsonb;
BEGIN
 IF coalesce(p_input->>'email','')='' THEN RAISE EXCEPTION 'Email is required in input data.'; END IF;
 form_key:=(p_analysis#>>'{order_form,key}')::uuid;
 IF p_input->>'form_key' IS NOT NULL AND p_input->>'form_key' IS DISTINCT FROM form_key::text THEN
  RAISE EXCEPTION 'The active order form changed. Reopen the order.'; END IF;
 IF form_key IS NULL OR NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.key=form_key
  AND f.blueprint=(SELECT blueprint FROM eshop.spots WHERE id=p_spots[1]))
  OR EXISTS(SELECT 1 FROM eshop.spots WHERE id=ANY(p_spots) AND blueprint IS DISTINCT FROM
   (SELECT blueprint FROM eshop.spots WHERE id=p_spots[1])) THEN
  RAISE EXCEPTION 'No open form found for this occasion to create the new order.'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('spot',s.id,'fields',
  coalesce(p_input->'ticket_fields'->s.id::text,'[]'::jsonb)) ORDER BY s.id),'[]')
 INTO tickets FROM eshop.spots s WHERE s.id=ANY(p_spots);
 RETURN jsonb_build_object('form',form_key,'ticket',tickets,'lang','cs')
  ||(p_input-'ticket_fields'-'form_key'-'form'-'ticket');
END $$;
REVOKE ALL ON FUNCTION public.blueprint_order_input_internal(bigint[],jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;
