DO $$
DECLARE payload jsonb; projected jsonb;
BEGIN
 payload := '{"title":"One name","eventKind":"regular","formEnabled":false,"formDraft":{"title":"Old"},"ticketDraft":{},"blueprintMode":"copy","appearance":{"id":"custom","primary":"112233","secondary":"445566","gradient":false,"fontFamily":"Custom","preserveSource":true}}';
 projected:=public.normalize_occasion_setup_type_internal(payload);
 PERFORM assert_true((projected->>'formEnabled')::boolean,'Every kind retains a form');
 PERFORM assert_eq(projected#>>'{formDraft,title}','One name','Form inherits event name');
 PERFORM assert_eq(projected->>'blueprintMode','none','Dormant seating is excluded');
 PERFORM assert_false(projected ? 'ticketDraft','Regular event excludes ticket config');
 PERFORM assert_true(payload ? 'ticketDraft','Projection preserves stored work');
 payload:=jsonb_set(payload,'{eventKind}','"concert"');
 projected:=public.normalize_occasion_setup_type_internal(payload);
 PERFORM assert_true(projected ? 'ticketDraft','Concert retains tickets');
 payload:=jsonb_set(payload,'{eventKind}','"ball"');
 projected:=public.normalize_occasion_setup_type_internal(payload);
 PERFORM assert_eq(projected->>'blueprintMode','copy','Ball retains seating');
 BEGIN PERFORM public.normalize_occasion_setup_type_internal(jsonb_set(payload,'{appearance,primary}','"bad"')); RAISE EXCEPTION 'Bad color accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.normalize_occasion_setup_type_internal(payload||'{"eventKindNeedsConfirmation":true}'); RAISE EXCEPTION 'Unconfirmed kind accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_false(has_function_privilege('authenticated','public.normalize_occasion_setup_type_internal(jsonb)','EXECUTE'),'Projection is private');
 PERFORM assert_eq(public.normalize_occasion_setup_type_internal('{"title":"Legacy"}')->>'title','Legacy','Legacy clients stay compatible');
END $$;
