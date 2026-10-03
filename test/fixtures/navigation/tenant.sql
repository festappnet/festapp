-- Synthetic-only fixture. Run on the disposable festapp-tabs-e2e-backend DB.
DO $$
DECLARE admin_id uuid; occasion_a bigint; occasion_b bigint; bank_a bigint; bank_b bigint; unit_b bigint;
BEGIN
  IF (SELECT count(*) FROM public.organizations) <> 1 OR
     (SELECT title FROM public.organizations WHERE id=1) <> 'Test Organization' THEN
    RAISE EXCEPTION 'Expected fresh synthetic tenant';
  END IF;
  SELECT id INTO admin_id FROM public.user_info WHERE email_readonly='t@t.com';
  IF admin_id IS NULL THEN RAISE EXCEPTION 'Missing synthetic admin'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
  PERFORM set_config('request.jwt.claim.sub',admin_id::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  INSERT INTO public.units(title,organization,data) VALUES('Other E2E Unit',1,'{}') RETURNING id INTO unit_b;
  INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies,is_fetch_enabled)
    VALUES('E2E Bank Account','123456/0100','FIO',ARRAY['CZK'],false) RETURNING id INTO bank_a;
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank_a,admin_id,true);
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(1,bank_a,1);
  INSERT INTO eshop.bank_accounts(title,account_number,type,supported_currencies,is_fetch_enabled)
    VALUES('Other Unit Bank','987654/0100','FIO',ARRAY['CZK'],false) RETURNING id INTO bank_b;
  INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(bank_b,admin_id,true);
  INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(unit_b,bank_b,1);
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,data,features)
    VALUES('E2E Occasion A',1,1,'e2e-tabs-a','2026-10-03 08:00+02','2026-10-11 20:00+02','{"timezone":"Europe/Prague","information":"<p>E2E info</p>"}','[{"code": "form", "is_enabled": true}, {"code": "ticket", "is_enabled": true, "ticket_type": "wide", "layout": {"schemaVersion": 2, "templates": {"wide": {"page": {"width": 595.28, "height": 841.89}, "ticketArea": {"x": 29.76400000000001, "y": 29.764, "width": 535.752, "height": 267.876}, "elements": [{"id": "qr", "binding": "qr", "box": {"x": 405.16245, "y": 140.63490000000002, "width": 80.3628, "height": 80.3628}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "left"}}, {"id": "ticketSymbol", "binding": "ticketSymbol", "box": {"x": 405.16245, "y": 224.9977, "width": 80.3628, "height": 22}, "visible": true, "locked": false, "style": {"fontSize": 9.375659999999998, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "left"}}, {"id": "spotGroup", "binding": "spotGroup", "box": {"x": 50, "y": 167.87599999999998, "width": 241.08839999999998, "height": 21}, "visible": true, "locked": false, "style": {"fontSize": 8.036279999999998, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "left"}}, {"id": "food", "binding": "food", "box": {"x": 50, "y": 189.87599999999998, "width": 241.08839999999998, "height": 21}, "visible": true, "locked": false, "style": {"fontSize": 8.036279999999998, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "left"}}, {"id": "note", "binding": "note", "box": {"x": 50, "y": 211.87599999999998, "width": 241.08839999999998, "height": 21}, "visible": true, "locked": false, "style": {"fontSize": 8.036279999999998, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "left"}}, {"id": "price", "binding": "price", "box": {"x": 50, "y": 233.87599999999998, "width": 241.08839999999998, "height": 21}, "visible": true, "locked": false, "style": {"fontSize": 8.036279999999998, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "left"}}]}, "named": {"page": {"width": 212.5, "height": 387.5}, "ticketArea": {"x": 6.25, "y": 6.25, "width": 200, "height": 375}, "elements": [{"id": "logo", "binding": "logo", "box": {"x": 71.875, "y": 12.5, "width": 56.25, "height": 56.25}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionTitle", "binding": "occasionTitle", "box": {"x": 6.25, "y": 77, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "occasionDatePlace", "binding": "occasionDatePlace", "box": {"x": 6.25, "y": 111, "width": 187.5, "height": 24}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "orderName", "binding": "orderName", "box": {"x": 6.25, "y": 151, "width": 187.5, "height": 32}, "visible": true, "locked": false, "style": {"fontSize": 12.5, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "qr", "binding": "qr", "box": {"x": 50, "y": 206.25, "width": 100, "height": 100}, "visible": true, "locked": false, "style": {"fontSize": 12, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}, {"id": "ticketSymbol", "binding": "ticketSymbol", "box": {"x": 10, "y": 313, "width": 180, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 8.75, "minFontSize": 6, "maxLines": 1, "color": "2A2A2A", "align": "center"}}, {"id": "footer", "binding": "footer", "box": {"x": 6.25, "y": 348, "width": 187.5, "height": 20}, "visible": true, "locked": false, "style": {"fontSize": 6.25, "minFontSize": 6, "maxLines": 2, "color": "2A2A2A", "align": "center"}}], "fontId": "builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f"}}}, "background": ""}, {"code": "services", "is_enabled": true, "services_mode": "stay", "services_allow_accommodation": true, "services_allow_food": true}, {"code": "user_groups", "is_enabled": true}, {"code": "game", "is_enabled": true}, {"code": "volunteers", "is_enabled": true}, {"code": "songbook", "is_enabled": true}, {"code": "event_feedback", "is_enabled": true}, {"code": "timetable", "is_enabled": true}]'::jsonb) RETURNING id INTO occasion_a;
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,data,features)
    VALUES('E2E Occasion B',1,1,'e2e-tabs-b','2026-10-03 08:00+02','2026-10-11 20:00+02','{"timezone":"Europe/Prague"}','[]') RETURNING id INTO occasion_b;
  INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_manager,is_editor_order,is_editor_order_view,is_approved)
    VALUES(occasion_a,admin_id,true,true,true,true,true,true),(occasion_b,admin_id,true,true,true,true,true,true);
  PERFORM public.create_form(occasion_a,'e2e-first-form','E2E First Form');
  PERFORM public.create_form(occasion_a,'e2e-second-form','E2E Second Form');
  PERFORM public.create_form(occasion_b,'e2e-foreign-form','E2E Foreign Form');
  INSERT INTO public.inventory_pools(title,occasion,type,sellable_capacity,data)
    VALUES('E2E Accommodation Pool',occasion_a,'accommodation',5,'{}'),('E2E Foreign Pool',occasion_b,'accommodation',5,'{}');
  INSERT INTO public.events(title,occasion,start_time,end_time,description,data)
    VALUES('E2E First Day Event',occasion_a,'2026-10-03 10:00+02','2026-10-03 11:00+02','first','{}'),
      ('E2E Second Week Event',occasion_a,'2026-10-10 10:00+02','2026-10-10 11:00+02','second','{}');
  PERFORM public.create_user_in_organization_with_data_pure(1,'viewer@example.invalid','test','{"name":"E2E","surname":"Viewer"}');
END;
$$;
NOTIFY pgrst, 'reload schema';
