BEGIN;
DO $$
DECLARE layout jsonb; v2 jsonb; font text; features jsonb;
BEGIN
  SELECT id INTO font FROM public.ticket_font_assets WHERE metadata->>'family'='Roboto Slab' LIMIT 1;
  PERFORM assert_true(font IS NOT NULL,'catalog seeded');
  -- Use the same canonical geometry as existing shared fixtures.
  layout := '{"schemaVersion":1,"templates":{"named":{"pageFit":"ticket","page":{"width":200,"height":375},"ticketArea":{"x":0,"y":0,"width":200,"height":375},"elements":[{"id":"qr","binding":"qr","box":{"x":50,"y":100,"width":100,"height":100},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":1,"color":"000000","align":"left"}},{"id":"ticketSymbol","binding":"ticketSymbol","box":{"x":10,"y":210,"width":180,"height":20},"visible":true,"locked":false,"style":{"fontSize":10,"minFontSize":6,"maxLines":1,"color":"000000","align":"center"}}]}}}';
  v2:=jsonb_set(jsonb_set(layout,'{schemaVersion}','2'),'{templates,named,fontId}',to_jsonb(font));
  PERFORM public.validate_ticket_layout(v2);
  BEGIN PERFORM public.validate_ticket_layout(jsonb_set(v2,'{schemaVersion}','1'));RAISE EXCEPTION 'v1 accepted font';EXCEPTION WHEN OTHERS THEN IF SQLERRM='v1 accepted font' THEN RAISE;END IF;END;
  BEGIN PERFORM public.validate_ticket_layout(jsonb_set(v2,'{templates,named,fontId}','"gf:unknown"'));RAISE EXCEPTION 'unknown accepted';EXCEPTION WHEN OTHERS THEN IF SQLERRM='unknown accepted' THEN RAISE;END IF;END;
  features:=jsonb_build_array(jsonb_build_object('code','ticket','layout',v2));
  BEGIN PERFORM public.merge_ticket_layout_features(features,features,jsonb_build_object('expected',v2,'next',layout));RAISE EXCEPTION 'downgrade accepted';EXCEPTION WHEN OTHERS THEN IF SQLERRM='downgrade accepted' THEN RAISE;END IF;END;
  PERFORM assert_eq(public.merge_ticket_layout_features(features,'[]')#>'{0,layout}',v2,'old client preserves v2');
  PERFORM assert_true((public.merge_ticket_layout_features(features,features,jsonb_build_object('expected',v2,'next',NULL))#>'{0,layout}') IS NULL,'explicit remove allowed');
  BEGIN PERFORM public.merge_ticket_layout_features(features,features,jsonb_build_object('expected',layout,'next',v2));RAISE EXCEPTION 'conflict accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
  PERFORM assert_eq(public.merge_ticket_layout_features(jsonb_build_array(jsonb_build_object('code','ticket','layout',jsonb_set(v2,'{schemaVersion}','3'))),'[]')#>'{0,layout,schemaVersion}','3'::jsonb,'future schema preserved');
  BEGIN PERFORM public.merge_ticket_layout_features(jsonb_build_array(jsonb_build_object('code','ticket','layout',jsonb_set(v2,'{schemaVersion}','3'))),features,jsonb_build_object('expected',jsonb_set(v2,'{schemaVersion}','3'),'next',v2));RAISE EXCEPTION 'future edit accepted';EXCEPTION WHEN OTHERS THEN IF SQLERRM='future edit accepted' THEN RAISE;END IF;END;
  PERFORM assert_true(NOT has_table_privilege('authenticated','public.ticket_font_assets','INSERT'),'client cannot register');
  PERFORM assert_true(NOT has_table_privilege('service_role','public.ticket_font_assets','UPDATE'),'registry append only');
  PERFORM assert_true(NOT (SELECT public FROM storage.buckets WHERE id='ticket-fonts'),'bucket private');
END $$;
INSERT INTO storage.objects(bucket_id,name) VALUES ('ticket-fonts','read-probe.ttf');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='ticket-fonts') THEN RAISE EXCEPTION 'private fonts exposed'; END IF;
  BEGIN INSERT INTO public.ticket_font_assets(id,metadata) VALUES ('gf:'||repeat('0',64),'{}');RAISE EXCEPTION 'client registry write accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  BEGIN
    INSERT INTO storage.objects(bucket_id,name) VALUES ('ticket-fonts','test.ttf');RAISE EXCEPTION 'client upload accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
