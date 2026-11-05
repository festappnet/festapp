-- Retire the unreleased verification contract on existing disposable previews.
-- Historical/unknown sends remain fenced and are never turned into retries.
UPDATE public.email_messages SET workflow_state='cancelled',prepared=NULL,lease_token=NULL,lease_until=NULL
 WHERE message_kind='sale_opening_confirmation' AND workflow_state IN ('pending','preparing','retry_wait','blocked');
DELETE FROM public.sale_opening_capabilities WHERE purpose='confirm';
ALTER TABLE public.sale_opening_capabilities DROP CONSTRAINT IF EXISTS sale_opening_capabilities_purpose_check;
ALTER TABLE public.sale_opening_capabilities ADD CONSTRAINT sale_opening_capabilities_purpose_check CHECK(purpose='unsubscribe');
UPDATE public.sale_opening_subscriptions SET state='closed',closed_at=coalesce(closed_at,now()) WHERE state='pending';
ALTER TABLE public.sale_opening_subscriptions DROP CONSTRAINT IF EXISTS sale_opening_subscriptions_state_check;
ALTER TABLE public.sale_opening_subscriptions ALTER COLUMN state SET DEFAULT 'active';
ALTER TABLE public.sale_opening_subscriptions ADD CONSTRAINT sale_opening_subscriptions_state_check CHECK(state IN ('active','unsubscribed','closed'));
ALTER TABLE public.sale_opening_subscriptions DROP COLUMN IF EXISTS verified_at;
ALTER TABLE public.sale_opening_subscriptions DROP COLUMN IF EXISTS last_confirmation_at;
DELETE FROM public.email_templates WHERE code='sale_opening_confirmation' AND occasion IS NULL AND unit IS NULL AND organization IS NULL;
