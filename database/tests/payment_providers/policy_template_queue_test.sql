-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Fixed authored bank instructions are never silently rewritten or dispatched.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); oc bigint:=(x->>'occasion')::bigint; un bigint; wrapper bigint;
 org bigint:=(x->>'organization')::bigint; input jsonb; preview jsonb; queued jsonb; msg public.email_messages;
 clean jsonb; body text:='<main>{{content}}</main>'; original_epoch bigint; sibling_unit bigint; sibling_occasion bigint; sibling_revision text;
BEGIN
 PERFORM assert_false(EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='payment_template_policy_fence' AND NOT tgisinternal),'payment policy has no persistent application trigger');
 PERFORM assert_false(has_table_privilege('authenticated','public.email_templates','INSERT,UPDATE,DELETE'),'authenticated cannot bypass template RPC');
 PERFORM assert_false(has_table_privilege('service_role','public.email_wrappers','INSERT,UPDATE,DELETE'),'worker cannot bypass wrapper owner');
 SELECT unit INTO un FROM public.occasions WHERE id=oc;
 INSERT INTO public.units(organization,title) VALUES(org,'Sousední pořadatel') RETURNING id INTO sibling_unit;
 INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time) VALUES(org,sibling_unit,'Sousední ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id INTO sibling_occasion;
 original_epoch:=coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=oc),0);
 PERFORM public.update_email_template(jsonb_build_object('occasion',oc,'code','TICKET_ORDER_CONFIRMATION','subject','Potvrzení','html','<p>{{fullOrder}}</p>'));
 PERFORM assert_true((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=oc)>original_epoch,'explicit template RPC advances epoch');
 sibling_revision:=public.payment_template_audit_internal(sibling_occasion)->>'revision';
 PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',oc),true);
 INSERT INTO public.email_wrappers(occasion,html) VALUES(oc,body) RETURNING id INTO wrapper;
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',oc),true);
 UPDATE public.email_wrappers SET html=body||'<p>Zaplaťte na účet 123456/0800</p>' WHERE id=wrapper;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 queued:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'unit',un,'occasion',oc),
  (SELECT data->>'email' FROM eshop.orders WHERE id=(x->>'order')::bigint),'{}',gen_random_uuid()::text,
  'TICKET_ORDER_CONFIRMATION',now(),NULL,(x->>'order')::bigint,(SELECT email_payment_version FROM eshop.orders WHERE id=(x->>'order')::bigint));
 SELECT * INTO msg FROM public.email_messages WHERE message_id=(queued->>'message_id')::uuid;
 PERFORM assert_false((msg.data#>>'{collectionAction,allowed}')::boolean,'new disabled intent has no permitted collection');
 PERFORM assert_false(public.email_intent_valid(msg),'newly queued disabled-bank content with fixed account is blocked too');
 UPDATE public.email_messages SET prepared='{"sealed":"immutable-bank-content"}' WHERE id=msg.id RETURNING * INTO msg;
 original_epoch:=(msg.data->>'paymentTemplateEpoch')::bigint;
 PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',oc),true);
 UPDATE public.email_wrappers SET html=body WHERE id=wrapper;
 PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',oc),true);
 UPDATE public.email_wrappers SET html=body||'<p>Zaplaťte na účet 123456/0800</p>' WHERE id=wrapper;
 PERFORM assert_true((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=oc)>original_epoch,'A-B-A edits have a monotonic epoch');
 PERFORM assert_false(public.email_intent_valid(msg),'restoring identical content never revives an old encrypted snapshot');
 PERFORM public.payment_template_write_scope_internal(jsonb_build_object('occasion',oc),true);
 UPDATE public.email_wrappers SET html=body WHERE id=wrapper;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SET LOCAL ROLE authenticated;
 input:=input||'{"mode":"enabled"}'; preview:=public.preview_payment_method_policy(input);
 PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(msg),'repair and policy re-enable do not revive the old snapshot');
 PERFORM assert_eq(public.payment_template_audit_internal(sibling_occasion)->>'revision',sibling_revision,'unit A template edits do not invalidate sibling B review or queued snapshots');
 queued:=public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'unit',un,'occasion',oc),msg.recipient,'{}',msg.dedupe_key,
  msg.code,now(),NULL,msg.order_id,msg.source_version);
 PERFORM assert_eq(queued->>'message_id',msg.message_id::text,'derived template/policy epochs do not change the immutable business dedupe identity');
 BEGIN
  PERFORM public.enqueue_email('order_confirmation',jsonb_build_object('organization',org,'unit',un,'occasion',oc),msg.recipient,'{"different":true}',msg.dedupe_key,
   msg.code,now(),NULL,msg.order_id,msg.source_version);
  RAISE EXCEPTION 'different business data replayed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'email_dedupe_conflict' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT prepared FROM public.email_messages WHERE id=msg.id),'{"sealed":"immutable-bank-content"}'::jsonb,'audit snapshot remains byte-identical');
END $$;
