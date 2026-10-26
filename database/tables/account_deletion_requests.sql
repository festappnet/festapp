CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  organization bigint NOT NULL REFERENCES public.organizations(id),
  status text NOT NULL DEFAULT 'email_pending' CHECK (status IN (
    'email_pending','email_sent','deletion_pending','completed','revoked','failed'
  )),
  token_hash text UNIQUE CHECK (token_hash IS NULL OR token_hash ~ '^[0-9a-f]{64}$'),
  used_token_hash text UNIQUE CHECK (used_token_hash IS NULL OR used_token_hash ~ '^[0-9a-f]{64}$'),
  masked_email text,
  expires_at timestamptz NOT NULL,
  cooldown_until timestamptz NOT NULL,
  public_deleted boolean NOT NULL DEFAULT false,
  auth_deleted boolean NOT NULL DEFAULT false,
  onesignal_deleted boolean NOT NULL DEFAULT false,
  attempt_count integer NOT NULL DEFAULT 0,
  error_class text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  email_sent_at timestamptz,
  claimed_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE UNIQUE INDEX IF NOT EXISTS account_deletion_one_active_user_idx
  ON public.account_deletion_requests(user_id)
  WHERE status IN ('email_pending','email_sent','deletion_pending');
CREATE INDEX IF NOT EXISTS account_deletion_retry_idx
  ON public.account_deletion_requests(status, updated_at)
  WHERE status IN ('deletion_pending','failed');

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.account_deletion_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.account_deletion_requests TO service_role;
