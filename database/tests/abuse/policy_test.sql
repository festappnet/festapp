DO $$
DECLARE actor uuid; org bigint; un bigint; rev bigint; r jsonb;
BEGIN
 SELECT ui.id,ui.organization,uu.unit INTO actor,org,un FROM public.user_info ui
 JOIN public.unit_users uu ON uu."user"=ui.id WHERE uu.is_manager LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SELECT revision INTO rev FROM public.abuse_policy_revision;
 PERFORM public.set_abuse_policy_v1(rev,'Scoped override regression fixture',jsonb_build_array(jsonb_build_object(
  'rule_key','occasion.create.unit.day','base_limit',100,'target_kind','organization','target_id',org,'expires_at',now()+interval '1 day'),jsonb_build_object(
  'rule_key','occasion.create.unit.day','base_limit',60,'target_kind','unit','target_id',un,'expires_at',now()+interval '1 day')));
 r:=public.abuse_effective_rules_v1('occasion.creation',un,org);
 PERFORM assert_eq((SELECT (x->>'base_limit')::int FROM jsonb_array_elements(r->'rules') x WHERE x->>'rule_key'='occasion.create.unit.day'),60,'Unit overrides tenant defaults for Unit rule');
 PERFORM assert_eq((SELECT (x->>'base_limit')::int FROM jsonb_array_elements(r->'rules') x WHERE x->>'rule_key'='occasion.create.actor.day'),20,'target overrides never alter global actor limit');
 UPDATE public.abuse_policy_overrides SET expires_at=now()-interval '1 second' WHERE target_kind='unit';
 r:=public.abuse_effective_rules_v1('occasion.creation',un,org);
 PERFORM assert_eq((SELECT (x->>'base_limit')::int FROM jsonb_array_elements(r->'rules') x WHERE x->>'rule_key'='occasion.create.unit.day'),100,'expired override falls back to parent');
 BEGIN PERFORM public.set_abuse_policy_v1(rev,'Stale operator revision fixture','[{"rule_key":"occasion.create.unit.day","base_limit":30}]'); RAISE EXCEPTION 'stale revision accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 SELECT revision INTO rev FROM public.abuse_policy_revision;
 BEGIN PERFORM public.set_abuse_policy_v1(rev,'Illegal hard cap override fixture','[{"rule_key":"occasion.create.unit.day","base_limit":201}]'); RAISE EXCEPTION 'hard cap accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.set_abuse_policy_v1(rev,'Illegal identity change fixture','[{"rule_key":"occasion.create.unit.day","base_limit":40,"window_seconds":60}]'); RAISE EXCEPTION 'identity mutation accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 DELETE FROM public.abuse_policy_rules WHERE rule_key='occasion.create.actor.burst';
 BEGIN PERFORM public.admit_occasion_creation_v1(actor,un,org); RAISE EXCEPTION 'missing mandatory rule accepted'; EXCEPTION WHEN configuration_limit_exceeded THEN NULL; END;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.admit_occasion_creation_v1(actor,un,org); RAISE EXCEPTION 'private helper callable'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.set_abuse_policy_v1(rev,'Unauthorized editor fixture','[]'); RAISE EXCEPTION 'editor changed policy'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.abuse_policy_audit WHERE revision=rev),'operator change has an audit record');
END $$;
