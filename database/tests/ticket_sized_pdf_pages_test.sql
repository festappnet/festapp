BEGIN;
DO $test$
DECLARE layout jsonb := $layout${"schemaVersion": 1, "templates": {"wide": {"pageFit": "ticket", "page": {"width": 200, "height": 375}, "ticketArea": {"x": 0, "y": 0, "width": 200, "height": 375}, "elements": [{"id": "logo", "binding": "logo", "box": {"x": 71.875, "y": 12.5, "width": 56.25, "height": 56.25}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionTitle", "binding": "occasionTitle", "box": {"x": 6.25, "y": 77, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionDatePlace", "binding": "occasionDatePlace", "box": {"x": 6.25, "y": 111, "width": 187.5, "height": 24}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "orderName", "binding": "orderName", "box": {"x": 6.25, "y": 151, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "qr", "binding": "qr", "box": {"x": 50, "y": 206.25, "width": 100, "height": 100}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "ticketSymbol", "binding": "ticketSymbol", "box": {"x": 10, "y": 313, "width": 180, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "center"}}, {"id": "footer", "binding": "footer", "box": {"x": 6.25, "y": 348, "width": 187.5, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 6.25, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}]}}}$layout$::jsonb; bad jsonb; bordered jsonb; invalid_margin jsonb;
BEGIN
  PERFORM public.validate_ticket_layout(layout);
  bordered := jsonb_set(layout, '{templates,wide}', (layout->'templates'->'wide') ||
    '{"pageMargin":9,"page":{"width":218,"height":393},"ticketArea":{"x":9,"y":9,"width":200,"height":375}}'::jsonb);
  PERFORM public.validate_ticket_layout(bordered);
  FOR invalid_margin IN SELECT value FROM jsonb_array_elements('[-1,73,null,"9"]'::jsonb) LOOP
    BEGIN
      PERFORM public.validate_ticket_layout(jsonb_set(bordered, '{templates,wide,pageMargin}', invalid_margin));
      RAISE EXCEPTION 'Expected invalid margin rejection: %', invalid_margin USING ERRCODE='XX000';
    EXCEPTION WHEN raise_exception THEN NULL; END;
  END LOOP;
  bad := jsonb_set(bordered, '{templates,wide,ticketArea,x}', '0');
  BEGIN
    PERFORM public.validate_ticket_layout(bad);
    RAISE EXCEPTION 'Expected mismatched margin origin rejection' USING ERRCODE='XX000';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  -- A named storage slot may select an ordinary A4 template.
  PERFORM public.validate_ticket_layout(jsonb_build_object('schemaVersion',1,'templates',
    jsonb_build_object('named',((layout->'templates'->'wide') - 'pageFit') ||
      '{"page":{"width":595.28,"height":841.89}}'::jsonb)));
  bad := jsonb_set(layout, '{templates,wide,page,width}', '199');
  BEGIN
    PERFORM public.validate_ticket_layout(bad);
    RAISE EXCEPTION 'Expected mismatched ticket page rejection' USING ERRCODE='XX000';
  EXCEPTION WHEN raise_exception THEN NULL; END;
  bad := jsonb_set(layout, '{templates,wide,pageFit}', '"unknown"');
  BEGIN
    PERFORM public.validate_ticket_layout(bad);
    RAISE EXCEPTION 'Expected unknown page fit rejection' USING ERRCODE='XX000';
  EXCEPTION WHEN raise_exception THEN NULL; END;
END;
$test$;
ROLLBACK;
