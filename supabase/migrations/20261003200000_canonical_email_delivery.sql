-- Canonical email cutover. Maintenance and reviewed function bundle required. Starts paused.
BEGIN;

-- Source: database/functions/emails/email_schema.sql
-- Cutover only under maintenance: old senders must be stopped first.
ALTER TABLE public.queue_emails RENAME TO email_messages;
ALTER SEQUENCE public.queue_emails_id_seq RENAME TO email_messages_id_seq;
REVOKE ALL ON SEQUENCE public.email_messages_id_seq FROM PUBLIC,anon,authenticated;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_pkey TO email_messages_pkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_occasion_fkey TO email_messages_occasion_fkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_organization_fkey TO email_messages_organization_fkey;
ALTER TABLE public.email_messages RENAME CONSTRAINT queue_emails_unit_fkey TO email_messages_unit_fkey;
ALTER INDEX public.queue_emails_ticket_order_command_idx RENAME TO email_messages_ticket_order_command_idx;
ALTER TABLE public.email_messages
  ADD COLUMN message_id uuid NOT NULL DEFAULT extensions.gen_random_uuid(),
  ADD COLUMN message_kind text,
  ADD COLUMN dedupe_key text,
  ADD COLUMN input_hash text,
  ADD COLUMN workflow_state text NOT NULL DEFAULT 'pending',
  ADD COLUMN recipient text,
  ADD COLUMN recipient_user uuid,
  ADD COLUMN order_id bigint,
  ADD COLUMN source_version bigint,
  ADD COLUMN priority integer NOT NULL DEFAULT 50,
  ADD COLUMN expires_at timestamptz,
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_until timestamptz,
  ADD COLUMN prepared jsonb,
  ADD COLUMN prepared_hash text,
  ADD COLUMN prepared_at timestamptz,
  ADD COLUMN provider_message_id text,
  ADD COLUMN accepted_at timestamptz,
  ADD COLUMN delivered_at timestamptz,
  ADD COLUMN bounced_at timestamptz,
  ADD COLUMN complained_at timestamptz,
  ADD COLUMN opened_at timestamptz,
  ADD COLUMN clicked_at timestamptz,
  ADD COLUMN provider_failure text,
  ADD COLUMN feedback_pending boolean NOT NULL DEFAULT false,
  ADD COLUMN tracking_policy text NOT NULL DEFAULT 'disabled',
  ADD COLUMN post_action jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN post_action_state text NOT NULL DEFAULT 'pending';
ALTER TABLE eshop.orders ADD COLUMN email_payment_version bigint NOT NULL DEFAULT 0;
ALTER TABLE eshop.payment_info ADD COLUMN email_reminder_version bigint NOT NULL DEFAULT 0;
UPDATE public.email_messages SET
  message_id = (substr(md5('festapp:email:'||id),1,8)||'-'||substr(md5('festapp:email:'||id),9,4)||'-4'||substr(md5('festapp:email:'||id),14,3)||'-8'||substr(md5('festapp:email:'||id),18,3)||'-'||substr(md5('festapp:email:'||id),21,12))::uuid,
  dedupe_key='legacy:'||id,
  message_kind=CASE code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation'
    WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
    WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder'
    WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
    ELSE 'legacy_unknown' END,
  order_id=coalesce((data->>'order_id')::bigint,(data#>>'{ticket_order,order,id}')::bigint),
  workflow_state=CASE WHEN target_time='infinity' THEN 'blocked'
    WHEN code NOT IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO') OR processing_at IS NOT NULL OR attempt_count>0 THEN 'unknown' ELSE 'pending' END,
  tracking_policy=CASE WHEN code IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO') THEN 'open' ELSE 'disabled' END,
  input_hash=encode(extensions.digest(coalesce(data,'{}')::text,'sha256'),'hex');
UPDATE public.email_messages m SET recipient=o.data->>'email',source_version=CASE WHEN m.message_kind='order_reminder' THEN pi.email_reminder_version ELSE o.email_payment_version END
 FROM eshop.orders o LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=m.order_id;
ALTER TABLE public.email_messages ALTER COLUMN message_kind SET NOT NULL;
ALTER TABLE public.email_messages ALTER COLUMN dedupe_key SET NOT NULL;
ALTER TABLE public.email_messages ALTER COLUMN input_hash SET NOT NULL;
ALTER TABLE public.email_messages ADD CONSTRAINT email_workflow CHECK(workflow_state IN
 ('blocked','pending','preparing','sending','accepted','retry_wait','unknown','dead','cancelled','suppressed','expired'));
CREATE UNIQUE INDEX email_message_uuid ON public.email_messages(message_id);
CREATE UNIQUE INDEX email_message_dedupe ON public.email_messages(organization,message_kind,dedupe_key);
CREATE INDEX email_due ON public.email_messages(priority,target_time,id) WHERE workflow_state IN ('pending','retry_wait');
CREATE INDEX email_active_leases ON public.email_messages(lease_until) WHERE workflow_state IN ('preparing','sending');
CREATE INDEX email_order_summary ON public.email_messages(occasion,order_id,created_at DESC);
CREATE UNIQUE INDEX email_provider_message ON public.email_messages(provider_message_id) WHERE provider_message_id IS NOT NULL;
CREATE TABLE public.email_attempts (
 attempt_id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), message_id uuid NOT NULL REFERENCES public.email_messages(message_id),
 lease_token uuid NOT NULL, state text NOT NULL CHECK(state IN ('preparing','sending','accepted','not_accepted','unknown','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(), began_at timestamptz, finished_at timestamptz, provider_message_id text,
 error_code text, UNIQUE(message_id,lease_token));
CREATE TABLE public.email_delivery_events (
 event_key text PRIMARY KEY, provider_message_id text NOT NULL, attempt_id uuid, recipient text NOT NULL,
 event_type text NOT NULL CHECK(event_type IN ('send','delivery','delay','bounce','complaint','reject','rendering_failure','open','click')),
 provider_time timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now(), hard_bounce boolean NOT NULL DEFAULT false, invalid_recipient boolean NOT NULL DEFAULT false,
 message_id uuid REFERENCES public.email_messages(message_id));
CREATE INDEX email_event_history ON public.email_delivery_events(message_id,provider_time);
CREATE INDEX email_attempt_history ON public.email_attempts(created_at);
CREATE INDEX email_unmatched ON public.email_delivery_events(provider_message_id) WHERE message_id IS NULL;
CREATE TABLE public.email_suppressions (recipient text PRIMARY KEY, reason text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
-- One account/region authority for all tenants and gateway instances. No tenant key.
CREATE TABLE public.email_capacity (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), account_id text, region text,
 paused boolean NOT NULL DEFAULT true, worker_url text, quota_refresh_until timestamptz, quota_at timestamptz, max_rate numeric, daily_quota numeric,
 provider_sent_24h numeric, shared_account boolean NOT NULL DEFAULT true, allocated_rate numeric, allocated_daily numeric,
 provider_outage_streak integer NOT NULL DEFAULT 0 CHECK(provider_outage_streak>=0), probe_until timestamptz, probe_attempt uuid,
 next_send_at timestamptz NOT NULL DEFAULT now(), circuit_until timestamptz, rate_factor numeric NOT NULL DEFAULT 1 CHECK(rate_factor>0 AND rate_factor<=1),
 max_preparing integer NOT NULL DEFAULT 2 CHECK(max_preparing BETWEEN 1 AND 8), max_sending integer NOT NULL DEFAULT 2 CHECK(max_sending BETWEEN 1 AND 8),
 wake_error text, heartbeat_at timestamptz);
INSERT INTO public.email_capacity(singleton) VALUES(true);
ALTER TABLE public.email_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_capacity ENABLE ROW LEVEL SECURITY;
-- Remove inherited queue policies: internal-only tables, explicit read RPCs.
DO $$ DECLARE p record; BEGIN FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='email_messages' LOOP
 EXECUTE format('DROP POLICY %I ON public.email_messages',p.policyname); END LOOP; END $$;
REVOKE ALL ON public.email_messages,public.email_attempts,public.email_delivery_events,public.email_suppressions,public.email_capacity FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.email_messages,public.email_attempts,public.email_delivery_events,public.email_suppressions,public.email_capacity TO service_role;
CREATE TABLE public.email_confirmation_receipts (
 token_hash text PRIMARY KEY CHECK(length(token_hash)=64),message_id uuid NOT NULL REFERENCES public.email_messages(message_id),
 expires_at timestamptz NOT NULL,reads integer NOT NULL DEFAULT 0);
ALTER TABLE public.email_confirmation_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.email_confirmation_receipts FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.email_confirmation_receipts TO service_role;

-- A public client must not mint or read the machine proof used by email/other system workers.
REVOKE ALL ON public.request_secrets FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.request_secrets TO service_role;
REVOKE ALL ON FUNCTION public.generate_request_secret(integer),public.check_request_secret(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.generate_request_secret(integer),public.check_request_secret(text) TO service_role;


-- Source: database/functions/users/get_can_reset_user_password.sql
CREATE OR REPLACE FUNCTION public.get_can_reset_user_password(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_current_user_id uuid:=auth.uid();v_has_permission boolean:=false;
v_is_unit_manager_path boolean;v_is_occasion_manager_path boolean;v_target_has_elevated_privileges boolean;v_target_is_org_admin boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_user_id) THEN RETURN false; END IF;
    -- Priority 1: Self-Reset. A user can always change their own password.
    IF v_current_user_id = p_user_id THEN
        v_has_permission := TRUE;
    END IF;

    -- Priority 2: Organization admin for a user belonging to their organization.
    -- A merged user may have a different home organization in user_info while
    -- participating in this organization's occasion or unit.
    IF NOT v_has_permission THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.organization_users cou
            WHERE cou."user" = v_current_user_id
              AND cou.is_admin = TRUE
              AND (
                  EXISTS (
                      SELECT 1 FROM public.user_info tui
                      WHERE tui.id = p_user_id
                        AND tui.organization = cou.organization
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.occasion_users tou
                      JOIN public.occasions o ON o.id = tou.occasion
                      WHERE tou."user" = p_user_id
                        AND o.organization = cou.organization
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.unit_users tu
                      JOIN public.units u ON u.id = tu.unit
                      WHERE tu."user" = p_user_id
                        AND u.organization = cou.organization
                  )
              )
        ) INTO v_has_permission;
    END IF;

    -- Priority 3: Unit Manager Path (with new negative check).
    IF NOT v_has_permission THEN
        -- Step 3a: Check if the current user has Unit Manager rights over the target user.
        WITH target_user_units AS (
            SELECT unit AS unit_id FROM public.unit_users WHERE "user" = p_user_id
            UNION
            SELECT o.unit AS unit_id FROM public.occasion_users ou JOIN public.occasions o ON ou.occasion = o.id WHERE ou."user" = p_user_id
        )
        SELECT EXISTS (
            SELECT 1
            FROM public.unit_users uu
            JOIN target_user_units tuu ON uu.unit = tuu.unit_id
            WHERE uu."user" = v_current_user_id AND uu.is_manager = TRUE
        ) INTO v_is_unit_manager_path;

        IF v_is_unit_manager_path THEN
            -- Step 3b: **NEW NEGATIVE CHECK**. A Unit Manager cannot change an Org Admin's password.
            SELECT EXISTS (
                SELECT 1 FROM public.organization_users
                WHERE "user" = p_user_id AND is_admin = TRUE
            ) INTO v_target_is_org_admin;

            -- Grant permission only if the target user is NOT an Organization Admin.
            IF NOT v_target_is_org_admin THEN
                v_has_permission := TRUE;
            END IF;
        END IF;
    END IF;

    -- Priority 4: Unit editors can manage ordinary users in their unit, but
    -- cannot reset credentials of users with elevated roles anywhere.
    IF NOT v_has_permission THEN
        SELECT EXISTS (
            SELECT 1 FROM public.unit_users editor_uu
            WHERE editor_uu."user" = v_current_user_id
              AND editor_uu.is_editor = TRUE
              AND (
                  EXISTS (
                      SELECT 1 FROM public.unit_users target_uu
                      WHERE target_uu."user" = p_user_id
                        AND target_uu.unit = editor_uu.unit
                  )
                  OR EXISTS (
                      SELECT 1 FROM public.occasion_users target_ou
                      JOIN public.occasions o ON o.id = target_ou.occasion
                      WHERE target_ou."user" = p_user_id
                        AND o.unit = editor_uu.unit
                  )
              )
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.organization_users target_org
            WHERE target_org."user" = p_user_id AND target_org.is_admin = TRUE
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.unit_users target_unit
            WHERE target_unit."user" = p_user_id
              AND (target_unit.is_manager OR target_unit.is_editor OR target_unit.is_editor_view)
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.occasion_users target_occasion
            WHERE target_occasion."user" = p_user_id
              AND (target_occasion.is_manager OR target_occasion.is_editor
                   OR target_occasion.is_editor_view OR target_occasion.is_editor_order
                   OR target_occasion.is_editor_order_view)
        ) INTO v_has_permission;
    END IF;

    -- Priority 5: Occasion Manager Path (with expanded security check).
    IF NOT v_has_permission THEN
        -- Step 4a: Check if a direct manager->user link exists on any single occasion.
        SELECT EXISTS (
          SELECT 1 FROM public.occasion_users AS manager_ou
          JOIN public.occasion_users AS target_ou ON manager_ou.occasion = target_ou.occasion
          WHERE manager_ou."user" = v_current_user_id
            AND manager_ou.is_manager = TRUE
            AND target_ou."user" = p_user_id
        ) INTO v_is_occasion_manager_path;

        IF v_is_occasion_manager_path THEN
            -- Step 4b: EXPANDED NEGATIVE CHECK. Target must not have any elevated privileges.
            SELECT EXISTS (
              SELECT 1 FROM public.unit_users
              WHERE "user" = p_user_id AND (is_manager = TRUE OR is_editor = TRUE OR is_editor_view = TRUE)
            ) INTO v_target_has_elevated_privileges;

            IF NOT v_target_has_elevated_privileges THEN
                SELECT EXISTS (
                    SELECT 1 FROM public.organization_users
                    WHERE "user" = p_user_id AND is_admin = TRUE
                ) INTO v_target_has_elevated_privileges;
            END IF;

            IF NOT v_target_has_elevated_privileges THEN
                v_has_permission := TRUE;
            END IF;
        END IF;
    END IF;

    -- Final permission enforcement.
 RETURN v_has_permission;
END $$;
REVOKE ALL ON FUNCTION public.get_can_reset_user_password(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_can_reset_user_password(uuid) TO authenticated,service_role;


-- Source: database/functions/users/reset_user_password.sql
CREATE OR REPLACE FUNCTION reset_user_password(p_user_id uuid, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_current_user_id uuid := auth.uid();
  v_has_permission boolean := false;
  v_encrypted_pw text;
  v_is_unit_manager_path boolean;
  v_is_occasion_manager_path boolean;
  v_target_has_elevated_privileges boolean;
  v_target_is_org_admin boolean;
BEGIN
    -- =================================================================
    -- 1. INPUT VALIDATION
    -- =================================================================
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4000, 'message', 'Input data is invalid: User ID is missing')::text;
    END IF;

    IF p_password IS NULL OR trim(p_password) = '' THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4000, 'message', 'Input data is invalid: Password cannot be empty')::text;
    END IF;

    -- =================================================================
    -- 2. USER EXISTENCE CHECK
    -- =================================================================
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION '%',
            jsonb_build_object('code', 4040, 'message', 'User not found')::text;
    END IF;


    -- =================================================================
    -- 3. PERMISSION CHECKS (HIERARCHICAL LOGIC)
    -- =================================================================
    -- The function checks for permissions in a specific, prioritized order.

    IF NOT public.get_can_reset_user_password(p_user_id) THEN
        RAISE EXCEPTION '%',jsonb_build_object('code',4030,'message','Permission denied. You do not have the required privileges to reset this user''s password.')::text;
    END IF;

    -- =================================================================
    -- 4. PASSWORD UPDATE
    -- =================================================================
    v_encrypted_pw := crypt(p_password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = v_encrypted_pw
    WHERE auth.users.id = p_user_id;

    -- =================================================================
    -- 5. SUCCESS RESPONSE
    -- =================================================================
    RETURN jsonb_build_object('code', 200, 'message', 'Password has been successfully updated.');

EXCEPTION
    WHEN OTHERS THEN
        RETURN CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::jsonb
            ELSE jsonb_build_object('code', 5000, 'message', SQLERRM)
        END;
END;
$$;


-- Source: database/functions/emails/email_domain.sql
-- Invoker-only helper. Its ACL prevents public use; public domain commands own permissions.
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_tickets' THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false';
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_paid_order_tickets(p_order bigint) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_occ public.occasions;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_order FOR UPDATE;
 SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
 IF v_order.state='paid' AND v_occ.is_order_synchronization_enabled AND v_order.data ? 'email'
 AND (coalesce(v_order.price,0)<>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_occ.features) f WHERE f->>'code'='ticket' AND (f->>'is_enabled')::boolean)) THEN
  PERFORM public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',p_order),v_occ.organization,v_occ.id,v_occ.unit);
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_order_email_intents(p_order bigint) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='payment_changed',lease_token=NULL,lease_until=NULL
 WHERE order_id=p_order AND message_kind IN ('order_payment_notice','order_tickets','order_reminder') AND workflow_state IN ('pending','retry_wait','blocked','preparing');
END $$;

CREATE OR REPLACE FUNCTION public.apply_email_post_actions(p_message uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m record; v_result jsonb;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 FOR m IN SELECT * FROM public.email_messages WHERE workflow_state='accepted' AND post_action_state='pending'
 AND (p_message IS NULL OR message_id=p_message) ORDER BY id LIMIT 20 LOOP
  -- Domain producers lock order before message; follow that order before owning the projection.
  IF m.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=m.order_id FOR UPDATE; END IF;
  SELECT * INTO m FROM public.email_messages WHERE id=m.id AND workflow_state='accepted' AND post_action_state='pending' FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN CONTINUE; END IF;
  BEGIN
   IF m.message_kind='order_tickets' THEN
    -- Never resurrect a used/storno ticket or a reverted/cancelled order.
    UPDATE eshop.orders SET state='sent',updated_at=now() WHERE id=m.order_id AND state='paid' AND email_payment_version=m.source_version;
    IF FOUND THEN
     UPDATE eshop.tickets t SET state='sent',updated_at=now()
     FROM eshop.order_product_ticket opt WHERE opt.ticket=t.id AND opt."order"=m.order_id AND t.state='paid'
      AND t.id IN (SELECT jsonb_array_elements_text(m.post_action->'ticket_ids')::bigint);
     INSERT INTO eshop.orders_history("order",data,state,price,currency_code) SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=m.order_id;
    END IF;
   END IF;
   IF m.message_kind='app_links' AND m.recipient_user IS NOT NULL THEN PERFORM public.mark_app_links_sent(m.occasion,m.recipient_user); END IF;
   IF m.message_kind='deletion_confirm' AND m.post_action ? 'deletion_request' THEN PERFORM public.set_account_deletion_email_state((m.post_action->>'deletion_request')::uuid,true); END IF;
   IF m.post_action ? 'history_id' THEN PERFORM public.add_sent_to_customer_flag((m.post_action->>'history_id')::bigint); END IF;
   IF m.message_kind='order_reminder' THEN
    UPDATE eshop.payment_info SET data=coalesce(data,'{}')||'{"current_version_reminded":true}'::jsonb
    WHERE id=(m.post_action->>'payment_info_id')::bigint AND email_reminder_version=m.source_version;
   END IF;
   UPDATE public.email_messages SET post_action_state='done',last_error=CASE WHEN last_error='post_action_failed' THEN NULL ELSE last_error END WHERE id=m.id;
  EXCEPTION WHEN OTHERS THEN UPDATE public.email_messages SET last_error='post_action_failed' WHERE id=m.id; END;
 END LOOP;
END $$;

-- Account-domain writes and their durable intent are one DB transaction.
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
  v_domain_result:=public.create_user_from_registration((p_context->>'organization')::bigint,p_recipient,p_domain->>'password',p_domain->'data',p_domain->>'unit_title');
  IF v_domain_result->>'code'<>'200' THEN RETURN jsonb_build_object('domain',v_domain_result); END IF;
  v_user:=(v_domain_result->>'id')::uuid;
  v_source:=jsonb_build_object('password_version',(SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') FROM auth.users WHERE id=v_user));
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
REVOKE ALL ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_account_email(text,jsonb,jsonb,text,jsonb,text,text,text,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.reset_password_and_enqueue_email(p_user uuid,p_password text,p_occasion bigint,p_sealed jsonb,p_content_hash text,p_dedupe text,p_expires timestamptz)
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
 v_answer:=public.reset_user_password(p_user,p_password);
 IF v_answer->>'code'<>'200' THEN RAISE EXCEPTION 'password_reset_denied'; END IF;
 SELECT jsonb_build_object('organization',organization,'occasion',id,'unit',unit,'recipient_user',p_user) INTO v_context FROM public.occasions WHERE id=p_occasion;
 v_email:=public.get_user_delivery_email(p_user);
 SELECT encode(extensions.digest(encrypted_password,'sha256'),'hex') INTO v_password_version FROM auth.users WHERE id=p_user;
 v_result:=public.enqueue_email('sign_in',v_context,v_email,jsonb_build_object('password_version',v_password_version,'content_hash',p_content_hash),p_dedupe,'SIGN_IN_CODE',now(),p_expires);
 UPDATE public.email_messages SET prepared=p_sealed,prepared_hash=encode(extensions.digest(p_sealed::text,'sha256'),'hex'),prepared_at=now() WHERE message_id=(v_result->>'message_id')::uuid;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reset_password_and_enqueue_email(uuid,text,bigint,jsonb,text,text,timestamptz) TO authenticated;


-- Source: database/functions/emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
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

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now();
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY priority-greatest(0,floor(extract(epoch FROM now()-created_at)/300))::integer,
 (SELECT max(a.created_at) FROM public.email_attempts a JOIN public.email_messages served ON served.message_id=a.message_id WHERE served.organization=m.organization) NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision); END IF;
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds'; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05);
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100);END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;


-- Source: database/functions/emails/email_reporting.sql
CREATE OR REPLACE FUNCTION public.get_email_occasion_context(p_occasion bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'unit',unit) FROM public.occasions WHERE id=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_email_occasion_context(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_occasion_context(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.email_reporting_state(m public.email_messages) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT CASE WHEN m.complained_at IS NOT NULL THEN 'complaint' WHEN m.bounced_at IS NOT NULL THEN 'bounce'
 WHEN m.last_error='post_action_failed' THEN 'post_action_failed' WHEN m.provider_failure IN ('reject','rendering_failure') THEN m.provider_failure
 WHEN m.workflow_state IN ('unknown','dead','suppressed','retry_wait') THEN m.workflow_state
 WHEN m.clicked_at IS NOT NULL THEN 'click' WHEN m.opened_at IS NOT NULL THEN 'open' WHEN m.delivered_at IS NOT NULL THEN 'delivery'
 WHEN m.provider_failure='delay' THEN 'delay' ELSE m.workflow_state END;
$$;
REVOKE ALL ON FUNCTION public.email_reporting_state(public.email_messages) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.email_reporting_state(public.email_messages) TO service_role;

CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH messages AS (
 SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion
  AND workflow_state NOT IN ('cancelled','expired')),
 ranked AS (
 SELECT *,CASE WHEN reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed') THEN 0
 WHEN workflow_state IN ('pending','preparing','sending','blocked') AND target_time<=now() THEN 1
 WHEN workflow_state='accepted' THEN 2 ELSE 3 END rank FROM messages)
 SELECT coalesce(jsonb_object_agg(r.order_id,jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'message_id',r.message_id,'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),
 'scheduled_at',r.target_time,'attention_count',(SELECT count(*) FROM ranked n WHERE n.order_id=r.order_id AND rank=0),'loaded_at',now(),
 'messages',(SELECT coalesce(jsonb_agg(jsonb_build_object('kind',message_kind,'state',reporting_state,'at',coalesce(delivered_at,accepted_at,created_at)) ORDER BY created_at DESC),'[]') FROM ranked n WHERE n.order_id=r.order_id))
),'{}'::jsonb) INTO v_summary FROM (SELECT DISTINCT ON (order_id) * FROM ranked ORDER BY order_id,rank,created_at DESC,id DESC) r;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_order_email_summary(p_order bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_occ bigint;
BEGIN
 SELECT occasion INTO v_occ FROM eshop.orders WHERE id=p_order;
 IF v_occ IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;
 RETURN coalesce(public.get_order_email_summaries(v_occ,ARRAY[p_order])->p_order::text,jsonb_build_object('state','unavailable','messages','[]'::jsonb,'loaded_at',now()));
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summary(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summary(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.email_report_allowed(p_org bigint,p_occasion bigint,p_user uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce(public.get_is_admin_on_organization(p_org),false) OR
 (p_occasion IS NOT NULL AND EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND organization=p_org)
 AND coalesce(public.get_is_editor_order_view_on_occasion(p_occasion),false)
 AND (p_user IS NULL OR EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_user)));
$$;
REVOKE ALL ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.email_report_allowed(bigint,bigint,uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_delivery_page(p_occasion bigint,p_before bigint DEFAULT NULL,p_limit integer DEFAULT 30,p_order bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_state text DEFAULT NULL,p_organization bigint DEFAULT NULL,p_user uuid DEFAULT NULL,p_since timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion,p_user),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'invalid_page_limit'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY id DESC),'[]') INTO v_result FROM (
 SELECT id,message_id,message_kind,order_id,created_at,accepted_at,delivered_at,bounced_at,complained_at,opened_at,clicked_at,
 public.email_reporting_state(m) state,tracking_policy,post_action_state,last_error FROM public.email_messages m
 WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion OR (p_user IS NOT NULL AND occasion IS NULL))
 AND (p_user IS NULL OR recipient_user=p_user) AND (p_since IS NULL OR created_at>=p_since) AND (p_before IS NULL OR id<p_before) AND (p_order IS NULL OR order_id=p_order)
 AND (p_kind IS NULL OR message_kind=p_kind) AND (p_state IS NULL OR public.email_reporting_state(m)=p_state)
 ORDER BY id DESC LIMIT p_limit) x;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_page(bigint,bigint,integer,bigint,text,text,bigint,uuid,timestamptz) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_email_delivery_detail(p_message uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_id IS NULL THEN RAISE EXCEPTION 'email_detail_not_available'; END IF;
 IF NOT coalesce(public.email_report_allowed(m.organization,m.occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN jsonb_build_object('message',jsonb_build_object('id',m.message_id,'kind',m.message_kind,'state',public.email_reporting_state(m),'tracking_policy',m.tracking_policy,'opened_at',m.opened_at,'clicked_at',m.clicked_at,'post_action',m.post_action_state,'last_error',m.last_error,'provider_id',m.provider_message_id,'requested_by',m.data->>'requested_by'),
 'attempts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',attempt_id,'state',state,'at',created_at,'error',error_code,'provider_id',provider_message_id) ORDER BY created_at),'[]') FROM public.email_attempts WHERE message_id=p_message),
 'events',(SELECT coalesce(jsonb_agg(jsonb_build_object('type',event_type,'at',provider_time) ORDER BY provider_time),'[]') FROM (SELECT event_type,provider_time FROM public.email_delivery_events WHERE message_id=p_message ORDER BY provider_time DESC LIMIT 100) e));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_detail(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_detail(uuid) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.create_email_confirmation_receipt(p_command uuid,p_order bigint,p_hash text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid;
BEGIN
 PERFORM public.require_service_role();
 SELECT message_id INTO v_message FROM public.email_messages WHERE message_kind='order_confirmation' AND data->>'command_id'=p_command::text AND order_id=p_order;
 IF v_message IS NULL THEN RETURN false; END IF;
 INSERT INTO public.email_confirmation_receipts(token_hash,message_id,expires_at) VALUES(p_hash,v_message,now()+interval '15 minutes');
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_email_confirmation_receipt(uuid,bigint,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_email_confirmation_status(p_hash text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_message uuid; m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_confirmation_receipts SET reads=reads+1 WHERE token_hash=p_hash AND expires_at>now() AND reads<15 RETURNING message_id INTO v_message;
 IF v_message IS NULL THEN RETURN 'unavailable'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=v_message;
 RETURN CASE WHEN EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id AND e.invalid_recipient AND e.recipient=lower(m.recipient)) THEN 'invalid_email'
 WHEN m.bounced_at IS NOT NULL OR m.complained_at IS NOT NULL OR m.provider_failure IN ('reject','rendering_failure') THEN 'failed'
 WHEN m.delivered_at IS NOT NULL THEN 'delivered' WHEN m.workflow_state='accepted' THEN 'accepted' WHEN m.workflow_state IN ('unknown','dead','suppressed','expired','cancelled','retry_wait') THEN m.workflow_state ELSE 'queued' END;
END $$;
REVOKE ALL ON FUNCTION public.get_email_confirmation_status(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_confirmation_status(text) TO service_role;
CREATE OR REPLACE FUNCTION public.get_auth_email_context(p_user uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT jsonb_build_object('organization',organization,'recipient',public.get_user_delivery_email(id)) FROM public.user_info WHERE id=p_user);
END $$;
REVOKE ALL ON FUNCTION public.get_auth_email_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_email_context(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.get_email_delivery_overview(p_occasion bigint,p_organization bigint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_org bigint;
BEGIN
 v_org:=coalesce(p_organization,(SELECT organization FROM public.occasions WHERE id=p_occasion));
 IF NOT coalesce(public.email_report_allowed(v_org,p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 RETURN (SELECT jsonb_build_object('messages',count(*),'accepted',count(*) FILTER(WHERE accepted_at IS NOT NULL),
 'delivered',count(*) FILTER(WHERE delivered_at IS NOT NULL),'bounced',count(*) FILTER(WHERE bounced_at IS NOT NULL),
 'complained',count(*) FILTER(WHERE complained_at IS NOT NULL),'opened_messages',count(*) FILTER(WHERE opened_at IS NOT NULL),
 'clicked_messages',count(*) FILTER(WHERE clicked_at IS NOT NULL),'tracking_coverage',count(*) FILTER(WHERE tracking_policy<>'disabled'),
 'unknown',count(*) FILTER(WHERE workflow_state='unknown'),'dead',count(*) FILTER(WHERE workflow_state='dead'),
 'feedback_overdue',count(*) FILTER(WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=email_messages.message_id))) FROM public.email_messages WHERE organization=v_org AND (p_occasion IS NULL OR occasion=p_occasion));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_overview(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_overview(bigint,bigint) TO authenticated,service_role;


-- Source: database/functions/emails/email_health.sql
-- Operator telemetry only. This is the same queue/attempt/event journal, no second state owner.
CREATE OR REPLACE FUNCTION public.get_email_delivery_health() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;v_queue jsonb;v_times jsonb;v_provider jsonb;v_oldest timestamptz;v_post bigint;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity;
 SELECT min(created_at) INTO v_oldest FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now();
 SELECT coalesce(jsonb_object_agg(workflow_state,n),'{}') INTO v_queue FROM (SELECT workflow_state,count(*) n FROM public.email_messages GROUP BY workflow_state) s;
 SELECT jsonb_build_object('commit_to_claim_seconds',avg(extract(epoch FROM a.created_at-m.created_at)),
 'preparation_seconds',avg(extract(epoch FROM m.prepared_at-a.created_at)) FILTER(WHERE m.prepared_at>=a.created_at),
 'ready_to_send_seconds',avg(extract(epoch FROM a.began_at-m.prepared_at)) FILTER(WHERE a.began_at>=m.prepared_at),
 'throttles',count(*) FILTER(WHERE error_code='throttled')) INTO v_times
 FROM public.email_attempts a JOIN public.email_messages m USING(message_id) WHERE a.created_at>now()-interval '1 day';
 SELECT jsonb_build_object('unmatched',count(*) FILTER(WHERE message_id IS NULL),'last_event_at',max(received_at),
 'feedback_lag_seconds',avg(extract(epoch FROM received_at-provider_time)) FILTER(WHERE received_at>now()-interval '1 day')) INTO v_provider FROM public.email_delivery_events;
 SELECT count(*) INTO v_post FROM public.email_messages WHERE workflow_state='accepted' AND post_action_state='pending';
 RETURN jsonb_build_object('queue',v_queue,'oldest_due_at',v_oldest,'timings_24h',v_times,'provider',v_provider,'post_action_backlog',v_post,
 'capacity',jsonb_build_object('paused',c.paused,'quota_at',c.quota_at,'quota_fresh',coalesce(c.quota_at>now()-interval '15 minutes',false),
 'heartbeat_at',c.heartbeat_at,'circuit_until',c.circuit_until,'provider_outage_streak',c.provider_outage_streak,'probe_until',c.probe_until,'incident',c.wake_error,
 'effective_rate',CASE WHEN c.shared_account THEN least(c.max_rate*0.8,c.allocated_rate) ELSE c.max_rate*0.8 END*c.rate_factor,
 'allocated_daily',c.allocated_daily,'provider_sent_24h',c.provider_sent_24h),
 'alerts',to_jsonb(array_remove(ARRAY[
 CASE WHEN NOT c.paused AND (c.quota_at IS NULL OR c.quota_at<now()-interval '15 minutes') THEN 'quota_stale' END,
 CASE WHEN v_oldest<now()-interval '5 minutes' THEN 'oldest_due' END,
 CASE WHEN v_oldest<now()-interval '5 minutes' AND (c.heartbeat_at IS NULL OR c.heartbeat_at<now()-interval '5 minutes') THEN 'worker_heartbeat_stale' END,
 CASE WHEN c.provider_outage_streak>0 THEN 'provider_outage' END,
 CASE WHEN c.wake_error IS NOT NULL THEN 'provider_or_wake_incident' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.email_messages WHERE last_error='post_action_failed') THEN 'post_action_failed' END,
 CASE WHEN EXISTS(SELECT 1 FROM public.email_messages m WHERE accepted_at BETWEEN now()-interval '1 day' AND now()-interval '30 minutes' AND NOT EXISTS(SELECT 1 FROM public.email_delivery_events e WHERE e.message_id=m.message_id)) THEN 'feedback_overdue' END
 ],NULL)));
END $$;
REVOKE ALL ON FUNCTION public.get_email_delivery_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_email_delivery_health() TO service_role;


-- Source: database/functions/users/get_occasion_users_for_edit.sql
-- Historical SMTP invitation hints are a readonly compatibility projection, never canonical delivery evidence.
CREATE OR REPLACE FUNCTION public.get_occasion_sign_in_email_statuses(
  p_occasion bigint
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT COALESCE(public.get_is_editor_view_on_occasion(p_occasion), false)
     AND NOT COALESCE(public.get_is_editor_order_view_on_occasion(p_occasion), false) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  WITH evidence AS (
    SELECT le.recipient_user AS "user",le.created_at AS sent_at
    FROM public.log_emails le
    JOIN public.email_templates et ON et.id::text = le.template
    WHERE le.occasion = p_occasion
      AND le.recipient_user IS NOT NULL
      AND et.code = 'SIGN_IN_CODE'
    UNION ALL
    SELECT m.recipient_user,m.accepted_at FROM public.email_messages m
    WHERE m.occasion=p_occasion AND m.message_kind='sign_in' AND m.recipient_user IS NOT NULL AND m.accepted_at IS NOT NULL
  ), accepted AS (
    SELECT "user",count(*)::integer send_count,min(sent_at) first_sent_at,max(sent_at) last_sent_at FROM evidence GROUP BY "user"
  )
  SELECT COALESCE(
    jsonb_agg(to_jsonb(accepted) ORDER BY accepted."user"),
    '[]'::jsonb
  )
  INTO v_result
  FROM accepted;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_sign_in_email_statuses(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_sign_in_email_statuses(bigint)
  TO authenticated;


CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit(
  p_occasion_id bigint
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_result jsonb;
  v_users jsonb;
BEGIN
  v_result := public.get_occasion_users_for_edit_invitation_base_v1(
    p_occasion_id
  )::jsonb;
  IF COALESCE((v_result->>'code')::integer, 500) <> 200 THEN
    RETURN v_result::json;
  END IF;

  WITH accepted AS (
    SELECT (entry->>'user')::uuid AS "user" FROM jsonb_array_elements(public.get_occasion_sign_in_email_statuses(p_occasion_id)) entry
  )
  SELECT COALESCE(jsonb_agg(
    row.value || jsonb_build_object(
      'data',
      (CASE WHEN jsonb_typeof(row.value->'data') = 'object'
        THEN row.value->'data' ELSE '{}'::jsonb END - 'is_invited'::text)
      || jsonb_build_object('is_invited', accepted."user" IS NOT NULL)
    )
  ), '[]'::jsonb)
  INTO v_users
  FROM jsonb_array_elements(v_result #> '{data,occasion_users}') row
  LEFT JOIN accepted ON accepted."user" = (row.value->>'user')::uuid;

  RETURN jsonb_set(v_result, '{data,occasion_users}', v_users)::json;
END;
$$;

REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit(bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit(bigint)
  TO authenticated;


-- Source: database/functions/emails/queue_payment_reminders.sql
CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT, p_seconds_before_deadline BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
DECLARE
  v_interval INTERVAL;
BEGIN


  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE (occasion=p_occasion_id OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id);


  v_interval := make_interval(secs => p_seconds_before_deadline);




  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id
    ),occ.organization,o.occasion,occ.unit,pi.deadline - CASE WHEN o.occasion=p_occasion_id THEN v_interval ELSE make_interval(secs=>coalesce((form_settings.feature->>'reminder_interval_seconds')::bigint,86400)) END) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id


  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE


  LEFT JOIN public.forms f ON f.key = (o.data->>'form')::uuid
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'ordered'
    AND pi.deadline IS NOT NULL



    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE


    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (form_settings.feature->>'reminder_is_enabled')::boolean IS TRUE


    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, TRUE) IS TRUE;








  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id,
      'is_deposit_reminder', true
    ),occ.organization,o.occasion,occ.unit,(occ.start_time - make_interval(days => (deposit_settings.feature->>'deposit_deadline_days')::int)) - CASE WHEN o.occasion=p_occasion_id THEN v_interval ELSE make_interval(secs=>coalesce((form_settings.feature->>'reminder_interval_seconds')::bigint,86400)) END) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'deposit'
  ) deposit_settings ON TRUE

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE
  LEFT JOIN public.forms f ON f.key = (o.data->>'form')::uuid
  WHERE
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'paid'
    AND pi.deposit_amount IS NOT NULL
    AND pi.paid < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND (form_settings.feature->>'reminder_is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;


-- Source: database/functions/emails/set_payment_deadline.sql
CREATE OR REPLACE FUNCTION public.set_payment_deadline(p_payment_info_id bigint,p_new_deadline timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE o record; v_seconds bigint;
BEGIN
 UPDATE eshop.payment_info SET deadline=p_new_deadline,data=coalesce(data,'{}')||'{"current_version_reminded":false}'::jsonb,
 email_reminder_version=email_reminder_version+1 WHERE id=p_payment_info_id;
 FOR o IN SELECT DISTINCT occ.id,occ.features FROM eshop.orders ord JOIN public.occasions occ ON occ.id=ord.occasion WHERE ord.payment_info=p_payment_info_id LOOP
  SELECT (f->>'reminder_interval_seconds')::bigint INTO v_seconds FROM jsonb_array_elements(o.features) f WHERE f->>'code'='form';
  PERFORM public.queue_payment_reminders(o.id,coalesce(v_seconds,0));
 END LOOP;
END $$;


-- Source: database/functions/emails/fakturoid_email_gate.sql
-- A Fakturoid checkout is not an accepted order until its proforma exists.
-- Keep its confirmation out of the email worker until checkout finalizes it.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  PERFORM public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'command_id',p_command_id,'ticket_order',p_order_payload,'lang',coalesce(nullif(p_language,''),'cs'),
    'fakturoid_pending',v_await_fakturoid),v_organization,p_occasion,v_unit,
    CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END);

END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_fakturoid_ticket_order_state_v1(p_order_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state INTO v_state FROM eshop.orders o WHERE o.id=p_order_id;
  IF v_state IS NULL THEN
    RAISE no_data_found USING MESSAGE='ticket order not found';
  END IF;
  RETURN v_state;
END;
$$;
REVOKE ALL ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid, p_variable_symbol bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_currency text;
  v_payment_id bigint;
  v_existing_vs bigint;
  v_occasion bigint;
  v_queue_id bigint;
  v_impacts jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state,trim(o.currency_code),o.payment_info,o.occasion,pi.variable_symbol
  INTO v_state,v_currency,v_payment_id,v_occasion,v_existing_vs
  FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
  WHERE o.id=p_order_id FOR UPDATE OF o,pi;
  IF v_state IS NULL OR p_command_id IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid Fakturoid completion';
  END IF;
  IF v_state IN ('ordered','paid') THEN
    RETURN v_existing_vs;
  END IF;
  IF v_state<>'preparing_payment' THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  IF v_currency='CZK' THEN
    UPDATE eshop.payment_info SET variable_symbol=p_variable_symbol
    WHERE id=v_payment_id;
  ELSIF v_currency='EUR' THEN
    IF v_existing_vs IS DISTINCT FROM p_variable_symbol THEN
      RAISE check_violation USING MESSAGE='Fakturoid EUR symbol differs from RF base';
    END IF;
  ELSE
    RAISE check_violation USING MESSAGE='unsupported Fakturoid order currency';
  END IF;
  UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
  UPDATE public.email_messages SET target_time=now(),workflow_state='pending',
    data=jsonb_set(data-'fakturoid_pending','{ticket_order,order,payment_info,variable_symbol}',to_jsonb(p_variable_symbol))
  WHERE id=v_queue_id;
  PERFORM public.wake_email_worker();
  SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
  FROM public.occasion_users ou CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component
  WHERE ou.occasion=v_occasion;
  PERFORM public.record_client_sync_commit_v1(v_occasion,
    'fakturoid.order.complete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order_id,'operation','update',
      'safeLabel','Order payment ready','changedFields',
      jsonb_build_array('state','payment_info'))),'{}',v_impacts,'[]',
    'service',NULL);
  RETURN p_variable_symbol;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_occasion bigint;
  v_queue_id bigint;
  v_before_users uuid[];
  v_abort_command uuid := extensions.gen_random_uuid();
  v_hash text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state,o.occasion INTO v_state,v_occasion
  FROM eshop.orders o WHERE o.id=p_order_id FOR UPDATE;
  IF v_state='storno' THEN RETURN; END IF;
  IF v_state IS DISTINCT FROM 'preparing_payment' OR p_command_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.email_messages q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
  FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order_id,'reason','fakturoid_failed')::text,'UTF8'),'sha256'),'hex');
  PERFORM public.begin_anonymous_client_mutation_v1(v_abort_command,
    'inventory.order.fakturoid_abort',v_occasion,extensions.gen_random_uuid(),v_hash);
  UPDATE public.email_messages SET workflow_state='cancelled',last_error='fakturoid_aborted' WHERE id=v_queue_id;
  PERFORM public.update_order_and_tickets_to_storno_221(p_order_id);
  PERFORM public.complete_profile_inventory_membership_mutation_v1(
    v_abort_command,v_occasion,'inventory.order.fakturoid_abort',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',p_order_id,'operation','update','safeLabel','Failed order',
      'changedFields',jsonb_build_array('state','tickets','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order_id),'service');
END;
$$;
REVOKE ALL ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  TO service_role;


-- Source: database/functions/eshop/create_ticket_order.sql
CREATE OR REPLACE FUNCTION public.create_ticket_order_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key;

        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;

        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        INSERT INTO eshop.orders (created_at, updated_at, occasion, form)
        VALUES (now, now, occasion_id, form_id)
        RETURNING id INTO order_id;

        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            INSERT INTO eshop.tickets (state, occasion, ticket_symbol, note, created_at, updated_at)
            VALUES ('ordered', occasion_id, ticket_symbol, ticket_note, now, now)
            RETURNING id INTO ticket_id;

            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        generated_variable_symbol := generate_payment_variable_symbol(bank_account_id, form_id);
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_reminder_interval BIGINT;
                v_reminder_is_enabled BOOLEAN;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- Only queue reminder if deadline is in the future
                    IF v_deposit_deadline_ts > NOW() THEN
                        -- Get reminder interval from occasion form feature
                        SELECT elem->>'reminder_interval_seconds'
                        INTO v_reminder_interval
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        -- Check if reminder is enabled on the form feature
                        SELECT (elem->>'reminder_is_enabled')::boolean
                        INTO v_reminder_is_enabled
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        IF COALESCE(v_reminder_is_enabled, FALSE) AND v_reminder_interval IS NOT NULL THEN
                            PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',
                                jsonb_build_object('order_id',order_id,'is_deposit_reminder',true),organization_id,occasion_id,unit_id,
                                v_deposit_deadline_ts-make_interval(secs=>v_reminder_interval));
                        END IF;
                    END IF;
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;


-- Source: database/functions/eshop_orders/update_order_and_tickets_to_paid.sql
CREATE OR REPLACE FUNCTION public.update_order_and_tickets_to_paid(order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id bigint;
    current_state text;
BEGIN
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now(),email_payment_version=email_payment_version+1
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state IN ('ordered','expired','paid');

    -- Queue deposit-paid or fully-paid email for orders with deposit
    DECLARE
        v_deposit_amount NUMERIC;
        v_total_amount NUMERIC;
        v_total_paid NUMERIC;
        v_email_code TEXT;
        v_org_id BIGINT;
        v_unit_id BIGINT;
    BEGIN
        -- Fetch payment info for this order
        SELECT pi.deposit_amount, pi.amount, pi.paid
        INTO v_deposit_amount, v_total_amount, v_total_paid
        FROM eshop.payment_info pi
        JOIN eshop.orders o ON o.payment_info = pi.id
        WHERE o.id = order_id;

        -- Only queue emails for deposit orders. The template handler branches
        -- internally on amountPaid >= totalAmount to render either the
        -- deposit-paid copy (with remaining balance + QR) or the fully-paid copy.
        IF v_deposit_amount IS NOT NULL AND v_total_paid >= v_deposit_amount THEN
            -- Get organization and unit from occasion
            SELECT occ.organization, occ.unit
            INTO v_org_id, v_unit_id
            FROM public.occasions occ
            WHERE occ.id = occasion_id;

            v_email_code := 'TICKET_ORDER_PAYMENT_DONE';

            IF v_email_code IS NOT NULL THEN
                PERFORM public.enqueue_order_email(v_email_code,jsonb_build_object('order_id',order_id),v_org_id,occasion_id,v_unit_id);
            END IF;
        END IF;
    END;

    PERFORM public.enqueue_paid_order_tickets(order_id);

    -- Return a success message with a status code 200
    RETURN jsonb_build_object('code', 200, 'message', 'Update successful');
EXCEPTION WHEN OTHERS THEN
    -- Rollback is automatic on exception
    RETURN jsonb_build_object(
        'code', 500,
        'message', SQLERRM,
        'detail', coalesce(SQLERRM, 'An unexpected error occurred')
    );
END;
$function$;


-- Source: database/functions/eshop_orders/recalculate_order_payment_status.sql
CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_payment_info_id bigint;
    v_paid numeric;
    v_deposit_amount numeric;
    v_price numeric;
    v_state text;
BEGIN
    -- Get Order Details
    SELECT payment_info, price, state INTO v_payment_info_id, v_price, v_state
    FROM eshop.orders
    WHERE id = p_order_id;

    IF v_payment_info_id IS NULL THEN
        RETURN;
    END IF;

    -- Get Paid Amount and Deposit Amount from Payment Info
    SELECT paid, deposit_amount INTO v_paid, v_deposit_amount
    FROM eshop.payment_info
    WHERE id = v_payment_info_id;

    -- Update Logic
    IF COALESCE(v_paid, 0) >= COALESCE(v_deposit_amount, v_price) THEN
        -- Fully Paid (or Deposit Paid) -> Move to Paid
        IF v_state != 'paid' AND (v_state = 'ordered' OR v_state = 'created' OR v_state = 'expired') THEN
             PERFORM public.update_order_and_tickets_to_paid(p_order_id);
        END IF;
    ELSE
        -- Underpaid -> Revert to Ordered (if currently Paid)
        IF v_state IN ('paid','sent') THEN
            PERFORM public.cancel_order_email_intents(p_order_id);
            -- Revert Order
            UPDATE eshop.orders
            SET state = 'ordered', updated_at = now(),email_payment_version=email_payment_version+1
            WHERE id = p_order_id;

            -- Revert Tickets (only those that are 'paid')
            UPDATE eshop.tickets
            SET state = 'ordered', updated_at = now() -- Reverted to 'ordered' as 'valid' is not a supported state

            FROM eshop.order_product_ticket
            WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
            AND eshop.order_product_ticket."order" = p_order_id
            AND eshop.tickets.state IN ('paid','sent');
        END IF;
    END IF;
END;
$$;


-- Source: database/functions/eshop_orders/update_order_and_tickets_to_storno.sql
CREATE OR REPLACE FUNCTION update_order_and_tickets_to_storno_221(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_ids BIGINT[];
    updated_order_data jsonb;
BEGIN
    PERFORM public.cancel_order_email_intents(order_id);
    -- Retrieve all ticket ids associated with the order
    SELECT ARRAY_AGG(t.id) INTO ticket_ids
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    WHERE opt."order" = order_id;

    -- Check if the order exists and has associated tickets
    IF ticket_ids IS NULL THEN
        -- This is not an error, just an order with no tickets yet.
        -- But we can still storno the order itself.
        RAISE NOTICE 'No tickets found for order %, proceeding to storno order shell.', order_id;
    END IF;

    -- Call the helper to storno all tickets and their relations
    -- The helper function gracefully handles an empty/NULL array
    PERFORM internal_storno_tickets_221(ticket_ids);

    -- Set the order state to 'storno', price to 0, and update the data field
    UPDATE eshop.orders
    SET state = 'storno',
        price = 0,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object('tickets', '[]'::jsonb),
        updated_at = NOW()
    WHERE id = order_id
    RETURNING data INTO updated_order_data;

    -- Save the change to orders_history by inserting the updated order row
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        order_id,
        'storno',
        0,
        updated_order_data,
        NOW()
    );

END;
$$;


-- Source: database/functions/eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_paid             numeric;
  v_price            numeric;
  v_new_state        text;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
  v_current_products_for_compare jsonb;
BEGIN
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) decide new state based on money received */
  SELECT COALESCE(pi.paid,0), o.price
    INTO v_paid, v_price
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON o.payment_info = pi.id
   WHERE o.id = v_order_id;

  v_new_state := CASE
                   WHEN v_paid >= v_price AND v_price > 0 THEN 'paid'
                   WHEN v_price <= 0 THEN 'paid'
                   ELSE 'ordered'
                 END;

  IF v_new_state = 'paid' THEN
    IF NOT EXISTS (
      SELECT 1 FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
      WHERE opt."order" = v_order_id AND t.state <> 'sent'
    ) THEN
      v_new_state := 'sent';
    END IF;
  END IF;

  PERFORM public.cancel_order_email_intents(v_order_id);
  UPDATE eshop.orders
     SET email_payment_version=email_payment_version+1, state      = v_new_state,
         updated_at = now()
   WHERE id = v_order_id;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM apply_allocations(v_order_id);
  PERFORM public.enqueue_paid_order_tickets(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_new_state,
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;


-- Source: database/functions/eshop_orders/get_orders_tab_data.sql
CREATE OR REPLACE FUNCTION get_orders_tab_data(
    p_occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_orders_data JSONB;
    v_forms_data JSONB;
BEGIN

    SELECT get_orders(p_occasion_link, NULL, '{}'::jsonb) INTO v_orders_data;

    IF (v_orders_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_orders failed: %', v_orders_data->>'message';
    END IF;

    SELECT get_all_forms_with_fields(p_occasion_link) INTO v_forms_data;

    IF (v_forms_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_all_forms_with_fields failed: %', v_forms_data->>'message';
    END IF;

    RETURN (v_orders_data->'data') || jsonb_build_object('forms', v_forms_data->'data', 'email_delivery',
      public.get_order_email_summaries((SELECT id FROM public.occasions WHERE link=p_occasion_link),
        ARRAY(SELECT (ord->>'id')::bigint FROM jsonb_array_elements(v_orders_data#>'{data,orders}') ord)));
END;
$$;


-- Source: database/functions/others/delete_occasion.sql
CREATE OR REPLACE FUNCTION public.delete_occasion_internal_v1(oc bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_id BIGINT;
BEGIN

  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = oc;

  PERFORM check_is_manager_on_unit(unit_id);

-- ***********************************************************
  -- 0. SAFETY CHECK: Strict Order Check
  --    Prevent deletion if ANY order exists (even storno).
  -- ***********************************************************
  IF EXISTS (
      SELECT 1
      FROM eshop.orders
      WHERE occasion = oc
  ) THEN
      RAISE EXCEPTION 'Cannot delete occasion % because it contains orders (including storno).', oc;
  END IF;

  -- ***********************************************************
  -- 1. Delete records that depend on 'events'.
  -- ***********************************************************
  DELETE FROM public.event_groups
    WHERE event_parent IN (SELECT id FROM public.events WHERE occasion = oc)
       OR event_child  IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_roles
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users_saved
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.exclusive_events
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  -- ***********************************************************
  -- 2. Delete the 'events' themselves.
  -- ***********************************************************
  DELETE FROM public.events
    WHERE occasion = oc;

  -- ***********************************************************
  -- 3. Delete 'orders' dependent records.
  -- ***********************************************************
  DELETE FROM eshop.order_product_ticket
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.orders_history
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.bank_account_requests
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  -- ***********************************************************
  -- 4. Delete form-related records.
  -- ***********************************************************
  DELETE FROM public.form_fields
    WHERE form IN (SELECT id FROM public.forms WHERE occasion = oc);

  DELETE FROM public.forms
    WHERE occasion = oc;

  -- ***********************************************************
  -- 5. Delete records from tables that reference the occasion directly.
  -- ***********************************************************
  DELETE FROM public.email_templates
    WHERE occasion = oc;

  DELETE FROM public.email_wrappers
    WHERE occasion = oc;

  DELETE FROM public.information
    WHERE occasion = oc;

  DELETE FROM public.information_hidden
    WHERE occasion = oc;

  DELETE FROM public.log_notifications
    WHERE occasion = oc;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='occasion_deleted',data='{}',prepared=NULL,recipient=NULL,occasion=NULL,unit=NULL
    WHERE occasion = oc;

  DELETE FROM public.log_emails
    WHERE occasion = oc;

  DELETE FROM public.news
    WHERE occasion = oc;

  DELETE FROM public.occasion_users
    WHERE occasion = oc;

  DELETE FROM public.user_news
    WHERE occasion = oc;

  DELETE FROM public.places
    WHERE occasion = oc;

  DELETE FROM public.role_info
    WHERE occasion = oc;

  DELETE FROM public.user_groups
    WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion = oc);

  DELETE FROM public.user_group_info
    WHERE occasion = oc;

  DELETE FROM public.exclusive_groups
    WHERE occasion = oc;

  -- ***********************************************************
  -- 6. Delete remaining records from the eshop schema.
  -- ***********************************************************
  DELETE FROM eshop.tickets
    WHERE occasion = oc;

  DELETE FROM eshop.spots
    WHERE occasion = oc;

  DELETE FROM eshop.products
    WHERE occasion = oc;

  DELETE FROM eshop.product_types
    WHERE occasion = oc;

  DELETE FROM eshop.planned_changes
    WHERE occasion = oc;

  DELETE FROM eshop.bank_account_requests
    WHERE occasion = oc;

  DELETE FROM eshop.blueprints
    WHERE occasion = oc;

  -- Delete orders (Safe now: we checked for non-storno orders at step 0,
  -- and deleted dependents in step 3).
  DELETE FROM eshop.orders
    WHERE occasion = oc;

  -- ***********************************************************
  -- 7. Null out referencing images.
  -- ***********************************************************
  UPDATE public.images
    SET occasion = NULL
    WHERE occasion = oc;

  -- ***********************************************************
  -- 8. Finally, delete the occasion itself.
  -- ***********************************************************
  DELETE FROM public.occasions
    WHERE id = oc;

  RETURN;
END;
$$;


-- Source: database/functions/others/update_occasion.sql
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_form_link_base TEXT;
     v_form_link_suffix INTEGER;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features INTO final_unit, old_features FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;
         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = COALESCE(input_data->>'link', link),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             input_data->>'link',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
     END IF;

     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             IF v_form_link IS NULL THEN
                 -- Occasion slugs and form slugs are separate namespaces.
                 -- An automatic default must not block an unrelated settings save.
                 v_form_link_base := COALESCE(NULLIF(updated_occ.link, ''), 'registration');
                 v_form_link := v_form_link_base;
                 v_form_link_suffix := 0;
                 LOOP
                     -- Serialize automatic allocation for each candidate, including
                     -- candidates that are another occasion's unsuffixed slug.
                     PERFORM pg_advisory_xact_lock(hashtextextended('default-form:' || v_form_link, 0));
                     EXIT WHEN NOT EXISTS (SELECT 1 FROM public.forms WHERE link = v_form_link);
                     v_form_link_suffix := v_form_link_suffix + 1;
                     v_form_link := v_form_link_base || '-' || occ_id::text ||
                         CASE WHEN v_form_link_suffix = 1 THEN '' ELSE '-' || v_form_link_suffix::text END;
                 END LOOP;
             END IF;
             -- Explicit links still use create_form's collision validation.
             PERFORM create_form(occ_id, v_form_link, 'Registration');
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Find the associated form to attach the blueprint to
         SELECT id, blueprint INTO v_form_id, v_form_blueprint
           FROM public.forms
          WHERE occasion = occ_id
          LIMIT 1;

         -- If a form exists and it doesn't already have a blueprint, create one.
         IF FOUND AND v_form_blueprint IS NULL THEN
             INSERT INTO eshop.blueprints(configuration, occasion, organization, created_at, updated_at)
             VALUES ('{"dimensions": {"width": 28, "height": 52}}'::jsonb, occ_id, COALESCE(updated_occ.organization, 1), now, now)
             RETURNING id INTO new_blueprint_id;

             UPDATE public.forms
                SET blueprint = new_blueprint_id,
                    updated_at = now
              WHERE id = v_form_id;
         END IF;
     END IF;
 END;
 $$;

CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.update_occasion_internal_v1(input_data);
END;
$$;


-- Source: database/functions/seed/crons.sql
CREATE OR REPLACE FUNCTION setup_crons(p_project_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $func$
BEGIN
  -- Security Check
  IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
      RAISE EXCEPTION 'Access Denied: Service role required.';
  END IF;

  -- Schedule the apply_planned_changes cron job (runs every minute)
  PERFORM cron.schedule(
    'apply_planned_changes',
    '*/1 * * * *',
    'SELECT apply_planned_changes()'
  );

  -- Schedule the synchronize_orders cron job (runs every 10 minutes)
  PERFORM cron.schedule(
      'synchronize_orders',
      '*/10 * * * *',
      format($$
        SELECT net.http_post(
          url := '%s/functions/v1/synchronize-orders'::text,
          body := jsonb_build_object('requestSecret', public.generate_request_secret(3600))
        );
      $$, p_project_url)
  );

  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
END;
$func$;


-- Remove obsolete RPCs and duplicate legacy reminder producers discovered in the baseline.
DROP FUNCTION IF EXISTS public.claim_due_queue_emails_v1(integer);
DROP FUNCTION IF EXISTS public.release_queue_email_v1(bigint,text);
DROP FUNCTION IF EXISTS public.remove_from_queue_emails(bigint);
DROP FUNCTION IF EXISTS public.get_due_queue_emails();
DROP FUNCTION IF EXISTS public.get_orders_for_ticket_sending();
DROP FUNCTION IF EXISTS public.queue_deposit_reminders(bigint,bigint);
DROP FUNCTION IF EXISTS public.queue_surcharge_reminders(bigint,bigint);
-- Preserve the former implicit paid-ticket backlog without assuming absence of SMTP acceptance.
DO $$ DECLARE o record; v_result jsonb; BEGIN
 FOR o IN SELECT ord.id,ord.data->>'email' recipient,ord.email_payment_version,oc.organization,oc.id occ_id,oc.unit FROM eshop.orders ord JOIN public.occasions oc ON oc.id=ord.occasion
 WHERE ord.state='paid' AND oc.is_order_synchronization_enabled AND ord.data ? 'email'
 AND (coalesce(ord.price,0)<>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(oc.features) f WHERE f->>'code'='ticket' AND (f->>'is_enabled')::boolean)) LOOP
  IF nullif(btrim(o.recipient),'') IS NULL OR length(o.recipient)>320 OR position('@' in o.recipient)=0 THEN
   -- Historical addresses may violate today's producer contract. Preserve the
   -- candidate and its original address as trouble; never send or silently skip it.
   INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,
     recipient,order_id,source_version,workflow_state,last_error,tracking_policy)
   VALUES(now(),'TICKET_ORDER_PAYMENT_DONE',jsonb_build_object('order_id',o.id),o.organization,o.occ_id,o.unit,
     'order_tickets','legacy-invalid-ticket:'||o.id,encode(extensions.digest(jsonb_build_object('order_id',o.id,'recipient',o.recipient)::text,'sha256'),'hex'),
     o.recipient,o.id,o.email_payment_version,'unknown','legacy_ticket_invalid_recipient_requires_reconciliation','open');
  ELSE
   v_result:=public.enqueue_order_email('ORDER_TICKETS',jsonb_build_object('order_id',o.id),o.organization,o.occ_id,o.unit);
   UPDATE public.email_messages SET workflow_state='unknown',last_error='legacy_ticket_candidate_requires_reconciliation' WHERE message_id=(v_result->>'message_id')::uuid;
  END IF;
 END LOOP;
END $$;
-- Old cron names cannot run alongside the canonical worker.
DO $$ DECLARE job record; BEGIN
 IF EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
  FOR job IN SELECT jobid FROM cron.job WHERE jobname IN ('process_email_queue','festapp_canonical_process_email_queue') LOOP PERFORM cron.unschedule(job.jobid);END LOOP;
  PERFORM cron.schedule('festapp_canonical_process_email_queue','*/1 * * * *','SELECT public.recover_email_delivery()');
 END IF;
END $$;
-- Fail closed if a string-bodied active function still refers to the old queue.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND position('queue_emails' in prosrc)>0) THEN
  RAISE EXCEPTION 'active_legacy_email_function_remains';
 END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
