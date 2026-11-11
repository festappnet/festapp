-- test-setup: database/tests/helpers/high_volume_email_fixture.sql
-- test-setup: database/tests/helpers/order_email_current_issues_reference.sql
-- test-setup: database/tests/helpers/order_email_summaries_reference.sql
CREATE FUNCTION pg_temp.assert_email_batch(p_occasion bigint,p_orders bigint[])
RETURNS void LANGUAGE plpgsql AS $check$
DECLARE item record;
BEGIN
 FOR item IN SELECT * FROM public.order_email_current_issues_bulk(p_orders) LOOP
  PERFORM assert_eq(item.issues,pg_temp.reference_order_email_current_issues(item.order_id),'bulk provenance equals original per-order reader');
 END LOOP;
 PERFORM assert_eq(public.get_order_email_summaries(p_occasion,p_orders),pg_temp.reference_get_order_email_summaries(p_occasion,p_orders),'complete email summary equals original assembly');
END;
$check$;
CREATE FUNCTION pg_temp.bulk_test_mail(p_order bigint,p_kind text,p_state text,p_ordinal integer,p_parent uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $mail$
DECLARE o eshop.orders; oc public.occasions; message jsonb; mid uuid;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO oc FROM public.occasions WHERE id=o.occasion;
 message:=public.enqueue_email(p_kind,jsonb_build_object('organization',oc.organization,'unit',oc.unit,'occasion',oc.id),o.data->>'email','{}','bulk-email-'||gen_random_uuid());
 mid:=(message->>'message_id')::uuid;
 UPDATE public.email_messages SET order_id=p_order,source_version=o.email_payment_version,workflow_state=p_state,
  created_at=now()-interval '2 days'+p_ordinal*interval '1 minute',
  data=CASE WHEN p_parent IS NULL THEN data ELSE data||jsonb_build_object('repair_source_message_id',p_parent) END
 WHERE message_id=mid;
 RETURN mid;
END;
$mail$;
DO $$
DECLARE org bigint; un bigint; oc bigint; actor uuid:=gen_random_uuid(); oid bigint; ids bigint[]:='{}';
 i integer; root uuid; repair uuid; cross_order uuid; cycle_one uuid; cycle_two uuid; event_mail uuid; scope_other bigint;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 INSERT INTO public.organizations(title) VALUES('Email bulk reporting') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Reporting',org) RETURNING id INTO un;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Reporting',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO auth.users(id) VALUES(actor);
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES(oc,actor,true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 FOR i IN 1..8 LOOP
  INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
  VALUES(oc,i,public.generate_order_symbol(),CASE WHEN i=4 THEN 'storno' ELSE 'sent' END,
   jsonb_build_object('email','bulk-'||i||'@example.invalid')) RETURNING id INTO oid;
  ids:=array_append(ids,oid);
 END LOOP;
 -- Delivered current tickets supersede an older failed checkout confirmation.
 cross_order:=pg_temp.bulk_test_mail(ids[1],'order_confirmation','accepted',1);
 UPDATE public.email_messages SET bounced_at=now()-interval '1 day' WHERE message_id=cross_order;
 root:=pg_temp.bulk_test_mail(ids[1],'order_tickets','accepted',2);
 UPDATE public.email_messages SET delivered_at=now(),opened_at=now() WHERE message_id=root;
 -- An unresolved repair chain, later mutated into a stale delivery.
 root:=pg_temp.bulk_test_mail(ids[2],'order_tickets','accepted',3);
 UPDATE public.email_messages SET bounced_at=now()-interval '1 day' WHERE message_id=root;
 repair:=pg_temp.bulk_test_mail(ids[2],'order_tickets','pending',4,root);
 -- Rootless cycles terminate without leaking into another order's chain.
 cycle_one:=pg_temp.bulk_test_mail(ids[3],'order_tickets','dead',5);
 cycle_two:=pg_temp.bulk_test_mail(ids[3],'order_tickets','dead',6,cycle_one);
 UPDATE public.email_messages SET data=data||jsonb_build_object('repair_source_message_id',cycle_two) WHERE message_id=cycle_one;
 PERFORM pg_temp.bulk_test_mail(ids[4],'order_tickets','dead',7);
 -- ids[5] deliberately has no messages; pending confirmation remains visible.
 PERFORM pg_temp.bulk_test_mail(ids[6],'order_confirmation','pending',8);
 event_mail:=pg_temp.bulk_test_mail(ids[7],'order_tickets','accepted',9);
 UPDATE public.email_messages SET bounced_at=now()-interval '3 hours',delivered_at=now()-interval '1 hour' WHERE message_id=event_mail;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,recipient,event_type,provider_time,message_id)
 VALUES(gen_random_uuid()::text,'test-'||event_mail,'bulk-7@example.invalid','bounce',now()-interval '2 hours',event_mail),
 (gen_random_uuid()::text,'test-'||event_mail,'bulk-7@example.invalid','delivery',now()-interval '1 hour',event_mail);
 -- A source UUID from another order or message kind is never a repair parent.
 root:=pg_temp.bulk_test_mail(ids[8],'order_confirmation','dead',10,cross_order);
 PERFORM pg_temp.bulk_test_mail(ids[8],'order_update','dead',11,root);
 PERFORM pg_temp.assert_email_batch(oc,ids||ARRAY[ids[1],NULL,-1]);
 PERFORM assert_eq(public.order_email_current_issues(ids[1]),'[]'::jsonb,'current delivery resolves historical confirmation');
 PERFORM assert_eq(jsonb_array_length(public.order_email_current_issues(ids[8])),2,'cross-order and cross-kind parents remain independent');
 UPDATE public.email_messages SET workflow_state='accepted',delivered_at=now(),source_version=source_version+1,
  data=data||'{"repair_payment_fingerprint":"stale"}' WHERE message_id=repair;
 PERFORM pg_temp.assert_email_batch(oc,ids);
 PERFORM assert_eq(public.order_email_current_issues(ids[2])#>>'{0,resolution}','stale_delivery','stale snapshot cannot clear the failure');
 PERFORM assert_eq(public.get_order_email_summaries(oc,'{}'),'{}'::jsonb,'empty selection');
 PERFORM assert_eq(public.order_email_current_issues(-1),'[]'::jsonb,'missing order');
 -- Existing scope and role fences still precede the read.
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Other scope',org,un,gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO scope_other;
 INSERT INTO eshop.orders(occasion,order_sequence,order_symbol,state,data)
 VALUES(scope_other,1,public.generate_order_symbol(),'sent','{}') RETURNING id INTO oid;
 BEGIN PERFORM public.get_order_email_summaries(oc,ids||oid); RAISE EXCEPTION 'Foreign order accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_scope_mismatch' THEN RAISE; END IF; END;
 UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=oc AND "user"=actor;
 BEGIN PERFORM public.get_order_email_summaries(oc,ids); RAISE EXCEPTION 'Revoked reader accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_read_denied' THEN RAISE; END IF; END;
 PERFORM assert_false(has_function_privilege('anon','public.order_email_current_issues_bulk(bigint[])','EXECUTE'),'anonymous bulk read denied');
 PERFORM assert_false(has_function_privilege('authenticated','public.order_email_current_issues_bulk(bigint[])','EXECUTE'),'direct client bulk read denied');
 -- The real summary entrypoint must not regress to one provenance query per order.
 UPDATE public.occasion_users SET is_editor_order_view=true WHERE occasion=oc AND "user"=actor;
 EXECUTE $function$
  CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
  LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $body$
  BEGIN RAISE EXCEPTION 'SCALAR_EMAIL_ISSUES_IN_LIST'; END;
  $body$;
 $function$;
 PERFORM assert_eq((SELECT count(*) FROM jsonb_object_keys(public.get_order_email_summaries(oc,ids))),8::bigint,'summary list uses bulk provenance');
END $$;
