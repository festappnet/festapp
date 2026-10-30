-- Source: database/functions/eshop_forms/recover_form_save_client_sync_v1.sql
-- Resolve an uncertain editor save without executing its old document again.
-- The original command/hash lock serializes against an in-flight save. A save
-- that rolled back is sealed as rejected so a delayed packet cannot apply it.
CREATE OR REPLACE FUNCTION public.recover_form_save_client_sync_v1(p_form jsonb, p_command_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE actor uuid := auth.uid(); oc bigint; form_id bigint; request_hash text; receipt jsonb;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form) <> 'object'
    OR octet_length(p_form::text) > 4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate';
  END IF;
  oc := NULLIF(p_form->>'occasion','')::bigint;
  form_id := NULLIF(p_form->>'id','')::bigint;
  IF actor IS NULL OR oc IS NULL OR form_id IS NULL
    OR NOT public.can_author_forms(oc) THEN
    RAISE insufficient_privilege USING MESSAGE='form editor required';
  END IF;
  request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',oc,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  receipt := public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',oc,actor,request_hash);
  IF receipt->>'disposition' = 'replay' THEN RETURN receipt->'response'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=oc) THEN
    RAISE insufficient_privilege USING MESSAGE='foreign form';
  END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,
    jsonb_build_object('message','FORM_SAVE_NOT_APPLIED'));
END;
$function$;
REVOKE ALL ON FUNCTION public.recover_form_save_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.recover_form_save_client_sync_v1(jsonb,uuid) TO authenticated;
