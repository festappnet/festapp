-- Optional event fields remain distinct, unique, validated schema-3 bindings.
DO $test$
DECLARE layout jsonb := $layout${"schemaVersion":3,"templates":{"named":{"page":{"width":212.5,"height":387.5},"ticketArea":{"x":6.25,"y":6.25,"width":200,"height":375},"elements":[{"id":"qr","binding":"qr","box":{"x":50,"y":206.25,"width":100,"height":100},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":2,"color":"2A2A2A","align":"center"}},{"id":"ticketSymbol","binding":"ticketSymbol","box":{"x":10,"y":313,"width":180,"height":20},"visible":true,"locked":false,"style":{"fontSize":8.75,"minFontSize":6,"maxLines":1,"color":"2A2A2A","align":"center"}},{"id":"occasionStartTime","binding":"occasionStartTime","box":{"x":10,"y":10,"width":100,"height":24},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":3,"color":"2A2A2A","align":"left"}},{"id":"occasionPlace","binding":"occasionPlace","box":{"x":10,"y":40,"width":100,"height":24},"visible":true,"locked":false,"style":{"fontSize":12,"minFontSize":6,"maxLines":3,"color":"2A2A2A","align":"left"}}]}}}$layout$::jsonb;
BEGIN
  PERFORM public.validate_ticket_layout(layout);
  BEGIN
    PERFORM public.validate_ticket_layout(jsonb_set(layout, '{templates,named,elements,3,binding}', '"occasionStartTime"'));
    RAISE EXCEPTION 'duplicate optional binding accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'duplicate optional binding accepted' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.validate_ticket_layout(jsonb_set(layout, '{templates,named,elements,3,binding}', '"unknownEventField"'));
    RAISE EXCEPTION 'unknown binding accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'unknown binding accepted' THEN RAISE; END IF;
  END;
END $test$;
