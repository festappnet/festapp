-- One projection of the actual cancellation owner, used by review and commit.
CREATE OR REPLACE FUNCTION public.apply_blueprint_ticket_cancellation_internal(p_occasion bigint,p_blueprint bigint,p_spots bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE selected bigint[];affected bigint[];tickets bigint[];v_orders bigint[];before_orders jsonb;seats jsonb;revisions jsonb;money jsonb;result jsonb;
BEGIN
 IF public.can_write_orders(p_occasion) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 PERFORM public.check_occasion_writable(p_occasion);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 selected:=public.blueprint_seat_order_selection_internal(p_occasion,p_blueprint,p_spots,1000);
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
 LEFT JOIN eshop.tickets t ON t.id=i.ticket WHERE s.id=ANY(selected) AND (t.id IS NULL OR t.state='storno')) THEN
 RAISE check_violation USING MESSAGE='BLUEPRINT_CANCELLATION_SELECTION_CHANGED'; END IF;
 affected:=public.blueprint_order_affected_spots_internal(selected);
 IF cardinality(affected)>1000 THEN RAISE program_limit_exceeded; END IF;
 PERFORM public.check_blueprint_swap_scope_internal(p_occasion,affected);
 PERFORM public.lock_spot_assignment_scope_internal(affected,'{}'::bigint[],true,'{}'::bigint[],false);
 PERFORM public.check_blueprint_swap_scope_internal(p_occasion,affected);
 SELECT array_agg(DISTINCT i.ticket ORDER BY i.ticket),array_agg(DISTINCT i."order" ORDER BY i."order")
 INTO tickets,v_orders FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(selected);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',layout_revision) ORDER BY id),'[]') INTO revisions
 FROM eshop.blueprints WHERE id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(affected));
 SELECT jsonb_agg(jsonb_build_object('spotId',s.id,'blueprintId',s.blueprint,'title',s.title,'ticketId',i.ticket,'orderId',i."order",'state',t.state) ORDER BY s.id)
 INTO seats FROM eshop.spots s JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket JOIN eshop.tickets t ON t.id=i.ticket WHERE s.id=ANY(affected);
 before_orders:=public.order_payment_snapshot_internal(v_orders);
 PERFORM public.storno_tickets_bulk_internal_v1(tickets,false);
 SELECT public.project_order_amount_changes_internal(coalesce(jsonb_agg(jsonb_build_object('orderId',id,
 'beforeAmount',(before_orders->id::text->>'amount')::numeric,'afterAmount',price,
 'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
 'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')) INTO money FROM eshop.orders WHERE id=ANY(v_orders);
 result:=jsonb_build_object('occasionId',p_occasion,'blueprintId',p_blueprint,'requestedSpotIds',p_spots,'affectedSpotIds',affected,
 'ticketIds',tickets,'blueprints',revisions,'seats',seats,'orders',money);
 RETURN result||jsonb_build_object('confirmationHash',encode(extensions.digest(convert_to(
 jsonb_build_object('actor',auth.uid(),'result',result,'beforeOrders',before_orders)::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_ticket_cancellation_internal(bigint,bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_blueprint_ticket_cancellation(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 BEGIN
 result:=public.apply_blueprint_ticket_cancellation_internal(p_occasion,p_blueprint,p_spots);
 RAISE SQLSTATE 'BC001' USING MESSAGE='rollback cancellation preview';
 EXCEPTION WHEN SQLSTATE 'BC001' THEN NULL;
 END;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_ticket_cancellation(bigint,bigint,bigint,bigint,bigint[]) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_ticket_cancellation(bigint,bigint,bigint,bigint,bigint[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_blueprint_tickets(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[],p_tickets bigint[],p_confirmation_hash text,p_command_id uuid,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_editor IS NULL OR p_confirmation_hash IS NULL OR p_confirmation_hash!~'^[a-f0-9]{64}$'
 OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>1000 OR coalesce(cardinality(p_tickets),0)=0 OR cardinality(p_tickets)>1000 THEN
 RAISE invalid_parameter_value USING MESSAGE='confirmed ticket cancellation required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion)
 OR (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion AND blueprint=p_blueprint)<>cardinality(p_spots)
 OR (SELECT count(*) FROM eshop.tickets WHERE id=ANY(p_tickets) AND occasion=p_occasion)<>cardinality(p_tickets) THEN RAISE insufficient_privilege; END IF;
 result:=public.cancel_tickets_command_internal(p_tickets,p_command_id,jsonb_build_object('occasion',p_occasion,'blueprint',p_blueprint,'spots',p_spots,'hash',p_confirmation_hash));
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT p_editor THEN result:=result-'sync'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.cancel_blueprint_tickets(bigint,bigint,bigint,bigint,bigint[],bigint[],text,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.cancel_blueprint_tickets(bigint,bigint,bigint,bigint,bigint[],bigint[],text,uuid,boolean) TO authenticated;
