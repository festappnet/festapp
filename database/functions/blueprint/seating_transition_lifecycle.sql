CREATE OR REPLACE FUNCTION public.start_seating_configuration_internal(p_form bigint,p_blueprint bigint)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; b eshop.blueprints; tid uuid;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF f.id IS NULL OR NOT coalesce(public.can_author_forms(f.occasion) OR public.can_edit_occasion(f.occasion,NULL),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 SELECT * INTO b FROM eshop.blueprints WHERE id=p_blueprint;
 IF b.id IS NULL OR b.occasion<>f.occasion OR b.organization IS DISTINCT FROM (SELECT organization FROM public.occasions WHERE id=f.occasion) THEN
 RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF NOT coalesce(public.can_author_forms(f.occasion) OR public.can_edit_occasion(f.occasion,NULL),false) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=f.occasion AND jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
 RAISE EXCEPTION 'MODE_CHANGED'; END IF;
 IF b.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE EXCEPTION 'BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 SELECT id INTO tid FROM public.form_seating_transitions WHERE form=f.id AND state='organizer_managed';
 IF tid IS NOT NULL THEN
 IF NOT EXISTS(SELECT 1 FROM public.form_seating_transitions WHERE id=tid AND blueprint=b.id) THEN RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
 RETURN tid; END IF;
 IF EXISTS(SELECT 1 FROM public.forms WHERE blueprint=b.id) THEN RAISE EXCEPTION 'TARGET_ALREADY_PUBLIC'; END IF;
 IF f.blueprint IS NOT NULL THEN RAISE EXCEPTION 'MODE_CHANGED'; END IF;
 INSERT INTO public.form_seating_transitions(occasion,form,blueprint,started_by) VALUES(f.occasion,f.id,b.id,auth.uid()) RETURNING id INTO tid;
 RETURN tid;
END $$;
REVOKE ALL ON FUNCTION public.start_seating_configuration_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.start_seating_configuration(p_form bigint,p_blueprint bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occ bigint; started jsonb; tid uuid;
BEGIN
 SELECT occasion INTO occ FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='seating.configuration.start';
 IF NOT FOUND THEN SELECT occasion INTO occ FROM public.forms WHERE id=p_form; END IF;
 IF occ IS NULL OR NOT public.can_author_forms(occ) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.configuration.start',occ,auth.uid(),encode(extensions.digest(jsonb_build_array(p_form,p_blueprint)::text,'sha256'),'hex'));
 IF NOT public.can_author_forms(occ) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 tid:=public.start_seating_configuration_internal(p_form,p_blueprint);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,occ,'seating.configuration.start',
 jsonb_build_array(jsonb_build_object('entityType','form','entityId',p_form,'operation','update','safeLabel','Seating configuration','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=occ),jsonb_build_object('transitionId',tid,'context',jsonb_set(public.get_seating_transition_context(tid)->'data','{items}','[]'::jsonb)));
END $$;
REVOKE ALL ON FUNCTION public.start_seating_configuration(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.start_seating_configuration(bigint,bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_seating_configuration(p_transition uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr public.form_seating_transitions; started jsonb; original_form bigint; original_bp bigint;
BEGIN
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition;
 IF tr.id IS NULL OR NOT public.can_author_forms(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.configuration.cancel',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_transition,p_expected_revision)::text,'sha256'),'hex'));
 IF NOT public.can_author_forms(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM 1 FROM public.forms WHERE id=tr.form FOR UPDATE;
 SELECT * INTO tr FROM public.form_seating_transitions WHERE id=p_transition FOR UPDATE;
 IF tr.state<>'organizer_managed' OR tr.revision IS DISTINCT FROM p_expected_revision THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','CONTEXT_CHANGED')); END IF;
 IF EXISTS(SELECT 1 FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket JOIN eshop.orders o ON o.id=x."order" WHERE o.form=tr.form AND s.blueprint=tr.blueprint)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE blueprint=tr.blueprint AND secret IS NOT NULL AND secret_expiration_time>clock_timestamp()) THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','ASSIGNMENTS_EXIST')); END IF;
 UPDATE public.form_seating_transitions SET state='cancelled',revision=revision+1,finished_by=auth.uid(),finished_at=clock_timestamp() WHERE id=tr.id;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.configuration.cancel',
 jsonb_build_array(jsonb_build_object('entityType','form','entityId',tr.form,'operation','update','safeLabel','Seating configuration removed','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('transitionId',tr.id,'sourceFormId',tr.form,'targetBlueprintId',tr.blueprint,'context',jsonb_set(public.get_seating_transition_context(tr.id)->'data','{items}','[]'::jsonb)));
END $$;
REVOKE ALL ON FUNCTION public.cancel_seating_configuration(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_seating_configuration(uuid,bigint,uuid) TO authenticated;
