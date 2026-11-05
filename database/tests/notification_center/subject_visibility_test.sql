-- test-setup: database/functions/notification_center/subject_visibility.sql
BEGIN;
SELECT set_config('request.jwt.claim.role','service_role',true);
SELECT set_config('festapp.email_wake','scheduled',true);
DO $$
DECLARE unit_id bigint; org bigint; other_org bigint; oc bigint; other_oc bigint; oid bigint; other_oid bigint;
 hidden uuid:=gen_random_uuid(); visible uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); message uuid;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Notification visibility') RETURNING id INTO org;
 INSERT INTO public.organizations(title) VALUES('Other notification tenant') RETURNING id INTO other_org;
 INSERT INTO auth.users(id) VALUES(hidden),(visible),(outsider);
 INSERT INTO public.user_info(id,organization,email_readonly)
 VALUES(hidden,org,' Hidden@Example.Invalid '),(visible,org,'visible@example.invalid'),(outsider,other_org,'outside@example.invalid');
 INSERT INTO public.units(title,organization) VALUES('Notification unit',org) RETURNING id INTO unit_id;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time)
 VALUES(org,unit_id,'Visibility',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO oc;
 INSERT INTO public.occasions(organization,title,link,start_time,end_time)
 VALUES(other_org,'Other visibility',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO other_oc;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(oc,'ordered',public.generate_order_symbol(),1,'{"email":" hidden@example.invalid "}') RETURNING id INTO oid;
 INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 VALUES(other_oc,'ordered',public.generate_order_symbol(),1,'{"email":"hidden@example.invalid"}') RETURNING id INTO other_oid;
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'order_created',jsonb_build_object('orderId',oid)),'organization without hidden members retains order activity');
 INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES(org,hidden,true),(org,visible,false),(other_org,outsider,true);
 PERFORM assert_false(public.notification_center_subject_visible_internal(org,'occasion_joined',jsonb_build_object('userId',hidden)),'hidden membership is private');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'occasion_joined',jsonb_build_object('userId',visible)),'visible membership remains visible');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'occasion_joined',jsonb_build_object('userId',outsider)),'another tenant hidden membership cannot affect this tenant');
 PERFORM assert_false(public.notification_center_subject_visible_internal(org,'order_created',jsonb_build_object('orderId',oid)),'hidden order contact matches case and whitespace');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'order_created',jsonb_build_object('orderId',other_oid)),'order contact lookup is tenant bound');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'order_created','{"orderId":"invalid"}'),'malformed order identifier is safe');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'form_closed','{}'),'unrelated event remains visible');

 message:=(public.enqueue_email('custom',jsonb_build_object('organization',org,'occasion',oc),
  'visible@example.invalid','{}','notification-visibility-test')->>'message_id')::uuid;
 UPDATE public.email_messages SET recipient_user=hidden WHERE message_id=message;
 PERFORM assert_false(public.notification_center_subject_visible_internal(org,'email_problem',jsonb_build_object('messageId',message)),'hidden email recipient identity is private');
 UPDATE public.email_messages SET recipient_user=NULL,recipient=' HIDDEN@example.invalid ' WHERE message_id=message;
 PERFORM assert_false(public.notification_center_subject_visible_internal(org,'email_problem',jsonb_build_object('messageId',message)),'hidden email address is private');
 UPDATE public.email_messages SET recipient='visible@example.invalid',order_id=oid WHERE message_id=message;
 PERFORM assert_false(public.notification_center_subject_visible_internal(org,'email_problem',jsonb_build_object('messageId',message)),'hidden linked order contact is private');
 UPDATE public.email_messages SET order_id=other_oid WHERE message_id=message;
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'email_problem',jsonb_build_object('messageId',message)),'email order lookup cannot cross tenant boundaries');
 PERFORM assert_true(public.notification_center_subject_visible_internal(other_org,'email_problem',jsonb_build_object('messageId',message)),'email lookup cannot cross tenant boundaries');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'email_problem','{"messageId":"invalid"}'),'malformed message identifier is safe');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'form_closed',jsonb_build_object('messageId',message)),'only email incidents inspect message identifiers');
 -- A hidden membership must belong to a profile in the same organization.
 UPDATE public.user_info SET organization=other_org WHERE id=hidden;
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'order_created',jsonb_build_object('orderId',oid)),'foreign profile cannot hide an order');
 PERFORM assert_true(public.notification_center_subject_visible_internal(org,'occasion_joined',jsonb_build_object('userId',hidden)),'foreign profile cannot hide a membership');
 PERFORM assert_false(has_function_privilege('authenticated','public.notification_center_subject_visible_internal(bigint,text,jsonb)','execute'),'private subject helper is not a client API');
 PERFORM assert_false(has_function_privilege('anon','public.notification_center_subject_visible_internal(bigint,text,jsonb)','execute'),'private subject helper is not anonymous');
END $$;
ROLLBACK;
