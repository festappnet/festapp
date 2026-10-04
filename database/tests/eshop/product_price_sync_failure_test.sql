-- Fault injection is scoped to the test runner's rollback transaction.
CREATE OR REPLACE FUNCTION public.record_client_sync_commit_v1(p_occasion bigint,p_source text,p_change_class text,
 p_items jsonb,p_public_components text[],p_private_impacts jsonb DEFAULT '[]'::jsonb,p_dirty_keys jsonb DEFAULT '[]'::jsonb,p_actor_kind text DEFAULT 'user',p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected sync failure'; END $$;
DO $$
DECLARE org bigint; unit_id bigint; occ bigint; pt bigint; prod bigint; pc bigint;
BEGIN
 SELECT id INTO org FROM public.organizations LIMIT 1;
 SELECT id INTO unit_id FROM public.units WHERE organization=org LIMIT 1;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,unit_id,'Sync failure','price-sync-failure-'||gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occ;
 INSERT INTO eshop.product_types(occasion,title) VALUES(occ,'Tickets') RETURNING id INTO pt;
 INSERT INTO eshop.products(occasion,product_type,title,price,currency_code) VALUES(occ,pt,'Ticket',450,'CZK') RETURNING id INTO prod;
 INSERT INTO eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
 VALUES('products.price',prod,'550',now()-interval '1 minute',occ) RETURNING id INTO pc;
 PERFORM public.apply_planned_changes();
 PERFORM assert_eq((SELECT price FROM eshop.products WHERE id=prod),450::numeric,'Sync failure rolls back price');
 PERFORM assert_false((SELECT applied FROM eshop.planned_changes WHERE id=pc),'Sync failure is never marked applied');
 PERFORM assert_eq((SELECT failure_code FROM eshop.planned_changes WHERE id=pc),'APPLICATION_FAILED','Failure remains repairable');
END $$;
