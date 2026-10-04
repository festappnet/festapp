from pathlib import Path
import os
os.chdir(Path(__file__).resolve().parents[2])
files=['emails/email_schema.sql','users/get_can_reset_user_password.sql','users/reset_user_password.sql','emails/email_domain.sql','emails/email_queue.sql','emails/email_reporting.sql','emails/email_health.sql','users/get_occasion_users_for_edit.sql','emails/queue_payment_reminders.sql','emails/set_payment_deadline.sql','emails/fakturoid_email_gate.sql','eshop/create_ticket_order.sql','eshop_orders/update_order_and_tickets_to_paid.sql','eshop_orders/recalculate_order_payment_status.sql','eshop_orders/update_order_and_tickets_to_storno.sql','eshop_orders/update_ticket_products_ws.sql','eshop_orders/get_orders_tab_data.sql','others/delete_occasion.sql','others/update_occasion.sql','seed/crons.sql']
s='-- Canonical email cutover. Maintenance and reviewed function bundle required. Starts paused.\nBEGIN;\n'
for name in files:s+='\n-- Source: database/functions/'+name+'\n'+(Path('database/functions')/name).read_text()+'\n'
s+='''
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
'''
Path('supabase/migrations/20261003200000_canonical_email_delivery.sql').write_text(s)
