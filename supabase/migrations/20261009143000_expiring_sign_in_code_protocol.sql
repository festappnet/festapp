-- Separate invitation proofs never become account passwords.
CREATE TABLE IF NOT EXISTS public.sign_in_codes (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 code_hash text NOT NULL,
 version uuid NOT NULL DEFAULT gen_random_uuid(),
 expires_at timestamptz NOT NULL,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 consumed_at timestamptz
);
ALTER TABLE public.sign_in_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sign_in_codes FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.sign_in_codes TO service_role;

-- Called only within authorized account-domain transactions.
CREATE OR REPLACE FUNCTION public.store_sign_in_code_v1(p_user uuid,p_code text,p_expires timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' OR p_expires IS NULL OR p_expires<=now() THEN RAISE EXCEPTION 'invalid_sign_in_code'; END IF;
 INSERT INTO public.sign_in_codes(user_id,code_hash,expires_at)
 VALUES(p_user,extensions.crypt(p_code,extensions.gen_salt('bf')),least(p_expires,now()+interval '10 minutes'))
 ON CONFLICT(user_id) DO UPDATE SET code_hash=excluded.code_hash,version=gen_random_uuid(),expires_at=excluded.expires_at,attempts=0,consumed_at=NULL;
END $$;
REVOKE ALL ON FUNCTION public.store_sign_in_code_v1(uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.store_sign_in_code_v1(uuid,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.consume_sign_in_code_v1(p_email text,p_organization bigint,p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_code public.sign_in_codes; v_user uuid; v_email text;
BEGIN
 PERFORM public.require_service_role();
 IF p_code IS NULL OR p_code !~ '^[0-9]{6}$' THEN RETURN NULL; END IF;
 SELECT ui.id,au.email INTO v_user,v_email FROM public.user_info ui JOIN auth.users au ON au.id=ui.id
 WHERE ui.organization=p_organization AND lower(ui.email_readonly)=lower(trim(p_email));
 IF v_user IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO v_code FROM public.sign_in_codes WHERE user_id=v_user FOR UPDATE;
 IF NOT FOUND OR v_code.expires_at<=now() OR v_code.consumed_at IS NOT NULL OR v_code.attempts>=5 THEN RETURN NULL; END IF;
 -- Return rather than raise: failed attempts must commit.
 UPDATE public.sign_in_codes SET attempts=attempts+1 WHERE user_id=v_user;
 IF extensions.crypt(p_code,v_code.code_hash) IS DISTINCT FROM v_code.code_hash THEN RETURN NULL; END IF;
 UPDATE public.sign_in_codes SET consumed_at=now() WHERE user_id=v_user;
 RETURN jsonb_build_object('userId',v_user,'authEmail',v_email);
END $$;
REVOKE ALL ON FUNCTION public.consume_sign_in_code_v1(text,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_sign_in_code_v1(text,bigint,text) TO service_role;


CREATE OR REPLACE FUNCTION public.enqueue_account_email(p_operation text,p_domain jsonb,p_context jsonb,p_recipient text,p_sealed jsonb,p_content_hash text,p_dedupe text,p_code text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_context jsonb:=p_context; v_kind text; v_result jsonb; v_domain_result jsonb; v_user uuid:=(p_domain->>'user_id')::uuid; v_source jsonb:='{}'; v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 PERFORM pg_advisory_xact_lock(hashtextextended('email-account:'||(p_context->>'organization')||':'||coalesce(v_user::text,p_dedupe)||':'||p_operation,0));
 -- Command replay is checked before generating/replacing the domain proof.
 SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND dedupe_key=p_dedupe;
 IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true,'domain',
  CASE WHEN p_operation='register' THEN (SELECT jsonb_build_object('code',200,'id',recipient_user) FROM public.email_messages WHERE message_id=v_message) ELSE NULL END); END IF;
 -- Older clients have no stable request ID. Join any unresolved proof instead of rotating it on a timeout retry.
 IF p_operation IN ('reset_token','deletion_confirm') AND v_user IS NOT NULL THEN
  SELECT message_id INTO v_message FROM public.email_messages WHERE organization=(p_context->>'organization')::bigint AND recipient_user=v_user
   AND message_kind=CASE WHEN p_operation='reset_token' THEN 'reset_password' ELSE 'deletion_confirm' END
   AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND expires_at>now() ORDER BY id DESC LIMIT 1;
  IF v_message IS NOT NULL THEN RETURN jsonb_build_object('message_id',v_message,'replayed',true);END IF;
 END IF;
 IF p_operation='reset_token' THEN
  v_kind:='reset_password';
  IF NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=v_user AND organization=(p_context->>'organization')::bigint) THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  INSERT INTO public.user_reset_token("user",token,created_at) VALUES(v_user,(p_domain->>'token')::uuid,now()) ON CONFLICT("user") DO UPDATE SET token=excluded.token,created_at=excluded.created_at;
  v_source:=jsonb_build_object('reset_hash',encode(extensions.digest(p_domain->>'token','sha256'),'hex'));
 ELSIF p_operation='register' THEN
  v_kind:='registration';
  v_domain_result:=public.create_user_from_registration((p_context->>'organization')::bigint,p_recipient,CASE WHEN p_domain ? 'invitation_code' THEN encode(extensions.gen_random_bytes(32),'hex') ELSE p_domain->>'password' END,p_domain->'data',p_domain->>'unit_title');
  IF v_domain_result->>'code'<>'200' THEN RETURN jsonb_build_object('domain',v_domain_result); END IF;
  v_user:=(v_domain_result->>'id')::uuid;
  IF p_domain ? 'invitation_code' THEN
   PERFORM public.store_sign_in_code_v1(v_user,p_domain->>'invitation_code',p_expires);
   v_source:=jsonb_build_object('sign_in_code_version',(SELECT version FROM public.sign_in_codes WHERE user_id=v_user));
  ELSE
   v_source:=jsonb_build_object('password_version',(SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') FROM auth.users WHERE id=v_user));
  END IF;
 ELSIF p_operation='deletion_confirm' THEN
  v_kind:='deletion_confirm';
  v_domain_result:=public.create_account_deletion_request(v_user,(p_context->>'organization')::bigint,p_domain->>'token_hash',p_expires,p_domain->>'masked_email');
  v_source:=jsonb_build_object('deletion_request',v_domain_result->>'requestId');
 ELSIF p_operation='google_mailbox' THEN
  v_kind:='google_mailbox';
  v_domain_result:=public.google_auth_transition_v1('mailbox_send',(p_domain->>'attempt_id')::uuid,p_domain->>'secret_hash',p_domain->'payload');
  IF (v_domain_result->>'organization')::bigint IS DISTINCT FROM (p_context->>'organization')::bigint OR v_domain_result->>'email' IS DISTINCT FROM p_recipient THEN RAISE EXCEPTION 'email_account_scope_mismatch'; END IF;
  v_source:=jsonb_build_object('google_attempt',p_domain->>'attempt_id','mailbox_hash',p_domain#>>'{payload,mailboxHash}');
 ELSE RAISE EXCEPTION 'invalid_account_email_operation'; END IF;
 IF v_user IS NOT NULL THEN v_context:=v_context||jsonb_build_object('recipient_user',v_user); END IF;
 v_result:=public.enqueue_email(v_kind,v_context,p_recipient,v_source||jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now(),post_action=v_source WHERE message_id=(v_result->>'message_id')::uuid;
 RETURN v_result||jsonb_build_object('domain',v_domain_result);
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_sign_in_code_v1(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_answer jsonb; v_context jsonb; v_email text; v_result jsonb; v_existing public.email_messages; v_password_version text;
BEGIN
 -- Reuse the existing hierarchical permission check, including elevated-account protections.
 IF auth.uid() IS NULL OR NOT coalesce(public.get_can_reset_user_password(p_user),false) THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sign-in:'||p_user::text||':'||p_occasion::text,0));
 SELECT * INTO v_existing FROM public.email_messages WHERE recipient_user=p_user AND occasion=p_occasion AND message_kind='sign_in' AND (dedupe_key=p_dedupe OR (workflow_state IN ('pending','preparing','sending','retry_wait','unknown') AND expires_at>now())) ORDER BY id DESC LIMIT 1;
 IF v_existing.id IS NOT NULL THEN
  RETURN jsonb_build_object('message_id',v_existing.message_id,'replayed',true);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user) THEN RAISE EXCEPTION 'user_not_in_occasion'; END IF;
 PERFORM public.store_sign_in_code_v1(p_user,p_password,p_expires);
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT version::text INTO v_password_version FROM public.sign_in_codes WHERE user_id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('sign_in_code_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false OR coalesce((v_feature->>'reminder_is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_sign_in_code_v1(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;
