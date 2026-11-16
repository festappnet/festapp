-- An explicit forward retirement; no history or financial record is erased.
UPDATE eshop.customer_order_change_policies SET policy=policy-'move',revision=revision+1,updated_at=clock_timestamp() WHERE policy ? 'move';
DROP FUNCTION public.remap_customer_move_answers_internal(jsonb,bigint,bigint,jsonb,boolean);
DROP FUNCTION public.customer_move_preview_internal(bigint,bigint);
DROP FUNCTION public.customer_move_targets_internal(bigint);
DROP FUNCTION public.move_customer_order_domain_internal(bigint,bigint);
DROP FUNCTION public.order_term_occasion_internal(bigint);
DROP FUNCTION public.refresh_order_wallet_term_domain_internal(bigint);
DROP FUNCTION public.lock_customer_order_change_internal(bigint,bigint);
ALTER TABLE public.forms DROP CONSTRAINT forms_term_interval;
ALTER TABLE public.forms DROP COLUMN term_start_at, DROP COLUMN term_end_at;
ALTER TABLE eshop.customer_order_change_requests DROP COLUMN target_form_id;
ALTER TABLE eshop.customer_order_change_requests DROP CONSTRAINT customer_order_change_requests_operation_check,
 ADD CONSTRAINT customer_order_change_requests_operation_check CHECK(operation='cancel');
ALTER TABLE eshop.customer_order_change_capabilities DROP CONSTRAINT customer_order_change_capabilities_operation_check,
 ADD CONSTRAINT customer_order_change_capabilities_operation_check CHECK(operation IN ('edit','cancel','withdraw'));
