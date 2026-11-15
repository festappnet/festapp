CREATE FUNCTION pg_temp.customer_fixture() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x jsonb:=pg_temp.payment_fixture(); fid bigint:=(x->>'form')::bigint; field bigint; read_token text:=encode(extensions.gen_random_bytes(32),'hex');
BEGIN
 UPDATE public.occasions SET features=features||'[{"code":"customer_self_service","is_enabled":true}]' WHERE id=(x->>'occasion')::bigint;
 INSERT INTO public.form_fields(form,title,type,is_hidden,is_ticket_field,is_required,"order") VALUES(fid,'Phone','phone',false,false,true,2) RETURNING id INTO field;
 PERFORM public.save_customer_order_policy_internal(fid,jsonb_build_object('edit',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day','fields',jsonb_build_array(jsonb_build_object('id',field,'type','phone'))),
  'cancel',jsonb_build_object('enabled',true,'allowed_until',now()+interval '1 day','mode','automatic','reason_required',false,'refund_mode','automatic')));
 PERFORM public.issue_order_overview_internal((x->>'order')::bigint,jsonb_build_object('tokenHash',encode(extensions.digest(read_token,'sha256'),'hex'),'contentHash',repeat('a',64),'sealed','{}'::jsonb),extensions.gen_random_uuid());
 RETURN x||jsonb_build_object('field',field,'readToken',read_token);
END $$;
CREATE FUNCTION pg_temp.customer_cap(x jsonb,op text,payload jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE token text:=encode(extensions.gen_random_bytes(32),'hex');
BEGIN
 INSERT INTO eshop.customer_order_change_capabilities(token_hash,parent_hash,organization_id,form_id,order_id,operation,proposal_hash,policy_revision,feature_epoch,expires_at)
 SELECT encode(extensions.digest(token,'sha256'),'hex'),encode(extensions.digest(x->>'readToken','sha256'),'hex'),(x->>'organization')::bigint,(x->>'form')::bigint,(x->>'order')::bigint,op,
 encode(extensions.digest(payload::text,'sha256'),'hex'),p.revision,o.customer_self_service_epoch,now()+interval '10 minutes'
 FROM eshop.customer_order_change_policies p JOIN public.forms f ON f.id=p.form_id JOIN public.occasions o ON o.id=f.occasion WHERE p.form_id=(x->>'form')::bigint;
 RETURN token;
END $$;
