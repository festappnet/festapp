-- Shared editor resource admission, independent of ticket authoring.
BEGIN;
-- Shared immutable fonts and text shaping serve both editors. Admission to
-- these resources does not grant ticket template, PDF or blueprint writes.
CREATE OR REPLACE FUNCTION public.can_prepare_layout_resources(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT coalesce(public.can_write_blueprints(p_occasion),false)
     OR coalesce(public.can_edit_ticket_layout(p_occasion),false);
$$;

GRANT EXECUTE ON FUNCTION public.can_prepare_layout_resources(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admit_layout_resources_limits_v1(p_occasion bigint,p_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE o public.occasions;
BEGIN
 IF NOT public.can_prepare_layout_resources(p_occasion) THEN RETURN NULL; END IF;
 IF p_bytes IS NULL OR p_bytes<=0 THEN
  RAISE invalid_parameter_value USING MESSAGE='preview bytes required';
 END IF;
 SELECT * INTO STRICT o FROM public.occasions WHERE id=p_occasion;
 -- Reuse the existing actor/unit/organization budget across both editors.
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('ticket.preview',o.unit,o.organization),
  jsonb_build_object('actor',auth.uid(),'unit',o.unit,'organization',o.organization),
  jsonb_build_object('ticket.preview.payload.bytes',p_bytes));
 RETURN public.bound_document_data_v1('{}');
END $$;

GRANT EXECUTE ON FUNCTION public.admit_layout_resources_limits_v1(bigint,bigint) TO authenticated;

COMMIT;
