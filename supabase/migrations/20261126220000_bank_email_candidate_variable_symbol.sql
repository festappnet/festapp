-- Show each payable order's variable symbol when confirming an email-detected bank payment.

-- SOURCE: eshop_bank_sync/bank_sync_email_confirmation.sql
CREATE OR REPLACE FUNCTION public.bank_sync_email_payable_targets_for_ids_internal(p_account bigint,p_currency text,p_ids bigint[])
RETURNS TABLE(payment_info_id bigint,order_id bigint,occasion_id bigint,candidate jsonb)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH eligible AS MATERIALIZED (
  SELECT pi.id,pi.amount,pi.currency_code,pi.variable_symbol,o.id AS order_id,o.occasion,o.order_symbol,o.order_sequence,o.state,o.data
  FROM eshop.payment_info pi JOIN eshop.orders o ON o.payment_info=pi.id JOIN public.occasions oc ON oc.id=o.occasion
  WHERE pi.id=ANY(p_ids) AND pi.bank_account=p_account AND pi.payment_method='bank'
   AND upper(trim(pi.currency_code))=upper(trim(p_currency)) AND pi.amount>0
   AND (o.state IN ('created','ordered','expired')
     OR (o.state IN ('paid','sent') AND pi.deposit_amount>0))
   AND NOT public.is_demo_occasion(o.occasion) AND NOT public.is_demo_bank_account(p_account)
   AND public.can_write_orders(o.occasion)
   AND EXISTS(SELECT FROM eshop.unit_bank_accounts a WHERE a.unit=oc.unit AND a.bank_account=p_account)
 ), totals AS MATERIALIZED (
  SELECT * FROM public.payment_financial_totals_bulk_internal((SELECT coalesce(array_agg(id::bigint),'{}'::bigint[]) FROM eligible))
 )
 SELECT e.id::bigint,e.order_id::bigint,e.occasion::bigint,jsonb_build_object(
  'payment_info_id',e.id,'order_id',e.order_id,'order_symbol',e.order_symbol,'order_number',e.order_sequence,
  'state',e.state,'customer_name',concat_ws(' ',coalesce(e.data->>'name',e.data->>'first_name'),coalesce(e.data->>'surname',e.data->>'last_name')),
  'customer_email',e.data->>'email','variable_symbol',e.variable_symbol::text,
  'remaining_due',greatest(e.amount-t.available,0),'currency',upper(trim(e.currency_code)))
 FROM eligible e JOIN totals t ON t.payment_id=e.id WHERE e.amount>t.available;
$$;
