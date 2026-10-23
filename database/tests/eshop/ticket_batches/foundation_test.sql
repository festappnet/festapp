BEGIN;
CREATE FUNCTION pg_temp.fixture(cap integer DEFAULT 1) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE org bigint; un bigint; oc bigint; f bigint; fk uuid; pt bigint; prod bigint; bank bigint; actor uuid; suffix text:=gen_random_uuid()::text;
BEGIN
 INSERT INTO organizations(title) VALUES('Waitlist regression '||suffix) RETURNING id INTO org;
 INSERT INTO units(title,organization) VALUES('Waitlist regression',org) RETURNING id INTO un;
 INSERT INTO occasions(title,unit,organization,link,start_time,end_time) VALUES('Waitlist regression',un,org,suffix,now(),now()+interval '1 day') RETURNING id INTO oc;
 PERFORM public.reserve_public_link_internal('occasion',oc,suffix,true);
 INSERT INTO forms(occasion,link,participant_capacity,waitlist_enabled,waitlist_offer_duration_seconds) VALUES(oc,suffix,cap,cap IS NOT NULL,CASE WHEN cap IS NOT NULL THEN 3600 END) RETURNING id,key INTO f,fk;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Regression bank','FIO',ARRAY['CZK']) RETURNING id INTO bank;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES(un,bank);
 INSERT INTO eshop.product_types(title,type,occasion) VALUES('spot','spot',oc) RETURNING id INTO pt;
 INSERT INTO eshop.products(title,product_type,price,currency_code,occasion) VALUES('Admission',pt,100,'CZK',oc) RETURNING id INTO prod;
 INSERT INTO form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 actor:=gen_random_uuid();
 INSERT INTO auth.users(id,email) VALUES(actor,actor::text||'@example.invalid');
 INSERT INTO public.user_info(id,email_readonly,organization) VALUES(actor,actor::text||'@example.invalid',org);
 INSERT INTO occasion_users(occasion,"user",is_editor_order,is_editor_order_view,is_editor) VALUES(oc,actor,true,true,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 RETURN jsonb_build_object('organization',org,'unit',un,'occasion',oc,'form',f,'key',fk,'type',pt,'product',prod,'actor',actor,'link',suffix);
END $$;
CREATE FUNCTION pg_temp.checkout(x jsonb,tickets bigint[] DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('form',x->'key','email','regression@example.invalid','ticket',
 CASE WHEN tickets IS NULL THEN jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product'))))
 ELSE (SELECT jsonb_agg(jsonb_build_object('ticketId',id,'fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))) FROM unnest(tickets) id) END);
$$;

DO $$
DECLARE x jsonb:=pg_temp.fixture(10); r jsonb; oid bigint; tid bigint; b uuid; cfg jsonb; claim jsonb; old_lease uuid; part_id uuid; manifest text; stranger uuid:=gen_random_uuid();
BEGIN
 r:=public.create_ticket_order_internal_v1(pg_temp.checkout(x));
 PERFORM set_config('role','none',true);
 PERFORM assert_eq(r->>'code','200'::text,'shared product materializer supports checkout');
 oid:=(r#>>'{order,id}')::bigint;
 SELECT ticket INTO tid FROM eshop.order_product_ticket WHERE "order"=oid LIMIT 1;
 UPDATE eshop.orders SET state='stock',price=NULL,payment_info=NULL WHERE id=oid;
 INSERT INTO eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot)
 VALUES((x->>'occasion')::bigint,(x->>'form')::bigint,oid,'Printed batch',(x->>'actor')::uuid,'CZK','{}') RETURNING id INTO b;
 INSERT INTO eshop.ticket_batch_items(batch_id,ticket_id,ordinal) VALUES(b,tid,1);
 r:=public.update_ticket_note_hidden(tid,'Internal stock note');
 PERFORM assert_eq(r->>'code','200'::text,'private note remains editable on stock');
 PERFORM assert_eq((public.get_form_capacity_snapshot_internal((x->>'form')::bigint)->>'occupiedPeople')::integer,1,'stock occupies real capacity');
 SELECT dto INTO r FROM public.scanner_ticket_projection_internal((x->>'occasion')::bigint,'{"admission":{"allow_unpaid_online":true},"fields":[],"products":{"order":[]}}'::jsonb,tid);
 PERFORM assert_eq(r->>'admission_allowed','false'::text,'unpaid override cannot admit stock');
 PERFORM assert_eq(r->>'requires_unpaid_confirmation','false'::text,'stock is not conditional unpaid');
 PERFORM assert_eq(r->>'unavailable_reason','not_sold'::text,'scanner explains stock rejection');
 BEGIN PERFORM public.check_order_is_mutable(oid); RAISE EXCEPTION 'stock ordinary write accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN PERFORM public.scanner_admit_ticket_internal(tid); RAISE EXCEPTION 'stock admitted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN PERFORM public.check_batch_order_delete_internal(oid); RAISE EXCEPTION 'batch history deleted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN PERFORM public.update_ticket_products_wsv2(tid,'[]'); RAISE EXCEPTION 'printed products changed';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 claim:=public.claim_ticket_batch_document(b);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 manifest:=public.complete_ticket_batch_resources_internal(b,(claim->>'lease')::uuid,'{"sealed":1,"snapshot":{"occasion":{"features":[{"code":"ticket","ticket_type":"wide","layout":{"templates":{"wide":{"page":{"width":595.28,"height":841.89},"ticketArea":{"x":40,"y":42,"width":200,"height":300}}}}}]}}}',20);
 SELECT id INTO part_id FROM eshop.ticket_batch_document_parts WHERE batch_id=b AND kind='single';
 claim:=public.claim_ticket_batch_document(b,part_id); old_lease:=(claim->>'lease')::uuid;
 UPDATE eshop.ticket_batch_document_parts SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE id=part_id;
 claim:=public.claim_ticket_batch_document(b,part_id);
 BEGIN PERFORM public.complete_ticket_batch_document_internal(part_id,old_lease,repeat('a',64),100,1); RAISE EXCEPTION 'stale lease published';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BATCH_STALE_LEASE' THEN RAISE; END IF; END;
 PERFORM public.complete_ticket_batch_document_internal(part_id,(claim->>'lease')::uuid,repeat('a',64),100,1);
 BEGIN PERFORM public.complete_ticket_batch_document_internal(part_id,old_lease,repeat('b',64),100,1); RAISE EXCEPTION 'ready PDF overwritten';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BATCH_DOCUMENT_IMMUTABLE' THEN RAISE; END IF; END;
 PERFORM assert_eq(public.complete_ticket_batch_resources_internal(b,old_lease,'{"sealed":2}',20),manifest,'sealed resource manifest cannot be replaced');
 r:=public.get_ticket_batch_export_manifest(b);
 PERFORM assert_eq(jsonb_array_length(r->'documents'),1,'export includes every frozen single');
 PERFORM assert_eq(r#>>'{documents,0,digest}',repeat('a',64),'export attests exact stored digest');
 PERFORM assert_eq(r#>>'{documents,0,ordinal}','1'::text,'export preserves printed ordinal');
 PERFORM assert_not_null(r->'abuseLimits','export has authoritative output policy');
 PERFORM assert_eq(r#>>'{template,ticketArea,width}','200'::text,'A4 crop comes from frozen layout');
 UPDATE eshop.ticket_batch_document_parts SET state='failed' WHERE id=part_id;
 BEGIN PERFORM public.get_ticket_batch_export_manifest(b); RAISE EXCEPTION 'incomplete export accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BATCH_PRINT_NOT_READY' THEN RAISE; END IF; END;
 UPDATE eshop.ticket_batch_document_parts SET state='ready' WHERE id=part_id;
 INSERT INTO auth.users(id,email) VALUES(stranger,stranger::text||'@example.invalid');
 PERFORM set_config('request.jwt.claim.sub',stranger::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN PERFORM public.get_ticket_batch_export_manifest(b); RAISE EXCEPTION 'foreign batch export disclosed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_ticket_batch_detail(b); RAISE EXCEPTION 'foreign batch read disclosed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_ticket_batch_stored_document(tid); RAISE EXCEPTION 'foreign stored document disclosed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 -- An ordinary sale parent must not make an active printed ticket editable.
 UPDATE eshop.orders SET state='paid' WHERE id=oid;
 BEGIN PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[tid]); RAISE EXCEPTION 'sold printed ticket editable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 UPDATE eshop.tickets SET state='storno' WHERE id=tid;
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[tid]);
END $$;
ROLLBACK;
