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

DO $$
DECLARE preset record; family text; face text; payload jsonb; projected jsonb; mode text;
BEGIN
 FOR preset IN SELECT * FROM (VALUES
 ('clean','4465A6','4465A6',false,'Roboto'),
 ('gala','14284B','A87F28',true,'Roboto Slab'),
 ('energy','BB350C','8B182E',true,'Russo One'),
 ('nature','216445','146475',true,'Roboto'),
 ('soft','885268','B89A68',true,'Roboto Slab'),
 ('contrast','111111','111111',false,'Roboto'),
 ('ocean','075985','0F766E',true,'Open Sans'),
 ('royal','312E81','7E22CE',true,'Playfair Display'),
 ('lavender','6D28D9','A855A0',true,'Lato'),
 ('citrus','3F6212','A16207',true,'Montserrat'),
 ('sunset','C2410C','9D174D',true,'Poppins'),
 ('wine','701A3C','9F1239',true,'Roboto Slab'),
 ('terracotta','9A3412','92400E',true,'Oswald'),
 ('forest','14532D','365314',true,'Open Sans'),
 ('graphite','334155','475569',true,'Inter'),
 ('rose','9D174D','BE185D',true,'Playfair Display'),
 ('azure','1D4ED8','0369A1',true,'Montserrat'),
 ('cream','785A38','A16207',true,'Lato')) AS p(id,primary_color,secondary_color,gradient,font_family) LOOP
  face:=public.occasion_setup_font_id_internal(preset.font_family);
  PERFORM assert_true(face IS NOT NULL,'All 18 offered presets have an immutable face');
  payload:=jsonb_build_object('title','Preset fixture','formEnabled',true,
   'appearance',jsonb_build_object('id',preset.id,'primary',preset.primary_color,'secondary',preset.secondary_color,'gradient',preset.gradient,'fontFamily',preset.font_family),
   'formDraft',jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('type','ticket')),'data',jsonb_build_object('design',jsonb_build_object(
    'primary_color','#'||preset.primary_color,'secondary_color','#'||preset.secondary_color,'font_family',preset.font_family,'background_mode',CASE WHEN preset.gradient THEN 'gradient' ELSE 'solid' END))),
   'ticketDraft',jsonb_build_object('layout',jsonb_build_object('templates',jsonb_build_object('wide',
    jsonb_build_object('fontId',face,'canvasColor',preset.primary_color)||CASE WHEN preset.gradient THEN jsonb_build_object('canvasGradient',jsonb_build_array(preset.primary_color,preset.secondary_color)) ELSE '{}'::jsonb END))));
  FOREACH mode IN ARRAY ARRAY['pdf_attachment','inline_qr','both'] LOOP
   payload:=jsonb_set(payload,'{ticketDraft,delivery_mode}',to_jsonb(mode));
   projected:=public.normalize_occasion_setup_appearance_internal(payload);
   PERFORM assert_eq(projected#>>'{formDraft,data,design,font_family}',preset.font_family,'Selected family reaches saved form');
  END LOOP;
  projected:=public.normalize_occasion_setup_appearance_internal(payload||'{"formEnabled":false}');
  BEGIN
   PERFORM public.normalize_occasion_setup_appearance_internal(jsonb_set(jsonb_set(payload,'{ticketDraft,delivery_mode}','"pdf_attachment"'),'{ticketDraft,layout,templates,wide,fontId}','"wrong"'));
   RAISE EXCEPTION 'Mismatched font accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH family IN ARRAY ARRAY['Roboto','Roboto Slab','Russo One','Open Sans','Lato','Montserrat','Oswald','Poppins','Inter','Playfair Display'] LOOP
  PERFORM assert_true(EXISTS(SELECT 1 FROM public.ticket_font_assets WHERE id=public.occasion_setup_font_id_internal(family)), 'All ten exact immutable IDs are already seeded');
 END LOOP;
 PERFORM assert_true(public.occasion_setup_font_id_internal('Unknown font') IS NULL,'Unknown family has no resolver');
 BEGIN
  PERFORM public.normalize_occasion_setup_appearance_internal(jsonb_set(payload,'{appearance,fontFamily}','"Unknown font"'));
  RAISE EXCEPTION 'Unknown font accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM assert_false(has_function_privilege('authenticated','public.occasion_setup_font_id_internal(text)','EXECUTE'),'Font resolver remains private');
END $$;
