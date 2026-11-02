-- Additional synthetic scenarios, isolated to this review sandbox; never replay.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM festapp_test_support.disposable_environment WHERE project='festapp-order-detail-20261101') THEN RAISE EXCEPTION 'Wrong sandbox'; END IF;
END $$;
SET festapp.email_wake='scheduled';
DO $$
DECLARE oc bigint;frm bigint;actor uuid;oid bigint;stock bigint;batch uuid;ticket bigint;
BEGIN
 SELECT id INTO actor FROM public.user_info WHERE email_readonly='spravce@example.invalid';
 SELECT id INTO oc FROM public.occasions WHERE link='order-detail-ples';
 SELECT id INTO frm FROM public.forms WHERE occasion=oc ORDER BY id LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);PERFORM set_config('request.jwt.claim.role','authenticated',true);
 -- A sold printed batch member remains linked to its actual order and symbol.
 SELECT id INTO oid FROM eshop.orders WHERE occasion=oc AND data->>'name'='Tomáš';
 SELECT x.ticket INTO ticket FROM eshop.order_product_ticket x WHERE x."order"=oid ORDER BY x.id LIMIT 1;
 IF EXISTS(SELECT 1 FROM eshop.ticket_batch_items WHERE ticket_id=ticket) THEN RAISE EXCEPTION 'Scenarios already installed'; END IF;
 stock:=public.allocate_ticket_order_identity_internal(frm);
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL,currency_code='CZK',data='{"tickets":[]}' WHERE id=stock;
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot)
  VALUES(oc,frm,stock,'Předtištěné vstupenky u pořadatele',actor,'CZK','{}') RETURNING id INTO batch;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal,sale_order_id) VALUES(batch,ticket,1,oid);
 -- Viewer identity was created by the navigation fixture; it has no write role.
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order,is_editor)
  SELECT oc,id,true,false,false FROM public.user_info WHERE email_readonly='viewer@example.invalid'
  ON CONFLICT DO NOTHING;
END $$;
