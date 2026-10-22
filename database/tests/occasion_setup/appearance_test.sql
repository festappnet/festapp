DO $$
DECLARE payload jsonb; projected jsonb;
BEGIN
 payload := '{"title":"One name","eventKind":"regular","eventKindNeedsConfirmation":true,"formEnabled":true,"formDraft":{"title":"Old","fields":[{"type":"email"},{"type":"ticket"},{"type":"spot"}]},"ticketDraft":{},"blueprintMode":"copy","appearance":{"id":"custom","primary":"112233","secondary":"445566","gradient":false,"fontFamily":"Custom","preserveSource":true}}';
 projected:=public.normalize_occasion_setup_appearance_internal(payload);
 PERFORM assert_eq(projected#>>'{formDraft,title}','One name','Form inherits event name');
 PERFORM assert_eq(projected->>'blueprintMode','copy','Seating is an independent choice');
 PERFORM assert_true(projected ? 'ticketDraft','Tickets remain an independent choice');
 PERFORM assert_eq(jsonb_array_length(projected#>'{formDraft,fields}'),3,'Independent fields stay intact');
 PERFORM assert_false(projected ? 'eventKind','Retired kind cannot select behavior');
 PERFORM assert_false(projected ? 'eventKindNeedsConfirmation','Retired confirmation cannot block finalization');
 PERFORM assert_true(payload ? 'eventKind','Projection preserves original draft');
 projected:=public.normalize_occasion_setup_appearance_internal(payload||'{"formEnabled":false}');
 PERFORM assert_false((projected->>'formEnabled')::boolean,'Form remains independently disabled');
 BEGIN PERFORM public.normalize_occasion_setup_appearance_internal(jsonb_set(payload,'{appearance,primary}','"bad"')); RAISE EXCEPTION 'Bad color accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_false(has_function_privilege('authenticated','public.normalize_occasion_setup_appearance_internal(jsonb)','EXECUTE'),'Projection is private');
 PERFORM assert_eq(public.normalize_occasion_setup_appearance_internal('{"title":"Legacy"}')->>'title','Legacy','Legacy drafts without appearance remain compatible');
 PERFORM assert_true(to_regprocedure('public.normalize_occasion_setup_type_internal(jsonb)') IS NULL,'Old type gate is removed');
END $$;
