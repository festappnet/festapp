BEGIN;
DO $test$
DECLARE layout jsonb := $layout${"schemaVersion": 1, "templates": {"wide": {"pageFit": "ticket", "page": {"width": 200, "height": 375}, "ticketArea": {"x": 0, "y": 0, "width": 200, "height": 375}, "elements": [{"id": "logo", "binding": "logo", "box": {"x": 71.875, "y": 12.5, "width": 56.25, "height": 56.25}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionTitle", "binding": "occasionTitle", "box": {"x": 6.25, "y": 77, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionDatePlace", "binding": "occasionDatePlace", "box": {"x": 6.25, "y": 111, "width": 187.5, "height": 24}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "orderName", "binding": "orderName", "box": {"x": 6.25, "y": 151, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "qr", "binding": "qr", "box": {"x": 50, "y": 206.25, "width": 100, "height": 100}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "ticketSymbol", "binding": "ticketSymbol", "box": {"x": 10, "y": 313, "width": 180, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "center"}}, {"id": "footer", "binding": "footer", "box": {"x": 6.25, "y": 348, "width": 187.5, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 6.25, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}]}}}$layout$::jsonb; value jsonb; bad jsonb;
BEGIN
  layout:=jsonb_set(layout,'{templates,wide,backgroundTransform}','{"scale":2,"x":-0.3,"y":0.2}');
  PERFORM public.validate_ticket_layout(layout);
  FOR value IN SELECT v FROM jsonb_array_elements('[null,{}, {"scale":0,"x":0,"y":0},{"scale":1,"x":11,"y":0},{"scale":1,"x":0,"y":"oops"}]') v LOOP
    bad:=jsonb_set(layout,'{templates,wide,backgroundTransform}',value);
    BEGIN
      PERFORM public.validate_ticket_layout(bad);
      RAISE EXCEPTION 'Expected invalid transform rejection' USING ERRCODE='XX000';
    EXCEPTION WHEN raise_exception THEN NULL; END;
  END LOOP;
END;
$test$;
ROLLBACK;
