-- Fixed output/asset limits accompany the existing admitted document response.
CREATE OR REPLACE FUNCTION public.bound_document_data_v1(data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE policy jsonb; limits jsonb; cap bigint;
BEGIN
 policy:=public.abuse_effective_rules_v1('document.output',NULL,NULL);
 IF policy IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 SELECT jsonb_object_agg(r->>'rule_key',(r->>'base_limit')::bigint) INTO limits FROM jsonb_array_elements(policy->'rules') r;
 cap:=(limits->>'document.input.bytes')::bigint;
 IF octet_length(data::text)>cap THEN RAISE SQLSTATE 'PT429' USING MESSAGE='document_input_limit'; END IF;
 RETURN data||jsonb_build_object('abuseLimits',limits);
END $$;
REVOKE ALL ON FUNCTION public.bound_document_data_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_ticket_document_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o public.occasions; policy jsonb;
BEGIN
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 policy:=public.abuse_effective_rules_v1('ticket.document',o.unit,o.organization);
 IF auth.uid() IS NULL THEN
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'actor'));
 END IF;
 PERFORM public.abuse_charge_v1(policy,jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization));
END $$;
REVOKE ALL ON FUNCTION public.admit_ticket_document_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Authorization, resource selection and admission happen before the existing
-- expensive read. The transport never supplies an actor, Unit or Organization.
CREATE OR REPLACE FUNCTION public.get_ticket_document_data_v1(p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint;
BEGIN
 SELECT occasion INTO occ FROM eshop.tickets WHERE id=p_ticket;
 IF occ IS NULL OR NOT (public.is_service_role() OR (auth.uid() IS NOT NULL AND public.get_is_editor_order_view_on_occasion(occ))) THEN
  RAISE insufficient_privilege USING MESSAGE='ticket document access denied'; END IF;
 PERFORM public.admit_ticket_document_internal_v1(occ);
 RETURN public.bound_document_data_v1(public.get_ticket_details_for_generating(p_ticket));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_document_data_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_document_data_v1(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_order_agreement_data_v1(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint;
BEGIN
 SELECT occasion INTO occ FROM eshop.orders WHERE id=p_order;
 IF occ IS NULL OR NOT (public.is_service_role() OR (auth.uid() IS NOT NULL AND public.get_is_editor_order_on_occasion(occ))) THEN
  RAISE insufficient_privilege USING MESSAGE='order document access denied'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.admit_ticket_document_internal_v1(occ);
 RETURN public.bound_document_data_v1(public.get_order_details(p_order));
END $$;
REVOKE ALL ON FUNCTION public.get_order_agreement_data_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_agreement_data_v1(bigint) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.admit_ticket_preview_v1(p_occasion bigint,p_bytes bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o public.occasions;
BEGIN
 IF public.can_edit_ticket_layout(p_occasion) IS NOT TRUE THEN RETURN false; END IF;
 IF p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='preview bytes required'; END IF;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('ticket.preview',o.unit,o.organization),
  jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization),jsonb_build_object('ticket.preview.payload.bytes',p_bytes));
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.admit_ticket_preview_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_ticket_preview_v1(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.admit_ticket_preview_limits_v1(p_occasion bigint,p_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.admit_ticket_preview_v1(p_occasion,p_bytes) THEN RETURN NULL; END IF;
 RETURN public.bound_document_data_v1('{}');
END $$;
REVOKE ALL ON FUNCTION public.admit_ticket_preview_limits_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_ticket_preview_limits_v1(bigint,bigint) TO authenticated;
