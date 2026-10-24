-- Adoption uses stable actor/operation identity, never a new policy revision.
INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
SELECT 'reception.'||operation||'.actor',actor::text,bucket,count,bucket+interval '2 minutes'
FROM public.reception_rate_limits WHERE bucket>now()-interval '1 minute' AND count>0 AND operation IN ('create','issue','revoke');
DROP TABLE public.reception_rate_limits;
-- Preserve report work already consumed before replacing the history counter.
INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
SELECT 'cleaning.report.actor',created_by::text,
 to_timestamp(floor(extract(epoch FROM created_at)/300)*300),count(*),
 to_timestamp(floor(extract(epoch FROM created_at)/300)*300)+interval '20 minutes'
FROM public.cleaning_reports WHERE created_by IS NOT NULL AND created_at>now()-interval '15 minutes'
GROUP BY created_by,to_timestamp(floor(extract(epoch FROM created_at)/300)*300);
