-- One campaign per form. Contacts are independent of orders and waiting tickets.
CREATE TABLE IF NOT EXISTS public.sale_opening_campaigns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 form_id bigint NOT NULL UNIQUE REFERENCES public.forms(id) ON DELETE CASCADE,
 phase text NOT NULL DEFAULT 'armed' CHECK (phase IN ('armed','dispatching','completed','cancelled')),
 revision bigint NOT NULL DEFAULT 1,
 opened_at timestamptz,
 closed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 next_maintenance_at timestamptz NOT NULL DEFAULT now(),
 retained_counts jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS public.sale_opening_subscriptions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 campaign_id uuid NOT NULL REFERENCES public.sale_opening_campaigns(id) ON DELETE CASCADE,
 email_normalized text NOT NULL CHECK (length(email_normalized)<=320 AND email_normalized=lower(btrim(email_normalized))),
 lang text NOT NULL CHECK (lang IN ('cs','en','sk','de','pl','uk')),
 state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','unsubscribed','closed')),
 version bigint NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(),
 closed_at timestamptz,
 UNIQUE(campaign_id,email_normalized)
);
CREATE TABLE IF NOT EXISTS public.sale_opening_capabilities (
 token_hash text PRIMARY KEY CHECK (token_hash ~ '^[0-9a-f]{64}$'),
 subscription_id uuid NOT NULL REFERENCES public.sale_opening_subscriptions(id) ON DELETE CASCADE,
 purpose text NOT NULL CHECK (purpose='unsubscribe'),
 source_version bigint NOT NULL,
 envelope jsonb NOT NULL,
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz
);
CREATE INDEX IF NOT EXISTS sale_opening_dispatch_idx ON public.sale_opening_subscriptions(campaign_id,created_at,id) WHERE state='active';
CREATE INDEX IF NOT EXISTS sale_opening_capability_subscription_idx ON public.sale_opening_capabilities(subscription_id);
ALTER TABLE public.sale_opening_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_opening_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_opening_capabilities ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sale_opening_campaigns,public.sale_opening_subscriptions,public.sale_opening_capabilities FROM PUBLIC,anon,authenticated,service_role;
